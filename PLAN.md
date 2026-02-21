# Crypto Paper Trader — Plan

For the full staged roadmap see **BUILD.md**. This file tracks the current tech stack and immediate next priorities.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Go + Gin |
| Mobile | React Native (Expo) |
| Database | PostgreSQL |
| Auth | Clerk (Google Sign-In, Clerk JWKS + svix webhooks) |
| Queue | Asynq + Redis (Upstash) |
| Market Data | CCXT |
| Real-time | SSE (server → mobile) |
| AI Analysis | Claude API |
| Payments | Stripe |
| Hosting | Fly.io (backend + DB), EAS (mobile) |
| CI/CD | GitHub Actions |

---

## Repo Layout

This repo is the Go backend only. Mobile is a separate repo.

```
cryptopapertrader-api/
├── cmd/api/main.go
├── internal/
│   ├── auth/
│   ├── trades/
│   ├── payments/
│   ├── analysis/
│   └── database/
├── migrations/
├── Dockerfile
├── docker-compose.yml
├── go.mod
└── .env.example
```

---

## Immediate Priorities

These three things must be in place before any feature work begins.

---

### 1. Docker Setup (local dev)

**Goal:** `docker-compose up` starts Postgres and Redis locally. Backend runs against them.

**Tasks:**
- [ ] `docker-compose.yml` — Postgres 15 + Redis services
- [ ] `apps/server/Dockerfile` — multi-stage Go build
- [ ] `.env.example` — all required keys listed (no values)
- [ ] `apps/server` reads `DATABASE_URL` and `REDIS_URL` from env; crash-fails if missing

**Deliverable:** `docker-compose up -d` → `curl localhost:8080/health` returns `{"status":"ok","db":"connected"}`.

**Env vars:**
```
DATABASE_URL=postgresql://crypto_trader:dev_password@localhost:5432/crypto_trader_dev
REDIS_URL=redis://localhost:6379
```

---

### 2. Clerk Authentication

**Goal:** Mobile users sign in via Clerk (Google). Go backend validates Clerk JWTs and syncs users to Postgres via webhooks.

**How it works:**
- Mobile app uses `@clerk/clerk-expo` — Clerk handles the Google OAuth flow
- After sign-in, Clerk issues a short-lived JWT; the mobile app sends it as `Authorization: Bearer <token>`
- Go middleware fetches Clerk's public JWKS endpoint and validates the token — no custom JWT code
- When a user signs up/updates/deletes, Clerk sends a webhook to `POST /webhooks/clerk`; your server verifies the svix signature and upserts into the `users` table

**Backend tasks:**
- [ ] `users` table migration (`clerk_id`, `email`, `name`, `avatar_url`)
- [ ] `internal/middleware/auth.go` — JWKS fetch + JWT validation (`lestrrat-go/jwx/v2`)
- [ ] `POST /webhooks/clerk` — svix signature check, handle `user.created` / `user.updated` / `user.deleted`
- [ ] `GET /api/v1/me` — protected route, returns current user from DB

**Mobile tasks:**
- [ ] Wrap app in `<ClerkProvider publishableKey={...}>`
- [ ] Sign-in screen with Google button (`useOAuth`)
- [ ] Inject Clerk token into axios requests via `getToken()`
- [ ] Register push token with backend on first login

**Go packages:**
```
github.com/gin-gonic/gin
github.com/lestrrat-go/jwx/v2
github.com/svix/svix-webhooks/go
github.com/jackc/pgx/v5
github.com/joho/godotenv
```

**Mobile packages:**
```
@clerk/clerk-expo
expo-router
```

**Env vars:**
```
CLERK_SECRET_KEY=sk_...
CLERK_WEBHOOK_SECRET=whsec_...
CLERK_JWKS_URL=https://<your-clerk-domain>/.well-known/jwks.json
CLERK_PUBLISHABLE_KEY=pk_...
```

**Deliverable:** Sign in with Google on simulator → JWT sent to `/api/v1/me` → returns user profile. Clerk webhook auto-creates the DB row.

---

### 3. Basic CI/CD (GitHub Actions)

**Goal:** Push to `main` triggers backend tests + Docker build. Foundation for later Fly.io deploy.

**Backend — `.github/workflows/deploy-server.yml`:**
- [ ] Trigger: push to `main`
- [ ] Steps: checkout → `go test ./...` → Docker build (no push yet)
- [ ] Add Fly.io deploy step once hosting is provisioned

**GitHub Secrets needed:**
```
CLERK_SECRET_KEY
CLERK_WEBHOOK_SECRET
ANTHROPIC_API_KEY      # add now, use in Stage 6
FLY_API_TOKEN          # add when Fly.io is provisioned
EXPO_TOKEN             # add when EAS is set up
```

**Deliverable:** Open a PR → CI runs `go test` and Docker build → green check before merge.

---

## After These Three

Continue with BUILD.md Stage 3 onwards:
- Stage 3: Price Watcher (CCXT WebSocket → sync.Map)
- Stage 4: Trade Matching Engine
- Stage 5: Trade CRUD API
- Stage 6: AI Analysis Worker (Claude + Asynq)
- Stage 7: SSE + Push Notifications
- Stage 8+: Mobile screens, Stripe, deploy
