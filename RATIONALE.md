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

### Session Caching — No Cache at MVP; JWT Custom Claim as the Long-Term Answer

**Chosen:** Hit Postgres directly for user resolution at MVP. Embed internal `user_id` as a Clerk JWT custom claim to eliminate the DB lookup permanently.
**Rejected:** Redis session cache, in-memory sync.Map cache, Redis token blacklist.

**Background — three separate problems bundled under "session cache":**

---

**Problem 1: JWKS Key Caching**

Not a concern. `lestrrat-go/jwx/v2` fetches Clerk's public keys and caches them in-memory automatically. No Clerk network call on every request. Nothing to build.

---

**Problem 2: User Record Resolution**

Every authenticated request must resolve `clerk_id` (from the JWT) to our internal `user_id` UUID (used for ownership checks on every trade route). That resolution must come from somewhere.

*Option A — Postgres on every request:*
- The `users` table has a UNIQUE index on `clerk_id` — this is an O(log n) indexed lookup, ~1–3ms on a local connection, ~2–5ms on Fly.io's internal network.
- Zero complexity. Always consistent. Single source of truth.
- Correct for MVP.

*Option B — In-memory cache (sync.Map):*
- Sub-microsecond reads after warmup. No extra network hop.
- Fatal flaw: single-instance only. Fly.io runs `count 2` for zero-downtime deploys. A `user.deleted` webhook invalidates the cache on one instance; the other keeps serving the deleted user until TTL expires.
- Worth adding only if Postgres user lookups appear in profiling. Not at MVP.

*Option C — Redis cache:*
- Shared across all instances. Consistent invalidation via webhook. TTL provides natural expiry even if the webhook handler fails.
- Adds a Redis round-trip (~0.5–2ms on Upstash) to every auth check — swapping one network call for another. Redis is no physically closer to the Go server than Postgres. The gain only materialises under heavy Postgres load from other queries.
- Must fall through to Postgres on Redis miss or Redis failure — adds a second failure mode with no reliability gain at MVP scale.
- Correct when running 3+ instances and auth latency is measurable. Wrong for MVP.

*Option D — JWT custom claim (chosen long-term approach):*
- Configure Clerk's JWT template to embed the internal UUID as a custom claim (e.g. `internal_id`).
- Set the claim in the `user.created` webhook: after upserting the user row, call Clerk's backend API to write `publicMetadata.internal_id = <uuid>`. Clerk then includes it in every token it issues.
- The auth middleware reads the UUID directly from the verified token. No DB. No Redis. No invalidation logic. Zero runtime dependencies beyond the JWKS crypto verification already happening.
- Maximum stale window = token lifetime (60 minutes). Acceptable for a paper trading app.
- This is architecturally the cleanest option and the right permanent answer. It removes an entire class of infrastructure before it needs to be built.

**Why this order matters:** Implementing the JWT custom claim in Stage 2 costs one extra Clerk API call in the webhook handler. Not implementing it means patching with a cache layer later — more code, more infra, more failure modes — to solve a problem that never needed to exist.

---

**Problem 3: Token Revocation / Blacklisting**

The traditional solution is a Redis blacklist: on logout, write `blacklisted:{jti}` with TTL = token expiry; middleware checks Redis on every request.

For this app:
- Clerk tokens expire in 60 minutes by default. Maximum exposure on a stolen token is 60 minutes.
- The app is paper trading — no real funds, no irreversible real-world actions within 60 minutes.
- Clerk's dashboard supports manual session revocation for emergencies.
- A Redis blacklist adds ~0.5–2ms latency and makes Redis a hard dependency for all auth.

Not needed for this app. If scope changes to handle real funds or sensitive PII, revisit.

---

**Decision summary:**

| Problem | Decision | Trigger to revisit |
|---|---|---|
| JWKS caching | Done — library handles it | Never |
| User record resolution | Postgres at MVP; JWT custom claim in Stage 2 to eliminate it | — |
| Multi-instance cache | Skip — Redis when warranted | `fly scale count 3+` and auth latency measured |
| Token revocation | Skip | App handles real funds or sensitive PII |

**Revisit if:** App scope expands beyond paper trading into real financial transactions, or token lifetime needs to be shorter than 60 minutes for security reasons.

