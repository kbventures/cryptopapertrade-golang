# Crypto Paper Trader

A mobile app for paper trading crypto — practice trading with real-time prices, no real money. Trades auto-close when price hits stop-loss or take-profit. Each closed trade gets an AI-generated post-mortem via Claude.

---

## What it does

- Open a paper trade (symbol, side, entry price, stop-loss, take-profit)
- Server streams live prices via CCXT WebSockets and auto-closes trades when targets are hit
- Closed trades trigger a background AI analysis job (Claude API)
- Mobile app receives live price updates via SSE; push notifications when a trade closes
- Subscription gating via Stripe (free tier: 5 open trades; Pro: unlimited + AI analysis)

---

## Stack

| Layer | Technology |
|---|---|
| Backend | Go + Gin |
| Mobile | React Native (Expo) |
| Database | PostgreSQL |
| Auth | Clerk (Google Sign-In) |
| Queue | Asynq + Redis (Upstash) |
| Market Data | CCXT WebSockets |
| Real-time delivery | SSE (server → mobile) |
| AI Analysis | Claude API (Anthropic) |
| Payments | Stripe |
| Hosting | Fly.io (backend + DB), EAS (mobile) |
| CI/CD | GitHub Actions |

---

## Repository Layout

This is the backend API repository. Mobile and desktop live in separate repos.

| Repo | Contents |
|---|---|
| `cryptopapertrader-api` | Go backend (this repo) |
| `cryptopapertrader-mobile` | React Native (Expo) |
| `cryptopapertrader-desktop` | Desktop app (not started) |

```
cryptopapertrader-api/
├── cmd/
│   └── api/
│       └── main.go          # composition root
├── internal/
│   ├── auth/                # Clerk middleware + webhook handler
│   ├── trades/              # handler + service + repository
│   ├── engine/              # price matching, PnL — no HTTP/DB imports
│   ├── worker/              # Asynq task definitions and handlers
│   ├── database/            # connection pool, migration runner
│   └── models/              # shared Go structs matching DB tables
├── .github/
│   └── workflows/
│       └── deploy-server.yml
├── docker-compose.yml
└── .env.example
```

---

## Local Development

**Prerequisites:** Go 1.22+, Node.js 20+, pnpm, Docker

```bash
# Start Postgres + Redis
docker-compose up -d

# Run backend
cp .env.example .env   # fill in values
go mod download
go run cmd/api/main.go
```

Mobile development lives in the `cryptopapertrader-mobile` repo.

---

## Documentation

| File | Purpose |
|---|---|
| [PLAN.md](./PLAN.md) | **Start here.** Current tech stack and the three immediate build priorities (Docker, Clerk auth, CI/CD). Read this to understand what we're building next and why. |
| [BUILD.md](./BUILD.md) | **Full staged roadmap.** 12 stages in order — each with concrete tasks, SQL schema, Go packages, env vars, and a deliverable to verify before moving on. Open this when starting a coding session. |
| [RATIONALE.md](./RATIONALE.md) | **Decision log.** Why every significant technical choice was made, what was rejected, and under what conditions the decision should be revisited. Covers auth, framework, CI/CD, folder structure, Clean Architecture, SOLID, 12-Factor App, and OWASP security. |
| [PAPER_TRADE_FLOW.html](./PAPER_TRADE_FLOW.html) | **Visual flow diagram.** Open in a browser. Shows the full lifecycle of a paper trade from open → price hit → auto-close → AI analysis → user notification. |
