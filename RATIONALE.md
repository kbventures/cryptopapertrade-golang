# Decision Rationale

Surgical record of *why* each significant technical decision was made.
Add entries here when a choice has real trade-offs worth remembering.

---

## Format

```
### [Decision Title]
**Chosen:** X
**Rejected:** Y, Z
**Why:**
- Reason 1
- Reason 2
**Revisit if:** condition that would change the decision
```

---

## Decisions

### Authentication — Clerk over manual OAuth + JWT

**Chosen:** Clerk
**Rejected:** Manual Google OAuth (Goth) + custom JWT generation
**Why:**
- Eliminates an entire category of security-sensitive code (token signing, refresh rotation, JWKS management) that is easy to get wrong
- Clerk's Expo SDK handles Google and Apple sign-in with one integration; doing both natively would require separate OAuth flows
- Clerk issues standard JWTs validated via a public JWKS endpoint — the Go backend just verifies, never mints
- User sync to Postgres via Clerk webhooks (svix) keeps auth state as the source of truth in Clerk, with a read replica in our DB
**Revisit if:** Clerk pricing becomes prohibitive at scale, or we need an auth flow Clerk doesn't support

---

### Backend Framework — Gin over Fiber (revised)

**Chosen:** Gin
**Rejected:** Fiber (fasthttp), Echo, stdlib net/http
**Why:**
- Fiber's fasthttp engine is not `net/http`-compatible; most Go middleware (OAuth, OTel, Prometheus, Clerk webhook validation) assumes standard types and will break or require an adaptor that eliminates Fiber's performance advantage
- The SSE scaling argument (thousands of concurrent connections) does not apply at MVP scale — Gin/net/http handles SSE fine until a real bottleneck is measured
- Gin is idiomatic, well-documented, and has a larger ecosystem; engineers expect it
- Clerk JWT verification, Prometheus metrics, and OpenTelemetry tracing are all plug-and-play with net/http-based frameworks

**If SSE volume ever justifies Fasthttp:** run a dedicated Fiber micro-service for the streaming endpoint only, keeping the core API on Gin. This isolates the optimisation instead of forcing the whole system onto a non-standard HTTP stack.

**Revisit if:** profiling shows Gin is a genuine bottleneck on the SSE fan-out path at real traffic levels

---

### Real-time Delivery — SSE over WebSockets (mobile)

**Chosen:** Server-Sent Events (SSE) for mobile clients
**Rejected:** Raw WebSockets on the mobile device
**Why:**
- SSE is unidirectional (server → client), which is all price updates require
- WebSockets keep a full-duplex connection alive, draining battery and radio on mobile
- SSE reconnects automatically; no client-side reconnect logic needed
- WebSockets remain the right choice *inside* the Go server (CCXT exchange connections) where battery is not a concern
**Revisit if:** we need client-initiated real-time messages (e.g., live order book interaction)

---

### Task Queue — Asynq over direct goroutines for AI calls

**Chosen:** Asynq (Redis-backed)
**Rejected:** Fire-and-forget goroutines
**Why:**

**Durability — the core reason**
A goroutine lives in memory. If the server crashes, restarts, or is redeployed mid-analysis, the job is silently gone. The user never gets their AI critique and nothing in the system knows it was lost. Asynq persists the job to Redis before the worker picks it up — a restart just means the job gets picked up after the server comes back.

**Retries**
Claude API calls fail. Rate limits, timeouts, transient errors. With a goroutine you either write your own retry logic (boilerplate, easy to get wrong) or the job is lost on the first failure. Asynq handles exponential backoff retry out of the box, configurable per task type.

**Deduplication**
If a trade close is somehow triggered twice (race condition, duplicate webhook), two goroutines would fire two Claude API calls and write two analyses. Asynq lets you key jobs by trade ID so the second enqueue is a no-op.

**Observability**
Goroutines are invisible — you have no idea how many are running, how many failed, or how long they're taking. Asynq ships with a web dashboard that shows queue depth, processing rate, failed jobs, and retry history. Critical when debugging why a user didn't receive their analysis.

**Backpressure**
If 100 trades close simultaneously, 100 goroutines fire Claude API calls at once. Asynq lets you set a concurrency limit on the worker so you control how many Claude calls run in parallel, avoiding rate limit hammering.