---

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
**Rejected:** Fiber (fasthttp), Echo, Chi, Gorilla Mux, stdlib `net/http`

---

**Candidate breakdown**

**stdlib `net/http`**

| Pros | Cons |
|---|---|
| Zero external dependencies | No path-parameter routing out of the box — `ServeMux` matches prefixes, not `{id}` patterns (pre-Go 1.22 this was painful; 1.22 added basic pattern matching but still no named params) |
| Ships with every Go installation, never abandoned | No middleware chain — you assemble `http.Handler` wrappers by hand |
| Everything the ecosystem builds on — 100% interoperable | No request body binding or validation; `json.Decode` + manual error handling per handler |
| Ideal for tiny internal tools or single-endpoint proxies | Verbose: route registration, group prefixes, and common headers are boilerplate |

*Verdict:* Correct for a two-endpoint proxy or internal tool. Insufficient as the routing/middleware backbone of a multi-domain API with auth, SSE, webhooks, and rate limiting.

---

**Chi**

| Pros | Cons |
|---|---|
| Wraps stdlib `http.Handler` directly — any `net/http` middleware works with zero adapters | No built-in request binding or validation; you call `json.Decode` yourself |
| Extremely lightweight (~1 000 LOC) — what you see is what you get | More boilerplate per route compared to Gin for JSON responses |
| Idiomatic Go: no custom context type, no magic | Smaller community and middleware ecosystem than Gin |
| Composable sub-routers that feel natural | Less documentation; fewer StackOverflow answers |

*Verdict:* A legitimate choice if you want the thinnest possible layer over stdlib and are comfortable writing your own JSON helpers. Chi is what Gin is built on conceptually but with fewer batteries. For a project that already needs Clerk webhook validation, SSE helpers, and Prometheus middleware, Gin's included utilities save real time.

---

**Echo**

| Pros | Cons |
|---|---|
| Performance comparable to Gin (radix-tree router, same order of magnitude) | Smaller community than Gin — fewer third-party middleware packages |
| `net/http`-compatible; standard middleware works | Custom `echo.Context` wrapper creates same interop friction as `gin.Context` |
| Cleaner API in some opinions (built-in Binder interface is more extensible) | OpenAPI/Swagger tooling (echo-swagger) lags Gin Swagger in ecosystem maturity |
| Built-in HTTP/2 support | Less production battle-testing than Gin at scale |

*Verdict:* Echo is a credible alternative and a reasonable swap if a future contributor strongly prefers it. It does not solve any problem that Gin creates for this project. Switching would provide no measurable benefit while requiring migration of all handler signatures.

---

**Gorilla Mux**

| Pros | Cons |
|---|---|
| Flexible and expressive routing (regex patterns, host matching, query params) | Was archived in 2022 then un-archived — signals uncertain long-term maintenance |
| `net/http`-compatible | Significantly slower than Gin, Chi, or Echo (no radix tree) |
| Mature, widely documented | No middleware chain built in — `gorilla/handlers` is a separate package |
| | Community has largely migrated to Chi or Gin |

*Verdict:* Ruled out on maintenance uncertainty alone. No performance or feature advantage over Gin or Chi.

---

**Fiber (fasthttp)**

| Pros | Cons |
|---|---|
| Highest raw throughput of any Go web framework — fasthttp avoids allocations that `net/http` makes on every request | **Not `net/http`-compatible.** This is the disqualifying issue: Clerk webhook validation, OTel tracing, Prometheus middleware, svix signature verification, and most Go middleware assume `http.Request`/`http.ResponseWriter`. Fiber requires a custom adaptor that eliminates its performance advantage and adds an untested translation layer. |
| Express-like API — approachable for developers coming from Node.js | `fiber.Ctx` is not `*http.Request`. Every third-party library that touches the context needs evaluation or a fork. |
| Zero-allocation routing | The performance gap only matters at tens of thousands of req/s — the SSE fan-out on this project is measured in hundreds of concurrent clients, not tens of thousands |
| | Smaller community than Gin for Go-native developers |

*Verdict:* Correct choice for a dedicated, isolated high-throughput service (e.g. a single SSE streaming endpoint with no middleware dependencies). Wrong choice for an API that integrates with Clerk, Prometheus, OTel, and svix — you would spend more time writing adaptors than the allocation savings are worth.

