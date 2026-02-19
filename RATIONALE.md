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
- AI critique jobs must survive server restarts — goroutines do not
- Asynq provides retry with backoff, deduplication by trade ID, and a built-in dashboard
- Decouples trade-close latency from Claude API latency (which can be 3–10s)
**Revisit if:** Redis adds unacceptable operational overhead for the scale we're at

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
