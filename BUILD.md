# Crypto Paper Trader — Staged Build Plan 

## Stack Summary

| Layer | Technology | Host |
|---|---|---|
| Backend | Go + Gin | Fly.io |
| Mobile | React Native + Expo | EAS / App Store |
| Database | PostgreSQL | Fly.io Postgres |
| Queue | Asynq + Redis | Upstash |
| Auth | **Clerk** | clerk.com |
| Market Data | CCXT (WebSockets) | Go server |
| Real-time Delivery | SSE (active) + Push (background) | Go server |
| AI Analysis | Claude API (Anthropic) | Go worker |
| Payments | Stripe | stripe.com |
| CI/CD | GitHub Actions + EAS Build | GitHub |

---

## Monorepo Layout

```
cryptopapertrade-api/
├── apps/
│   ├── server/          # Go backend (Gin)
│   ├── mobile/          # React Native (Expo)
│   └── desktop/         # Future: Tauri (placeholder — do not build yet)
├── packages/
│   └── types/           # Shared TypeScript types (kept in sync with Go API shapes)
├── .github/
│   └── workflows/
├── pnpm-workspace.yaml
└── BUILD.md
```

---

## Stage Overview (Claude Code Sessions)

| Stage | Name | Output | Blocks |
|---|---|---|---|
| **0** | Monorepo Skeleton | Folder structure, tooling, CI stub | Nothing |
| **1** | DB Schema + Go Foundation | Migrations, models, DB pool, health check | Stage 2+ |
| **2** | Clerk Auth | User sync webhook, JWT middleware, `/me` endpoint | Stage 3+ |
| **3** | Price Watcher | CCXT WebSocket feed, in-memory sync.Map | Stage 4 |
| **4** | Trade Matching Engine | Goroutine price comparator, auto-close trades | Stage 5 |
| **5** | Trade CRUD API | REST endpoints, pagination, validation | Stage 6 |
| **6** | AI Analysis Worker | Asynq queue, Claude API, post-mortem storage | Stage 7 |
| **7** | SSE + Push Delivery | Price SSE stream, FCM/APNs push notifications | Stage 8 |
| **8** | Mobile App Shell | Expo app, Clerk auth flow, navigation | Stage 9 |
| **9** | Mobile Screens | Dashboard, New Trade, Detail, History, Analysis | Stage 10 |
| **10** | Stripe Subscriptions | Checkout, webhooks, subscription gating | Stage 11 |
| **11** | CI/CD + Deploy | GitHub Actions, Fly.io deploy, EAS builds | Final |
| **12** | Polish + Testing | Unit tests, error handling, monitoring, rate limits | Ship |

---

## Stage 0 — Monorepo Skeleton

**Goal:** Every developer (and Claude Code) can clone and immediately understand where everything lives.

**Tasks:**
- [ ] Init repo with `pnpm-workspace.yaml`
- [ ] Create `apps/server` with Go module (`go mod init`)
- [ ] Create `apps/mobile` with `npx create-expo-app`
- [ ] Create `apps/desktop/` as an empty placeholder directory with a `README.md` noting "Tauri app — not started yet"
- [ ] Create `packages/types` with empty `package.json`
- [ ] Add root `.gitignore` (Go, Node, .env)
- [ ] Add `.env.example` with all required keys (no values)
- [ ] Add `docker-compose.yml` for local Postgres + Redis
- [ ] Add stub `README.md`

**Deliverable:** `docker-compose up` starts Postgres and Redis. Go and Expo apps can run independently.

**Environment variables needed at this stage:**
```
DATABASE_URL=
REDIS_URL=
CLERK_SECRET_KEY=
CLERK_WEBHOOK_SECRET=
```

---

## Stage 1 — DB Schema + Go Foundation

**Goal:** A running Go server that connects to Postgres, runs migrations, and returns a health check.

**Tasks:**
- [ ] Choose migration tool: `golang-migrate` (file-based, no ORM)
- [ ] Write initial migration: `users`, `trades`, `ai_critiques`, `subscriptions` tables (see schema below)
- [ ] Go packages: `gin-gonic/gin`, `jackc/pgx/v5`, `joho/godotenv`
- [ ] `internal/database/` — connection pool, ping on startup
- [ ] `internal/models/` — Go structs matching DB tables
- [ ] `GET /health` endpoint
- [ ] Validate all env vars at startup; crash-fail if missing