**If SSE volume ever justifies fasthttp:** run a dedicated Fiber micro-service for the streaming endpoint only, keeping the core API on Gin. This isolates the optimisation without forcing the whole system onto a non-standard HTTP stack.

---

**Why Gin wins for this project**

1. **Radix-tree router** — same asymptotic performance as Chi, Echo, and Fiber for the route count this project has; no meaningful difference in practice
2. **`net/http`-compatible** — Clerk JWKS validation, svix webhook signature checking, OTel tracing, and Prometheus all plug in without adaptors
3. **Batteries included** — `ShouldBindJSON`, `Param`, `Query`, middleware groups, and abort-with-status are 80% of what a JSON API handler needs; no boilerplate wrappers to write
4. **Ecosystem and documentation** — largest community of the three real candidates (Gin, Chi, Echo); more middleware packages, more answered questions, more production case studies
5. **`gin.Context` trade-off is acceptable** — the custom context is the one friction point (stdlib middleware must be wrapped with `WrapH` or `WrapF`), but every dependency this project uses either ships a native Gin middleware or has `net/http` compatibility that wraps cleanly
6. **Team familiarity** — Gin is the first result engineers reach for in Go web development; no onboarding cost

**Revisit if:** profiling shows Gin is a genuine bottleneck on the SSE fan-out path at real traffic levels, or a dependency is added that is incompatible with `gin.Context` and cannot be wrapped cleanly.

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

### SSE Implementation — Gin `c.Stream()` over `r3labs/sse/v2`

**Chosen:** Gin's built-in `c.Stream()` + `c.SSEvent()` with a per-client buffered channel
**Rejected:** `r3labs/sse/v2`, raw `net/http` with `http.Flusher`
**Why:**
- Gin already provides `c.Stream()` and `c.SSEvent()` — zero additional dependencies
- The fan-out hub (price watcher → connected clients) must be written regardless of library; `r3labs/sse/v2` does not eliminate that work, it wraps it in an opaque layer
- `r3labs/sse/v2` is better suited to a generic event bus pattern; here the data flow is fixed (CCXT engine → channel → SSE client), so its extra features (named streams, `Last-Event-ID` replay) add complexity without benefit at MVP scale
- Raw `http.Flusher` is what Gin's `c.Stream()` wraps internally — no reason to drop down further

**Pattern:**
```go
// Each connecting client receives a buffered channel.
// The price watcher hub registers/deregisters channels.
func (h *Handler) StreamPrices(c *gin.Context) {
    ch := make(chan PriceUpdate, 8)
    h.hub.Register(symbol, ch)
    defer h.hub.Deregister(ch)

    c.Stream(func(w io.Writer) bool {
        update, ok := <-ch
        if !ok { return false }
        c.SSEvent("price", update)
        return true
    })
}
```

**No extra Go package required.** `c.Stream` and `c.SSEvent` ship with `gin-gonic/gin`.

---

**Why SSE fan-out is cheap even at thousands of concurrent users**

The data flow is: one upstream CCXT WebSocket per symbol → one in-process hub → N client SSE connections.

The key insight is that the hub does **no per-user computation**. Every connected client watching BTC/USDT receives the exact same bytes — the serialised `PriceUpdate` struct is marshalled once and the result is written to N channels. The goroutine-per-client model means each client's write is independent I/O; a slow or disconnected client blocks only its own goroutine (buffered channel drop), not the hub.

This is almost entirely **network I/O**, not CPU:

| Work | Per symbol | Per connected client |
|---|---|---|
| Parse CCXT WebSocket message | Once | — |
| Marshal `PriceUpdate` to JSON | Once | — |
| Copy marshalled bytes to channel | — | One channel write |
| Flush bytes over TCP | — | One `io.Writer.Write` |

A single Fly.io `shared-cpu-1x` machine (256 MB RAM) can sustain thousands of concurrent SSE connections on this pattern without breaking a sweat. The binding constraint at scale is **open file descriptors** (one per client TCP connection) and **RAM** (~a few KB of goroutine stack + channel buffer per client), not CPU or bandwidth — the payload is tiny (a price tick is < 100 bytes).

Practical ceiling before needing to think about it: roughly 10 000 concurrent clients per 256 MB instance. At that point the right move is `fly scale count 2`, not a rewrite.