**Revisit if:** Redis adds unacceptable operational overhead for the scale we're at, or if we move to a managed job queue (e.g. Inngest, Temporal) that offers the same guarantees with less infra to maintain.

---

### Mobile Styling — NativeWind over Tamagui or StyleSheet

**Chosen:** NativeWind (Tailwind CSS syntax)
**Rejected:** Tamagui, React Native Paper, raw StyleSheet
**Why:**
- Tailwind class names are already known; no new component API to learn
- NativeWind v4 compiles to StyleSheet at build time — no runtime overhead
- Tamagui is powerful but adds significant complexity and a custom compiler
**Revisit if:** NativeWind v4 has stability issues with the Expo SDK version we're using

---

### Repository Structure — Monorepo over Polyrepo

**Chosen:** Single monorepo (`pnpm` workspaces + Go modules), repo named `cryptopapertrade-api`
**Rejected:** Separate repositories per app (`cryptopapertrade-api`, `cryptopapertrade-mobile`, etc.)
**Why:**

**Organisation and discoverability for a small team**
For a solo developer or small team, a single clone gives the full picture. You never wonder "which repo has the types?" or "where does the CI live?" — everything is in one place. This is the dominant reason at this scale, and it is sufficient on its own.

**Shared TypeScript contract without publishing**
`packages/types` holds the TypeScript interfaces that describe the API response shapes. In a monorepo both mobile and (future) desktop consume this via pnpm workspace linking — no npm publish step, no version pinning, no stale types. In a polyrepo this would require either publishing to npm on every API change or duplicating the types in each consumer.

**Note on code sharing:** Go and TypeScript do not share code — the Go module and pnpm workspaces are independent systems that coexist in the same folder without integrating. The benefit is organisational, not code-reuse. Types must be kept in sync manually or via an OpenAPI code-gen step, not automatically.

**Atomic commits across the stack**
An API shape change and its corresponding mobile/desktop client update ship in one PR, one review, one merge. This is a convenience benefit, not a safety guarantee — it still requires discipline to update both sides.

**Path-based CI preserves independent deployment**
`.github/workflows/` uses `paths:` filters so changes in `apps/server/**` trigger only the backend deploy and changes in `apps/mobile/**` trigger only the EAS build. Each app deploys independently despite living in the same repo.

**Desktop addition is trivial**
`apps/desktop/` is a placeholder from day one. Adding a Tauri or Electron app later requires no new repository, no new secrets, no new CI pipeline — just populate the directory.

**Revisit if:** The team grows to the point where backend and mobile are owned by separate teams who need independent PR workflows, access controls, or release cadences. At that point, extract into separate repos linked by a published OpenAPI contract.

---

### CI/CD — GitHub Actions + Fly.io + EAS

**Chosen:** GitHub Actions for pipeline orchestration, Fly.io for backend deploy, EAS Build for mobile
**Rejected:** CircleCI, Jenkins, self-hosted runners, Render, Railway, raw EC2

**Why GitHub Actions:**
- Already in GitHub — no third-party account, no webhook setup, secrets live in the same place as the code
- `paths:` filters mean backend and mobile pipelines are fully independent despite the monorepo; a CSS change in mobile never triggers a Go build
- Free tier is sufficient at this scale
- YAML workflows are committed alongside the code — the pipeline is versioned and reviewable in PRs

**Why Fly.io for the backend:**
- Native support for long-lived connections (SSE) — unlike serverless platforms (Vercel, Lambda) which time out HTTP connections
- `fly launch` provisions the app, Postgres, and Redis in minutes
- Zero-downtime deploys with `fly scale count 2` out of the box
- Persistent machines mean in-memory state (sync.Map price cache) survives between requests within the same instance

**Rejected alternatives:**
- **Render / Railway** — good DX but less control over machine count and SSE connection limits
- **AWS ECS / EC2** — more control, but significant overhead to configure at MVP scale
- **Serverless (Lambda, Vercel)** — incompatible with SSE and long-lived CCXT WebSocket connections

**Why EAS Build for mobile:**
- Managed cloud build service from Expo — no macOS runner needed for iOS builds
- `eas submit` handles App Store and Play Store submission from CI
- Integrates with Expo Updates for OTA (over-the-air) patches without a full App Store release

