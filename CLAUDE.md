# Crypto Paper Trader — Claude Code Instructions

Read this file before doing anything else in a session. It defines the project, the rules, and the commands.

---

## Project Summary

Mobile paper trading app for crypto. Users open trades with entry price, optional SL/TP. The Go backend streams live prices via CCXT WebSockets, auto-closes trades when targets are hit, and queues an AI post-mortem (Claude API) via Asynq after each close. Mobile app receives live prices via SSE.

**Stack:** Go + Gin · PostgreSQL · Clerk auth · Asynq + Redis · CCXT · SSE · Claude API · Stripe · React Native (Expo) · Fly.io · GitHub Actions

---

## Key Files

| File | When to read it |
|---|---|
| `BUILD.md` | Starting a coding session — contains the staged plan, schema, packages, and deliverables |
| `PLAN.md` | Checking immediate priorities and current tech stack decisions |
| `RATIONALE.md` | Before making any architectural decision — records what was chosen, rejected, and why |
| `README.md` | Project overview and local dev setup |

---

## Current Stage

**Stage 0 — not started.**
Work through stages in order. Do not skip. Each stage's deliverable is the foundation for the next.
Update this line when a stage is complete.

---

## Common Commands

```bash
# Local dev
make dev          # start Docker services + Go server
make test         # run Go tests
make lint         # run golangci-lint
make migrate      # run DB migrations

# Docker
docker-compose up -d          # start Postgres + Redis
docker-compose down           # stop services
docker-compose logs -f        # tail logs

# Go
go run cmd/api/main.go
go test ./...
go mod tidy
```

---

## Engineering Rules

These are non-negotiable. Violating them introduces bugs or security issues.

**Architecture**
- Dependencies flow inward only: Handler → Service → Repository → DB. Never reverse.
- No raw SQL in handlers. All queries go in `repository.go` files.
- No framework imports (`gin`, `pgx`) inside `internal/engine/` or `internal/worker/`.
- Composition root is `cmd/api/main.go` — the only place concrete types are wired together.

**Security**
- Never commit secrets. All config via environment variables. `.env` is gitignored.
- Crash-fail at startup if required env vars are missing. No silent defaults.
- Ownership middleware on every trade route — users can only access their own data.
- All DB queries use parameterised statements. No string-concatenated SQL.

**Code style**
- One `handler.go`, one `repository.go`, one `service.go` per domain package.
- Interfaces defined in the consuming package, not the implementing package.
- Errors wrapped with context: `fmt.Errorf("trades: close: %w", err)`.
- Structured JSON logging via `zerolog`. No `fmt.Println` in production paths.

**Database**
- Migrations are forward-only. No destructive `DROP` without an explicit rollback file.
- Migrations run as a one-off CI step before the server starts. Never inside the running app.

**Git**
- PR required before merging to `main`. CI must pass.
- Never force-push to `main`.

---

## Package Conventions (Go)

```
cryptopapertrader-api/       # repo root
├── cmd/api/main.go          # composition root — wire everything here
├── internal/
│   ├── auth/                # Clerk middleware + webhook handler
│   ├── trades/              # handler + repository + service
│   ├── engine/              # price matching, PnL — no HTTP/DB imports
│   ├── worker/              # Asynq task definitions and handlers
│   ├── database/            # connection pool, migration runner
│   └── models/              # shared Go structs matching DB tables
```

---

## Environment Variables

See `.env.example` for the full list with descriptions.
Required at each stage are listed in the corresponding BUILD.md stage section.