**Schema:**
```sql
-- users (synced from Clerk webhook)
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    clerk_id    VARCHAR(255) UNIQUE NOT NULL,
    email       VARCHAR(255) UNIQUE NOT NULL,
    name        VARCHAR(255),
    avatar_url  TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- trades
CREATE TABLE trades (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    symbol       VARCHAR(20) NOT NULL,       -- e.g. BTC/USDT
    exchange     VARCHAR(50) NOT NULL,
    side         VARCHAR(10) NOT NULL,       -- 'long' | 'short'
    entry_price  NUMERIC(20,8) NOT NULL,
    exit_price   NUMERIC(20,8),
    stop_loss    NUMERIC(20,8) NOT NULL,      -- required; engine auto-closes when price hits
    take_profit  NUMERIC(20,8) NOT NULL,     -- required; engine auto-closes when price hits
    quantity     NUMERIC(20,8) NOT NULL,
    status       VARCHAR(20) DEFAULT 'open', -- 'open' | 'closed'
    pnl          NUMERIC(20,8),
    pnl_percent  NUMERIC(10,4),
    notes        TEXT,
    opened_at    TIMESTAMPTZ DEFAULT NOW(),
    closed_at    TIMESTAMPTZ
);
CREATE INDEX idx_trades_user_status ON trades(user_id, status);
CREATE INDEX idx_trades_symbol      ON trades(symbol) WHERE status = 'open';

-- ai_critiques
CREATE TABLE ai_critiques (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trade_id   UUID NOT NULL REFERENCES trades(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content    TEXT NOT NULL,
    model      VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- subscriptions
CREATE TABLE subscriptions (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    stripe_customer_id     VARCHAR(255) UNIQUE,
    stripe_subscription_id VARCHAR(255),
    status                 VARCHAR(20) DEFAULT 'inactive',
    plan                   VARCHAR(50),
    period_end             TIMESTAMPTZ,
    updated_at             TIMESTAMPTZ DEFAULT NOW()
);
```

**Deliverable:** `curl localhost:8080/health` returns `{"status":"ok","db":"connected"}`.

---

## Stage 2 — Clerk Auth

**Goal:** Mobile app users authenticate via Clerk. The Go backend trusts Clerk JWTs and auto-syncs users to Postgres.

**Why Clerk over manual OAuth:**
- No custom JWT generation/validation code to maintain
- No Google OAuth flow in Go
- Clerk issues short-lived JWTs; Go validates them with Clerk's JWKS endpoint
- Clerk handles Apple/Google/email sign-in on mobile with one SDK

**Tasks:**

*Backend:*
- [ ] `POST /webhooks/clerk` — verify `svix` signature, handle `user.created` / `user.updated` / `user.deleted`, upsert into `users` table
- [ ] `internal/middleware/auth.go` — fetch Clerk JWKS, validate Bearer token, attach `userID` to context
- [ ] `GET /api/v1/me` — protected route returning current user
- [ ] Go packages: `lestrrat-go/jwx/v2` (JWKS + JWT), `svix-webhooks/svix-go`

*Mobile (deferred to Stage 8, but configure now):*
- [ ] Add Clerk publishable key to `apps/mobile/.env`
- [ ] Wrap Expo app with `<ClerkProvider>`

**Env vars needed:**
```
CLERK_SECRET_KEY=sk_...
CLERK_WEBHOOK_SECRET=whsec_...
CLERK_JWKS_URL=https://your-clerk-domain/.well-known/jwks.json
```

**Deliverable:** A Clerk test user making a request to `/api/v1/me` with their JWT receives their profile. Webhook creates the DB row automatically.

---

## Stage 3 — Price Watcher

**Goal:** Live crypto prices streaming from CCXT into Go memory. Foundation for the matching engine.