**Pipeline structure:**
- `deploy-server.yml` — triggers on `apps/server/**` changes: `go test` → Docker build → `flyctl deploy` → run migrations
- `deploy-mobile.yml` — triggers on `apps/mobile/**` changes: `pnpm install` → `eas build` → `eas submit` on version tags

**Revisit if:** Traffic requires multi-region deploy or a managed Kubernetes cluster becomes cost-effective.

---

### Folder Structure — `apps/` + `packages/` + `internal/`

**Chosen:** `apps/{server,mobile,desktop}` at the top level; Go code under `apps/server/internal/`; shared TS types in `packages/types/`
**Rejected:** Flat structure, `src/` root, domain-first top-level (`auth/`, `trades/`)

**Why `apps/` at the root:**
- Makes it immediately obvious this is a multi-app monorepo — no guessing whether `server/` is a subdirectory of something else
- Each app is independently runnable and deployable; the folder boundary reinforces that

**Why Go `internal/` with package-per-domain:**
```
apps/server/internal/
├── auth/        # Clerk middleware, webhook handler
├── trades/      # handlers + repository (no raw SQL in handlers)
├── engine/      # price matching, PnL calculation
├── worker/      # Asynq tasks
├── database/    # connection pool, migrations runner
└── models/      # shared Go structs
```
- `internal/` is a Go language feature — packages inside it cannot be imported by code outside `apps/server/`. Enforces encapsulation at the compiler level.
- One package per domain keeps each concern testable in isolation; `engine/pnl.go` is pure functions with no DB dependency
- `repository.go` per domain keeps all SQL in one place — handlers never write raw queries

**Rejected alternatives:**
- **Flat `server/` with all files at top level** — becomes unnavigable past ~10 files
- **Domain folders at repo root** (`/auth`, `/trades`) — ambiguous whether these are frontend, backend, or shared
- **MVC layout** (`controllers/`, `models/`, `views/`) — doesn't map cleanly to Go idioms; creates cross-cutting dependencies

**Revisit if:** A domain grows large enough to warrant its own microservice — at that point extract the `internal/<domain>` package into a separate repo.

---

### Engineering Principles — Clean Architecture, SOLID, 12-Factor App

These are not single decisions but constraints that shape every implementation choice. Recorded here so future contributors understand the "why" behind the patterns they'll see in the code.

---

**Clean Architecture**

Dependencies only point inward: handlers → domain logic → repository → DB. Never the reverse.

```
HTTP Handler (Gin)
      │  calls
      ▼
  Service / Use Case  (pure business logic, no framework imports)
      │  calls
      ▼
  Repository interface  (defined in the domain package)
      │  implemented by
      ▼
  Postgres / Redis / Claude API
```

- Handlers know about services; services do not know about Gin
- Repositories are interfaces — swappable for fakes in tests without a real DB
- The matching engine (`internal/engine/`) has zero knowledge of HTTP or Postgres; it is pure Go functions

**Practical rule:** If you need to import `gin` inside `internal/engine/` or `internal/trades/repository.go`, the boundary is wrong.

---

**SOLID**

| Principle | How it applies here |
|---|---|
| **Single Responsibility** | `repository.go` only does DB queries. `handler.go` only translates HTTP ↔ service calls. `pnl.go` only calculates PnL. |
| **Open/Closed** | The AI service is behind an interface (`internal/ai/`). Swapping Claude for another model requires a new implementation file, not editing existing handlers. |
| **Liskov Substitution** | Any `TradeRepository` implementation (real Postgres, in-memory fake) is substitutable in tests. |
| **Interface Segregation** | Repositories expose only the methods their consumers need — the webhook handler gets a `UserUpsert` interface, not a full `UserRepository`. |
| **Dependency Inversion** | Handlers depend on interfaces, not concrete structs. Concrete implementations are wired together in `cmd/api/main.go` (composition root). |

---

**12-Factor App**