**Revisit if:** SSE fan-out becomes a measured bottleneck — at that point extract a dedicated Fiber micro-service for the streaming endpoint only (as noted in the Gin vs Fiber decision above).

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


---

### Repository Structure — Monorepo over Polyrepo

**Chosen:** Single repo, simple folder structure, each app with its own native tooling, root Makefile
**Rejected:** Separate repositories per app

**Why monorepo for a solo developer:**

**Friction compounds on a solo developer**
Polyrepo requires constantly switching repos, opening separate PRs for changes that span both sides (an API shape change always has a matching mobile client change), and keeping contracts in sync manually with no tooling to catch drift. At team scale this is manageable with dedicated ownership. For a solo developer it is pure overhead with no payoff.

**Go and TypeScript are just folders — they do not interfere**
The two toolchains are completely independent and coexist without conflict. `apps/server/go.mod` is a Go module. `apps/mobile/package.json` is a Node project. Neither knows the other exists. There is no shared runtime, no shared module system, and no shared build step. They happen to live in the same git repository, which is the only thing "monorepo" means here.

**The critical rule: no JS tooling managing Go**
The only way a mixed-language monorepo becomes painful is if you force a JS monorepo tool (Turborepo, Nx, pnpm workspaces) to orchestrate the Go side. Don't. The root `Makefile` is the only cross-language coordinator — it calls `go` commands for the server and `pnpm` commands for mobile. Each app's own tooling handles everything else.

**CI/CD pipelines stay independent via `paths:` filters**
The two apps have completely different build and deploy steps:

| Step | Backend (Go) | Mobile (React Native / Expo) |
|---|---|---|
| Build | `go build` → Docker image | `eas build` → `.ipa` / `.apk` on Expo's cloud |
| Test | `go test ./...` | Jest + Maestro |
| Deploy | `flyctl deploy` → Fly.io | `eas submit` → App Store + Play Store |
| Secrets | Fly.io token, DB URL, Clerk, Claude | Expo token, Apple, Google Play, Clerk publishable key |

GitHub Actions `paths:` filters keep these pipelines independent. A change in `apps/mobile/**` never triggers the Go pipeline and vice versa. Both pipelines live in `.github/workflows/` in the same repo — one place to find them, one set of repo secrets to manage.

**Atomic commits across the stack**
An API shape change and its corresponding mobile client update ship in one PR, one review, one merge. With polyrepo this requires two PRs, two reviews, manual coordination, and the risk of the mobile side lagging behind permanently.

**Splitting out later is trivial**
Git history is preserved per-directory. When and if the team grows to the point where backend and mobile need independent ownership, `git filter-repo` extracts `apps/server/` into its own repo in minutes with full history intact. Start simple, optimise later.

**Revisit if:** The team grows to the point where backend and mobile are owned by separate teams who need independent access controls or release pipelines that `paths:` filters cannot satisfy.

---

### CI/CD — GitHub Actions + Fly.io + EAS

**Chosen:** GitHub Actions for pipeline orchestration, Fly.io for backend deploy, EAS Build for mobile
**Rejected:** CircleCI, Jenkins, self-hosted runners, Render, Railway, raw EC2

**Why GitHub Actions:**
- Already in GitHub — no third-party account, no webhook setup, secrets live in the same place as the code
- `paths:` filters keep backend and mobile pipelines fully independent — a mobile CSS change never triggers a Go build
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

### Folder Structure — `apps/` + `internal/`

**Chosen:** `apps/{server,mobile}` at the top level; Go code under `apps/server/internal/`; root `Makefile` and `docker-compose.yml`
**Rejected:** Flat structure, `src/` root, domain-first top-level (`auth/`, `trades/`), MVC layout

**Top-level layout:**
```
cryptopapertrade-api/
├── apps/
│   ├── server/              # Go backend (Gin)
│   │   ├── cmd/api/main.go
│   │   ├── internal/
│   │   │   ├── auth/
│   │   │   ├── trades/
│   │   │   ├── engine/
│   │   │   ├── worker/
│   │   │   ├── database/
│   │   │   └── models/
│   │   ├── migrations/
│   │   ├── Dockerfile
│   │   └── go.mod
│   └── mobile/              # React Native (Expo)
│       ├── app/
│       ├── components/
│       └── package.json
├── .github/workflows/
├── docker-compose.yml       # local Postgres + Redis
├── Makefile                 # cross-app dev commands
└── .env.example
```