**Architecture:**
```
CCXT WebSocket (Binance/Coinbase)
        │
        ▼
  Go Goroutine (per exchange)
        │
        ▼
  sync.Map[symbol]→Price   ← ultra-fast reads, no lock contention
        │
        ▼
  fanout channel → SSE clients (Stage 7)
                → matching engine (Stage 4)
```

**Tasks:**
- [ ] `internal/watcher/` package
- [ ] Connect to Binance WebSocket via CCXT Go bindings (or raw WS if CCXT Go is unstable — use `gorilla/websocket` as fallback)
- [ ] Populate `sync.Map[string]float64` keyed by `exchange:symbol`
- [ ] `GET /api/v1/prices/:symbol` — read from map, return JSON (no DB hit)
- [ ] Reconnect logic with exponential backoff
- [ ] Log price ticks at DEBUG level; suppress at INFO

**Deliverable:** `curl localhost:8080/api/v1/prices/BTC/USDT` returns a live price within 1 second.

---

## Stage 4 — Trade Matching Engine

**Goal:** Open trades automatically close when the live price hits the stop-loss or take-profit target. PnL calculated server-side. Manual close by the user is post-MVP.

**Architecture:**
```
Startup: load all open trades from DB into memory map
Price tick received → compare against open trades map
Hit detected → close trade in DB → fire Asynq job (→ Stage 6)
```

**Tasks:**
- [ ] `internal/engine/` package
- [ ] On startup: `SELECT * FROM trades WHERE status='open'` → populate `map[tradeID]Trade`
- [ ] Non-blocking Goroutine: for each price tick, iterate open trades for that symbol
- [ ] PnL calculation: `(exitPrice - entryPrice) / entryPrice * 100` (long); inverse for short
- [ ] On close: DB transaction updating trade, then enqueue Asynq job
- [ ] Mutex or channel-based trade map updates (add on create, remove on close)
- [ ] `internal/engine/pnl.go` — pure functions, fully unit testable

**Deliverable:** Create an open trade via API, watch it auto-close in the DB when the mocked price crosses entry.

---

## Stage 5 — Trade CRUD API

**Goal:** Full REST API for trade management. All routes protected by Clerk middleware.

**Endpoints:**
```
GET    /api/v1/trades              list (pagination + filters: status, symbol, side)
POST   /api/v1/trades              create new open trade (SL + TP required)
GET    /api/v1/trades/:id          get single trade
DELETE /api/v1/trades/:id          delete (own trades only)
# PUT /api/v1/trades/:id/close    -- post-MVP: manual close by user
GET    /api/v1/stats               win rate, avg PnL, total trades, best/worst trade
```

**Tasks:**
- [ ] `internal/trades/handler.go` — Gin route handlers
- [ ] `internal/trades/repository.go` — all DB queries (no raw SQL in handlers)
- [ ] Input validation: symbol format, quantity > 0, side in (long/short), SL and TP both present and logically valid (SL < entry for long, TP > entry for long; inverse for short)
- [ ] Ownership check middleware: user can only access their own trades
- [ ] Pagination: cursor-based (use `opened_at + id` as cursor)
- [ ] `GET /api/v1/stats` computed from DB aggregates

**Deliverable:** Full CRUD flow verified with a REST client (curl / Postman).

---

## Stage 6 — AI Analysis Worker

**Goal:** After a trade closes, an async background job generates a Claude-powered post-mortem and stores it.

**Architecture:**
```
Trade closes (Stage 4)
      │
      ▼
Asynq job enqueued (Redis)
      │
      ▼
Worker goroutine picks up job
      │
      ▼
Fetch trade + user history from DB
      │
      ▼
Call Claude API (claude-sonnet-4-6)
      │
      ▼
Store critique in ai_critiques table
      │
      ▼
Push notification to user (Stage 7)
```

**Tasks:**
- [ ] Go packages: `hibiken/asynq`, `anthropics/anthropic-sdk-go`
- [ ] `internal/worker/` package with `CritiqueTrade` task
- [ ] Prompt template: trade details + user's last 10 closed trades for context
- [ ] Rate limiting: max 1 Claude call per trade close (deduplicate by trade ID)
- [ ] Store critique with model name + timestamp
- [ ] `GET /api/v1/trades/:id/critique` — fetch stored critique
- [ ] Graceful worker shutdown on SIGTERM