| Factor | Implementation |
|---|---|
| **I. Codebase** | One repo, one app per `apps/` directory, tracked in Git |
| **II. Dependencies** | Go: `go.mod`. Node: `pnpm-workspace.yaml`. No system-level deps assumed. |
| **III. Config** | All config via environment variables. `.env` for local dev (never committed). Crash-fail at startup if required vars are missing. |
| **IV. Backing services** | Postgres, Redis, Clerk, Stripe, Claude API all treated as attached resources — swappable via env var URL change |
| **V. Build / Release / Run** | GitHub Actions separates build (Docker image) from release (tag) from run (Fly.io machine). No SSH deploys. |
| **VI. Processes** | Go server is stateless per request. Shared state (price cache) lives in `sync.Map` in the process — acceptable at single-instance scale; moves to Redis if multi-instance needed |
| **VII. Port binding** | Go server binds to `PORT` env var. No app server (Nginx) in front during development. |
| **VIII. Concurrency** | Scale out by increasing Fly.io machine count. Asynq workers scale independently of the HTTP server. |
| **IX. Disposability** | Fast startup (Go binary ~50ms). Graceful shutdown on SIGTERM: drain active requests, flush Asynq, close DB pool. |
| **X. Dev/prod parity** | Docker Compose mirrors production services (same Postgres version, Redis). No "it works on my machine" differences. |
| **XI. Logs** | Structured JSON logs via `zerolog` to stdout. No log files. Fly.io aggregates them. |
| **XII. Admin processes** | DB migrations run as a one-off process in CI (`migrate up`) before the new server version starts. Never run migrations inside the running app. |

---

### Security — OWASP Top 10 Mitigations

These are not optional — each one maps to a concrete implementation rule.

| Threat | Mitigation in this project |
|---|---|
| **Injection (SQL, NoSQL)** | All queries use parameterised statements via `pgx/v5`. No string-concatenated SQL anywhere. Raw SQL lives only in `repository.go` files. |
| **Broken Authentication** | Auth delegated to Clerk. No custom password storage, no custom token signing. JWTs validated against Clerk's JWKS endpoint — short-lived, rotated automatically. |
| **Sensitive Data Exposure** | All traffic over HTTPS (enforced by Fly.io + Clerk). No secrets in logs. `zerolog` redacts token fields. `.env` never committed. |
| **Broken Access Control** | Ownership middleware on every trade route — a user cannot read, close, or delete another user's trade. Checked in middleware, not per-handler, so it cannot be accidentally omitted. |
| **Security Misconfiguration** | Crash-fail at startup if required env vars are missing — no silent fallback to insecure defaults. CORS restricted to known origins. |
| **Vulnerable Dependencies** | `go mod` and `pnpm` lock files committed. Dependabot alerts enabled on the repo. No unpinned `latest` tags in Docker base images. |
| **Insufficient Logging** | Structured JSON logs via `zerolog` on every request (method, path, status, latency). Auth failures logged with user ID (never token). Sentry for error tracking in production. |
| **Rate Limiting** | `golang.org/x/time/rate` middleware — 100 req/min per authenticated user. Separate stricter limit on `/webhooks/*` endpoints. Claude API calls deduplicated by trade ID via Asynq. |
| **Server-Side Request Forgery** | No user-controlled URLs are fetched server-side. CCXT targets are hardcoded exchange endpoints, not user input. |
| **Insecure Deserialization** | All request bodies decoded via `gin.ShouldBindJSON` with strict struct validation. Unknown fields rejected. No `interface{}` deserialization of user input. |

---

### Desktop App Framework — Decision Deferred

**Chosen:** Placeholder `apps/desktop/` directory in Stage 0; framework decided when desktop scope is defined
**Candidates:** Tauri (Rust + WebView), Electron (Node.js + Chromium), Flutter Desktop
**Why deferred:**
- Mobile is the primary v1 client; desktop is a future enhancement
- The right choice depends on how much UI code should be shared with mobile:
  - **Tauri** is the current default candidate: Rust core + WebView means the UI is React/HTML, NativeWind Tailwind classes are reusable, bundle is ~5–10 MB vs Electron's ~150 MB, strong security model via explicit capability grants
  - **Electron** is the safe fallback: mature ecosystem, most hiring familiarity, heavier but battle-tested
  - **Flutter Desktop** only fits if the mobile app is rebuilt in Flutter — not the current plan
- The monorepo structure accommodates any choice: `apps/desktop/` is an independent workspace package regardless of framework

**Default when desktop scope is defined:** Tauri + shared React components from `packages/types`.

**Revisit when:** Mobile v1 ships and desktop feature scope is defined.

---