**Why `apps/` at the root:**
- Makes it immediately obvious this is a multi-app repo — no guessing whether `server/` is a subdirectory of something else
- Each app is independently runnable and deployable; the folder boundary makes that clear

**Why Go `internal/` with package-per-domain:**
- `internal/` is a Go language feature — packages inside it cannot be imported by code outside `apps/server/`. Enforces encapsulation at the compiler level.
- One package per domain keeps each concern testable in isolation; `engine/pnl.go` is pure functions with no DB dependency
- `repository.go` per domain keeps all SQL in one place — handlers never write raw queries

**Rejected alternatives:**
- **Flat `server/` with all files at top level** — becomes unnavigable past ~10 files
- **Domain folders at repo root** (`/auth`, `/trades`) — ambiguous whether frontend, backend, or shared
- **MVC layout** (`controllers/`, `models/`, `views/`) — doesn't map cleanly to Go idioms; creates cross-cutting dependencies

**Revisit if:** A domain grows large enough to warrant its own microservice — extract the `internal/<domain>` package into a separate repo.

---

### Engineering Principles — Clean Architecture, SOLID, 12-Factor App

These are not single decisions but constraints that shape every implementation choice. Recorded here so future contributors understand the "why" behind the patterns they'll see in the code.

---

**Clean Architecture**

**Chosen:** Clean Architecture (layered dependency inversion)
**Rejected:** Active Record, flat handler pattern, MVC, Transaction Script

---

**What it is**

A layered structure where dependencies only point inward. Outer layers (HTTP, DB) know about inner layers (business logic), but never the reverse.

```
HTTP Handler (Gin)          ← outermost: knows about services
      │  calls
      ▼
  Service / Use Case         ← business logic: no framework imports
      │  calls
      ▼
  Repository interface       ← defined in the domain package
      │  implemented by
      ▼
  Postgres / Redis / Claude  ← outermost: infrastructure details
```

- Handlers know about services; services do not know about Gin
- Repositories are interfaces — swappable for fakes in tests without a real DB
- The matching engine (`internal/engine/`) has zero knowledge of HTTP or Postgres; it is pure Go functions

**Practical rule:** If you need to import `gin` inside `internal/engine/` or `internal/trades/repository.go`, the boundary is wrong.

---

**Why Clean Architecture was chosen**

**Testability without a running database**
The single biggest payoff. Because repositories are interfaces, unit tests for business logic (PnL calculation, trade ownership, analysis formatting) inject a fake repository with no DB connection. Tests run in milliseconds. Without this boundary, every test that touches a service layer needs a real Postgres instance or a complex mock setup.

**The matching engine is completely isolated**
`internal/engine/` compares prices against open trades and calculates PnL. It has no HTTP dependency and no DB dependency. It is pure functions over plain Go structs. This means it can be tested exhaustively with table-driven tests, benchmarked independently, and replaced entirely without touching any handler or repository.

**Framework lock-in is avoided**
If Gin is swapped for another HTTP framework, only the handler files change. The service layer, repositories, and engine are unaffected. The same applies to the database driver — switching from `pgx` to `database/sql` only touches the repository implementation files.

**The AI provider is swappable**
`internal/ai/` defines an interface. The Claude implementation satisfies it. If a cheaper or faster model becomes available, a new implementation file is added and the composition root in `main.go` is updated — nothing else changes. This was a direct response to the CRITIQUE.md concern about tight coupling to a single AI provider.

---

**Alternatives considered and rejected**

**Active Record**
The model struct handles its own persistence — e.g. `trade.Save()` calls the DB directly. Popular in Rails and some Go ORMs (GORM).

*Why rejected:*
- Business logic and persistence are coupled in the same struct, making unit testing impossible without a real DB
- Adding caching, auditing, or switching DB drivers requires modifying the model — violates Open/Closed
- GORM's magic (hooks, associations) introduces unpredictable query behaviour that is hard to debug and tune

**Flat handler pattern (all logic in handlers)**
All DB calls, calculations, and external API calls written directly inside the Gin handler functions. Common in quick prototypes.