**Env vars:**
```
ANTHROPIC_API_KEY=sk-ant-...
UPSTASH_REDIS_URL=rediss://...
```

**Deliverable:** Close a trade, wait ~5 seconds, fetch `/api/v1/trades/:id/critique` and receive an AI post-mortem.

---

## Stage 7 — SSE + Push Delivery

**Goal:** Active mobile app receives live price updates via SSE. Backgrounded app receives push notifications when a trade closes.

**Tasks:**

*SSE:*
- [ ] `GET /api/v1/stream` — authenticated SSE endpoint
- [ ] Price watcher (Stage 3) fans out to a `broadcast` channel
- [ ] Each SSE client goroutine reads from channel, writes `data: {symbol, price, ts}\n\n`
- [ ] Heartbeat every 30s to prevent proxy timeouts
- [ ] Clean up disconnected clients

*Push Notifications:*
- [ ] Store Expo push token per user in `users` table (`push_token` column)
- [ ] `POST /api/v1/push-token` — mobile registers its token on login
- [ ] After trade closes + critique ready: call Expo Push API
- [ ] Go package: `sideshow/apns2` (APNs) or Expo Push HTTP API (simpler, handles both platforms)

**Deliverable:** Open the mobile dev build, enter a price — watch the price update in real-time on screen. Close the app, close a trade server-side, receive a push notification.

---

## Stage 8 — Mobile App Shell

**Goal:** Expo app with Clerk auth, tab navigation, and API client connected to the Go backend.

**Tasks:**
- [ ] Expo SDK 52+ with Expo Router (file-based routing)
- [ ] `@clerk/clerk-expo` — wrap app in `<ClerkProvider>`, sign-in screen with Google + Apple
- [ ] Tab navigation: Dashboard / New Trade / History / Analysis / Settings
- [ ] `lib/api.ts` — typed axios client; Clerk `getToken()` injected as Bearer
- [ ] Auth guard: redirect unauthenticated users to sign-in
- [ ] NativeWind for styling (Tailwind CSS syntax in React Native)
- [ ] Register push token with backend on first login
- [ ] Handle `401` responses: trigger Clerk sign-out

**Mobile packages:**
```json
{
  "@clerk/clerk-expo": "latest",
  "expo-router": "~4.0.0",
  "nativewind": "^4.0.0",
  "tailwindcss": "^3.4.0",
  "axios": "^1.7.0",
  "expo-notifications": "~0.29.0"
}
```

**Deliverable:** Sign in with Google on device/simulator → see authenticated user name on screen.

---

## Stage 9 — Mobile Screens

**Goal:** All core screens built and wired to the Go API.

**Screens:**

| Screen | Key Features |
|---|---|
| **Dashboard** | Active trades list, portfolio PnL, win-rate chip, "New Trade" FAB |
| **NewTradeScreen** | Exchange picker, symbol input, entry price, quantity, Long/Short toggle, stop-loss, take-profit, notes |
| **TradeDetailScreen** | Live price via SSE, entry vs current, PnL %, AI critique tab (no manual close — post-MVP) |
| **HistoryScreen** | Closed trades, filter by date range / symbol / P&L sign, pull-to-refresh |
| **AnalysisScreen** | Per-trade critiques list, aggregate patterns, "Analyze all" button |
| **SettingsScreen** | Subscription status, upgrade CTA, sign out |

**Tasks:**
- [ ] Shared `<TradeCard />` component used in Dashboard and History
- [ ] SSE hook `usePriceStream(symbol)` for live price on TradeDetailScreen
- [ ] Optimistic UI on trade creation
- [ ] Empty states and skeleton loaders on all lists
- [ ] Error boundary + toast notifications for API errors

**Deliverable:** Full end-to-end flow: sign in → create trade → watch live price → close trade → view AI critique.

---

## Stage 10 — Stripe Subscriptions

**Goal:** Free tier (5 open trades max) and Pro tier (unlimited trades + AI analysis).

**Tasks:**