*Why rejected:*
- Handlers become untestable — you can't call a handler in a unit test without a full HTTP stack, DB, and external APIs
- Logic duplicates across handlers (ownership checks, PnL formulas) because there is no shared service layer
- A single handler file grows to hundreds of lines as features are added
- Replacing any dependency (DB, auth, AI) requires editing every handler that touches it

**MVC (Model-View-Controller)**
Three layers: models (data), views (templates/JSON), controllers (request handling). Standard in web frameworks like Laravel, Django, Rails.

*Why rejected for Go:*
- "View" maps poorly to a JSON API — there is no template rendering
- "Model" in MVC typically combines DB schema and business logic, creating the same coupling problem as Active Record
- Go idioms favour composition and interfaces over inheritance-based MVC patterns
- The domain packages (`trades/`, `engine/`, `worker/`) express the architecture more clearly than a `controllers/models/views/` split

**Transaction Script**
Each operation (open trade, close trade, calculate stats) is a standalone function with direct DB access. No layering.

*Why rejected:*
- Starts clean but degrades fast — shared logic (ownership checks, PnL) gets copy-pasted across scripts
- No natural place for the matching engine, which needs to hold state (open trades map) between price ticks
- Testing requires a real DB for every script

---

**Trade-offs and costs of Clean Architecture**

It is not free. These are the real costs:

| Cost | Detail |
|---|---|
| **More files** | A feature like "close a trade" touches `handler.go`, `service.go`, `repository.go`, and `models.go` instead of one file. Navigation requires understanding the layer structure. |
| **Boilerplate interfaces** | Every repository needs an interface definition even when there is only one implementation. For a small project this feels over-engineered initially. |
| **Indirection** | Tracing a bug requires following the call chain through multiple layers. A flat handler makes it easy to see everything in one place. |
| **Slower to start** | The first feature takes longer to scaffold than it would with a flat approach. Productivity improves as the codebase grows. |

**When it would be overkill:** A weekend script, a single-endpoint proxy, or any project that will never need unit tests or dependency swapping. For this project — with a matching engine, async workers, a swappable AI provider, and a requirement for testable PnL calculations — the layering pays for itself by Stage 4.

**Revisit if:** The service layer turns out to be a thin pass-through with no real logic (handlers call repositories directly, services add nothing). If that happens, collapse the service layer and call repositories from handlers directly — do not add abstraction that carries no value.

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

### Trade Closure — Mandatory SL/TP, Manual Close Post-MVP

**Chosen:** Stop-loss and take-profit are required fields on every trade. Trades close only when the engine hits a target. Manual user-initiated close is deferred to post-MVP.
**Rejected:** Optional SL/TP with immediate manual close support.
**Why:**
- Mandatory SL/TP enforces disciplined risk management — the core habit the app is trying to teach. A trade with no exit plan is not a paper trade, it's an open-ended position.
- Logical validation (SL below entry for longs, above for shorts) can be enforced at the API layer without ambiguity when both fields are always present.
- The DB schema stays clean: `stop_loss NOT NULL`, `take_profit NOT NULL`. No nullable handling in the matching engine.
- Manual close adds meaningful complexity: a new API endpoint, UI affordance, and a separate close-reason field in the DB (SL hit / TP hit / manual). Deferring it keeps Stage 4 and Stage 5 focused.
- Manual close is the natural next feature after MVP — the groundwork (close logic in the engine, the `PUT /trades/:id/close` stub in the API) is already identified and documented.
**Revisit if:** User research shows mandatory SL/TP is a significant onboarding blocker.

---

### Desktop App Framework — Decision Deferred

**Chosen:** Decision deferred until mobile v1 ships
**Candidates:** Tauri (Rust + WebView), Electron (Node.js + Chromium), Flutter Desktop
**Why deferred:**
- Mobile is the primary v1 client; desktop is a future enhancement
- When the time comes, desktop lives in its own repo — same as mobile
- The right framework depends on scope at that point:
  - **Tauri** is the default candidate: Rust core + WebView, React UI, small bundle (~5–10 MB vs Electron's ~150 MB), strong capability-grant security model
  - **Electron** is the safe fallback: mature ecosystem, battle-tested, heavier
  - **Flutter Desktop** only fits if the mobile app is rebuilt in Flutter — not the current plan

**Revisit when:** Mobile v1 ships and desktop feature scope is defined.

---