*Backend:*
- [ ] `POST /api/v1/payments/checkout` — create Stripe Checkout session, return URL
- [ ] `POST /webhooks/stripe` — verify signature, handle `customer.subscription.*` events
- [ ] Subscription gate middleware: check `subscriptions.status = 'active'` for Pro features
- [ ] `GET /api/v1/subscription` — return current plan + period end

*Mobile:*
- [ ] `SettingsScreen` shows current plan
- [ ] `WebBrowser.openAuthSessionAsync(checkoutUrl)` to launch Stripe Checkout
- [ ] On return: poll subscription endpoint, refresh UI

**Env vars:**
```
STRIPE_SECRET_KEY=sk_...
STRIPE_WEBHOOK_SECRET=whsec_...
STRIPE_PRO_PRICE_ID=price_...
```

**Deliverable:** Free user hits 5-trade limit, taps upgrade, completes Stripe checkout, returns to app with Pro status.

---

## Stage 11 — CI/CD + Deploy

**Goal:** Push to `main` → backend deploys to Fly.io → mobile build triggered on EAS.

**Tasks:**

*Backend — `.github/workflows/deploy-server.yml`:*
- [ ] Trigger on push to `main` with changes in `apps/server/**`
- [ ] Steps: checkout → Go test → Docker build → `flyctl deploy`
- [ ] Run DB migrations as part of deploy (`flyctl ssh console -C "migrate up"`)
- [ ] Secrets: `FLY_API_TOKEN`, `DATABASE_URL`, `CLERK_SECRET_KEY`, `ANTHROPIC_API_KEY`, etc.

*Mobile — `.github/workflows/deploy-mobile.yml`:*
- [ ] Trigger on push to `main` with changes in `apps/mobile/**`
- [ ] Steps: checkout → pnpm install → `eas build --platform all --non-interactive`
- [ ] On tag `v*`: `eas submit` to TestFlight + Play Console
- [ ] Secrets: `EXPO_TOKEN`, `CLERK_PUBLISHABLE_KEY`

*Fly.io setup (one-time):*
- [ ] `fly launch` inside `apps/server`
- [ ] `fly postgres create` and attach
- [ ] `fly secrets set` for all env vars
- [ ] Set `fly scale count 2` for zero-downtime deploys

**Deliverable:** Merge PR → both deploys succeed → app reachable at `https://your-app.fly.dev`.

---

## Stage 12 — Polish + Testing

**Goal:** Production-ready. Addresses all CRITIQUE.md concerns.

**Backend Tests:**
- [ ] Unit: PnL calculations (`internal/engine/pnl_test.go`)
- [ ] Unit: trade ownership middleware
- [ ] Integration: API endpoints with real test DB (use Docker in CI)
- [ ] Integration: Clerk webhook handler
- [ ] Test: Asynq worker with mock Claude client

**Mobile Tests:**
- [ ] Component: `TradeCard` renders PnL correctly for long/short
- [ ] Component: form validation on NewTradeScreen

**Hardening (from CRITIQUE.md):**
- [ ] Rate limiting: `golang.org/x/time/rate` + custom Gin middleware — 100 req/min per user
- [ ] Rate limiting: Claude API calls — 1 per trade (idempotency key by trade ID)
- [ ] Rate limiting: CCXT — single shared connection per exchange (multiplexing)
- [ ] Claude API fallback: if call fails, store `status='pending'` and retry via Asynq
- [ ] Sentry error tracking on both backend and mobile
- [ ] Structured JSON logging with `zerolog`
- [ ] `GET /health` extended: DB ping + Redis ping + CCXT connection status

**Deliverable:** `go test ./...` passes. CI green. No P0 crashes in manual testing.

---

## Engineering Guardrails

Full rationale for each principle is in **RATIONALE.md** under "Engineering Principles".

### Clean Architecture
- Dependencies flow inward only: Handler → Service → Repository → DB. Never reverse.
- Handlers never import repository structs directly — only interfaces.
- `internal/engine/` and `internal/worker/` have zero knowledge of Gin or HTTP.
- Composition root is `cmd/api/main.go` — this is the only place concrete types are wired together.

### SOLID
- **Single Responsibility:** One file per concern — `handler.go`, `repository.go`, `service.go` per domain.
- **Open/Closed:** AI provider is behind `internal/ai/` interface. New model = new file, no edits to handlers.
- **Dependency Inversion:** Handlers depend on interfaces. Concrete implementations injected at startup.

### 12-Factor App
- **Config:** All config via env vars. Crash-fail at startup if required vars are missing. No silent defaults.
- **Logs:** Structured JSON to stdout via `zerolog`. No log files written to disk.
- **Disposability:** Graceful shutdown on SIGTERM — drain requests, flush Asynq, close DB pool.
- **Dev/prod parity:** Docker Compose uses the same Postgres + Redis versions as production.
- **Admin processes:** Migrations run as a one-off CI step before the new server starts. Never inside the running app.
- **Processes:** Server is stateless per request. In-memory price cache (`sync.Map`) is acceptable at single-instance scale.

### Additional Rules
- **Never commit secrets.** All keys via environment variables. `.env` in `.gitignore`.
- **No raw SQL in handlers.** All queries live in `repository.go` files.
- **Ownership checks on every trade route.** Enforced in middleware, not per-handler.
- **Migrations are forward-only.** No destructive `DROP` without an explicit rollback file.
- **PR required before merging to `main`.** CI must pass (tests + Docker build).

---

## How to Use This Plan with Claude Code

Each stage maps to one focused Claude Code session. When starting a session:

1. Tell Claude: **"We are on Stage N — [Stage Name]"**
2. Provide the `.env.example` values relevant to that stage
3. Claude reads this file + relevant existing code, then builds only what's in scope
4. At end of session, verify the **Deliverable** before closing

Do not skip stages — each stage's deliverable is the foundation for the next.

---

## MVP Definition (Ship Without)

The following are **post-MVP** (do not block initial release):
- Stripe / subscriptions (Stage 10) — ship with no paywall first
- Push notifications (Stage 7, push half) — SSE-only is fine for v1
- Multiple exchanges — start with Binance only
- Apple Sign-In — Google only for v1
- Export/import trades
- Social/leaderboard features

---

## Future Phases (Post-MVP, in order)

Build these incrementally after the core MVP ships. Each phase is independent and builds on the previous.

---

### Phase A — Modify Open Trade (SL/TP adjustment)

**What:** User can update the stop-loss or take-profit on an open trade after it has been placed.

**Why:** Lets users trail their stop or move their target as the trade develops — a core real-trading behaviour.

**Backend:**
- `PATCH /api/v1/trades/:id` — update `stop_loss` and/or `take_profit`; re-validate logic (SL < entry for long, etc.)
- Matching engine reloads the updated values from DB immediately (or via an in-memory update message on the trade map)

**Mobile:**
- Edit fields on TradeDetailScreen; save sends the PATCH request
- Optimistic UI update

---

### Phase B — Manual Trade Close (user-initiated)

**What:** User can close an open paper trade at any time at the current live price, bypassing SL/TP.

**Why:** Simulates real trading where a trader exits a position early based on their own judgement.

**Architecture:**
```
Client ──WS──→ Binance          (client-maintained candlestick chart — no server load)

User taps "Close Trade"
      │
      ▼
POST /api/v1/trades/:id/close ──→ Go server
      │  same code path as auto-close
      ▼
Engine closes trade at current price → PnL calculated → Asynq job → AI post-mortem
```

**Key point:** The client opens its own WebSocket directly to Binance for the candlestick chart. This connection is between the user's device and Binance — it does not pass through the Go server and imposes no server load regardless of how many users have charts open. The server's own CCXT connection (for auto-close monitoring) is completely separate.

**Backend:**
- `PUT /api/v1/trades/:id/close` — closes at current live price; adds `close_reason` field: `'sl' | 'tp' | 'manual'`
- DB migration: add `close_reason VARCHAR(10)` to `trades` table

**Mobile:**
- `useCandleStream(symbol)` hook — opens WebSocket directly to Binance public market data stream
- Candlestick chart on TradeDetailScreen (library TBD: `react-native-wagmi-charts` or TradingView `lightweight-charts` in a WebView)
- "Close Trade" button sends `PUT` request; same result as an auto-close from the user's perspective
