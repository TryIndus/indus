# Indus Revamp Plan

This document contains the full rewrite plan: target architecture, phase-by-phase steps, verification checklists, and post-rewrite configuration.

---

## Known Issues (Pre-Rewrite)

- Alpaca API keys exposed as `NEXT_PUBLIC_*` (client-side visible — security vulnerability)
- TypeScript and ESLint errors ignored in builds (`ignoreBuildErrors: true`, `ignoreDuringBuilds: true`)
- No test suite
- `supabase.auth.getUser()` called twice in middleware
- Middleware only protects `/dashboard`, `/company`, `/search` — the `/crypto`, `/reports`, `/settings` routes are unprotected
- Socket.io adds ~50KB to client bundle for a unidirectional data flow
- Manual SSE streaming logic in `/api/context-chat` (~190 lines of boilerplate)
- No input validation on any API route
- No agent capabilities — AI is single-turn Q&A with pre-packed context, not agentic
- No server-side caching for AI explanations — every batch-explain request hits Gemini even when the same symbol+metric was just explained for another user
- Explanation caching is client-only (localStorage) — no cross-user benefit
- Socket.io server uses Pages Router (`pages/api/socket/index.ts`) while the rest of the app uses App Router — mixed routing
- Crypto real-time bar handler in `lib/server/alpaca-server.ts:278` hardcodes `const symbol = "ETH/USD"` instead of reading from bar data — only ETH/USD gets real-time crypto updates, all other crypto symbols are silently dropped
- No React error boundaries or loading states
- `lib/prompts.ts` and `lib/system-prompts.ts` are tightly coupled to the raw Gemini API format
- `scripts/check-env.js` exists as a manual env check script but is not integrated into any build or dev workflow
- `@radix-ui/react-icons` is in dependencies but Lucide is the actual icon library — likely dead dependency
- `tw-animate-css` is in devDependencies — verify if still needed or remove during bundle audit

---

## Target Tech Stack (Post-Rewrite)

### Decisions Made

| Layer | Choice | Rationale |
|---|---|---|
| **Deployment** | Vercel Hobby | Best-in-class Next.js DX, free tier covers portfolio use, 60s serverless function timeout (SSE auto-reconnects) |
| **Framework** | Next.js 15 (App Router) + React 19 | Already modern — clean up usage, properly leverage RSC and Server Actions |
| **Database & Auth** | Supabase (stay) | Already integrated, auth + realtime + PostgreSQL in one. Keep project active via Vercel cron. |
| **AI Provider** | Vercel AI SDK v6 + `@ai-sdk/google` (Gemini) | Replaces manual streaming with `useChat()`/`streamText()`, enables agentic tool use, provider-swappable |
| **AI Models** | Gemini 2.5 Flash (explanations), Gemini 2.5 Pro (chat + reports) | Cost-optimized: Flash for fast/cheap single-turn, Pro for reasoning-heavy multi-turn and long-form |
| **State Management** | Zustand (client state) + TanStack Query (server/async state) | Eliminates Context re-render issues, replaces all manual fetch patterns with caching/revalidation |
| **Real-time** | SSE via Next.js Route Handlers (replace Socket.io) | Unidirectional flow = SSE is the right primitive. Zero client library. Saves ~50KB bundle. |
| **Validation** | Zod | Runtime validation + TypeScript type inference on all API boundaries, env vars, external API responses |
| **Testing** | Vitest (unit/integration) + Playwright (E2E) | Industry standard. Vitest for API routes/utils, Playwright for auth flows and chart rendering. |
| **Linting/Formatting** | Biome (replaces ESLint + Prettier) | Single tool, 10-100x faster, zero config |
| **Charts** | TradingView Lightweight Charts v5 (keep) | Purpose-built for OHLCV candlestick data, ~40KB, no better alternative |
| **Styling** | Tailwind CSS v4 + shadcn/ui + Lucide (keep) + add next-themes | Already best-practice. Add next-themes for proper dark/light toggle instead of hardcoded dark. |
| **Package Manager / Runtime** | Bun (replace npm) | 10-25x faster installs, native TypeScript execution, built-in test runner, drop-in Node.js compatible. |
| **Date utils** | date-fns v4 (keep) | Already modern, tree-shakeable |
| **Financial Data** | Alpaca + Yahoo Finance 2 (keep) | Working data sources, no reason to change |

### Full Target Stack Summary

```
Runtime & Tooling:    Bun + Biome
Framework:            Next.js 15 (App Router) + React 19 + TypeScript 5
Styling:              Tailwind CSS v4 + shadcn/ui (Radix) + Lucide + next-themes
Auth & DB:            Supabase (PostgreSQL + Auth + Realtime)
AI:                   Vercel AI SDK v6 + Gemini 2.5 Pro / Flash
State:                Zustand (client) + TanStack Query (server)
Real-time:            SSE (server-maintained Alpaca WS → SSE to client)
Validation:           Zod (API inputs, env vars, external responses)
Testing:              Vitest + Playwright
Charts:               TradingView Lightweight Charts v5
Financial Data:       Alpaca Trade API + Yahoo Finance 2
Deployment:           Vercel Hobby (free tier)
```

---

## Architecture (Post-Rewrite)

### Data Flow

```
User Browser
  ├── useChat() (Vercel AI SDK) ──→ /api/chat ──→ Gemini 2.5 Pro
  │                                                   ├── tool: getStockPrice (Alpaca)
  │                                                   ├── tool: getFinancialMetrics (Yahoo)
  │                                                   ├── tool: compareCompanies
  │                                                   └── tool: searchNews
  │
  ├── TanStack Query ──→ /api/stock-data ──→ Yahoo Finance 2
  ├── TanStack Query ──→ /api/alpaca ──→ Alpaca REST API
  │
  ├── EventSource (SSE) ──→ /api/stream/[symbol] ──→ Alpaca WebSocket (server-side)
  │
  └── Zustand stores (UI state, favorites, settings)
        └── persisted to Supabase via TanStack Query mutations
```

### API Routes (Post-Rewrite)

| Route | Method | Purpose | AI Model |
|---|---|---|---|
| `/api/chat` | POST | Agentic financial chat with tool use | Gemini 2.5 Pro via `streamText()` |
| `/api/explain` | POST | Batch metric explanations (Supabase-cached) | Gemini 2.5 Flash via `generateText()` |
| `/api/reports/generate` | POST | Multi-step research report generation | Gemini 2.5 Pro via `generateText()` + tools + `maxSteps` |
| `/api/reports` | GET | List user reports | — |
| `/api/reports/[id]` | GET/DELETE | Get or delete a report | — |
| `/api/stock-data` | GET | Financial metrics from Yahoo Finance | — |
| `/api/alpaca` | POST | Historical candlestick bars | — |
| `/api/stream/[symbol]` | GET | SSE real-time price stream | — |
| `/api/metric-definition` | GET | Static metric definitions | — |
| `/api/cron/keepalive` | GET | Vercel cron — pings Supabase to prevent auto-pause | — |

### AI Agent Architecture

The AI chat becomes an agentic system where Gemini autonomously decides which tools to call:

**Tools defined with Zod schemas:**
- `getStockPrice` — fetches real-time price/volume from Alpaca
- `getFinancialMetrics` — fetches P/E, margins, revenue, etc. from Yahoo Finance
- `compareCompanies` — fetches and collates metrics for multiple symbols
- `searchNews` — searches recent financial news (future: add news API)
- `getMetricDefinition` — looks up metric definitions from the static definitions file

**Agent loop:** `streamText({ model, tools, maxSteps: 5 })` — Gemini calls tools, gets results, reasons, calls more tools if needed, then synthesizes a final response. This replaces the current pattern of pre-packing all context into the prompt.

**Model routing:**
- User asks a quick question about a metric → Gemini 2.5 Flash (fast, cheap)
- User has a multi-turn conversation about a stock → Gemini 2.5 Pro (stronger reasoning, larger context)
- Generate a research report → Gemini 2.5 Pro with tools and maxSteps (autonomous multi-step research)

**Server-side explanation cache (Supabase):**
- Metric explanations are symbol+metric specific, not user-specific — cache them in Supabase so all users benefit
- New table: `metric_explanations` (symbol, metric, explanation, created_at)
- Cache key: symbol + metric (e.g., `AAPL` + `pe_ratio`)
- On request: query Supabase for matching row where `created_at > now() - 1 hour`
- Cache hit → return immediately, skip Gemini API call entirely
- Cache miss → call Gemini, upsert result into `metric_explanations`, return to client
- Supabase cache survives Vercel cold starts (unlike in-memory caching on serverless)
- Client-side TanStack Query adds a second caching layer per-user with stale-while-revalidate
- **Cache cleanup:** The `/api/cron/keepalive` daily cron job (Phase 6) should also delete `metric_explanations` rows older than 24 hours to prevent unbounded table growth. Stale rows (>1h) are refreshed on demand, but unused rows would otherwise accumulate forever.

**Prompt files:**
- `lib/prompts.ts` and `lib/system-prompts.ts` must be adapted for the Vercel AI SDK format
- System prompts become a first-class `system` parameter in `streamText()` / `generateText()` — no more string concatenation
- Prompt construction logic stays in these files but the interface changes

### State Architecture (Post-Rewrite)

**Zustand stores** (client state, no providers needed):
- `useAuthStore` — user session, signOut (replaces AuthContext)
- `useFavoritesStore` — favorite symbols (replaces FavoritesContext)
- `useUIStore` — sidebar state, theme, mobile detection

**TanStack Query** (server/async state):
- Stock data queries with caching and stale-while-revalidate
- Report list with optimistic updates on delete
- Favorites synced to Supabase via mutations
- Alpaca historical bars with pagination

### Real-time Architecture (Post-Rewrite)

Replace Socket.io with SSE:

**Server side:** A Next.js Route Handler (`/api/stream/[symbol]`) creates an Alpaca WebSocket connection, subscribes to the requested symbol, and writes bar data to a `ReadableStream` as SSE events. The route must detect whether the symbol is a stock or crypto asset (crypto symbols contain `/`, e.g., `ETH/USD`) and use the appropriate Alpaca stream: `data_stream_v2` for stocks, `crypto_stream_v1beta3` for crypto. These are different SDK APIs with different subscription methods and data shapes.

**Client side:** Native `EventSource` API connects to the SSE endpoint. Zero library needed. The `StockChart` and `CryptoChart` components consume events and update the TradingView chart.

**Serverless isolation tradeoff (accepted):** On Vercel, each App Router route handler is an isolated serverless function invocation. This means every SSE client connection creates its own Alpaca WebSocket connection — there is no shared singleton like the current `AlpacaService`. If 5 users watch AAPL simultaneously, that's 5 separate Alpaca WebSocket connections. This is acceptable for a portfolio project with low concurrent users, but would not scale. See "Future Improvements" below for the Supabase Realtime fan-out solution that eliminates this limitation.

**SSE reconnection handling:** Vercel Hobby has a hard 60-second serverless function timeout (not configurable — only Pro/Enterprise can increase to 120s+). The SSE stream will drop when the function times out. The native `EventSource` API auto-reconnects by default, but the client must:
- Handle the `onerror` event gracefully (don't show an error to the user on expected reconnects)
- Use `Last-Event-ID` header to resume from where it left off (the server includes an incrementing event ID)
- Show a brief "reconnecting" indicator only if reconnection takes more than a few seconds
- Reconnection involves a cold start: new serverless function → new Alpaca WebSocket → subscribe → wait for first bar. This can take 2-5 seconds, not sub-second. At 1-minute bar timeframes, users are unlikely to notice a missed bar, but the reconnecting indicator should account for this delay.

**Bundle impact:** Removes `socket.io-client` (~50KB) and `socket.io` (server). Net client bundle reduction: ~50KB.

---

## Deployment & Operations

### Supabase Auto-Pause Prevention

Supabase free tier pauses projects after 7 days of inactivity. Solution: **Vercel Cron Job** (no external services needed).

- Add a `vercel.json` with a cron definition that runs daily
- The cron calls `/api/cron/keepalive` — a simple route handler that does `SELECT 1` from Supabase
- Vercel Hobby allows 1 cron job, max once per day — more than enough
- This keeps Supabase active with zero external infrastructure

```json
// vercel.json
{
  "crons": [
    {
      "path": "/api/cron/keepalive",
      "schedule": "0 8 * * *"
    }
  ]
}
```

### Environment Variable Switchover

During the rewrite, both old and new env vars must coexist:
- **Before Phase 3:** Add `GOOGLE_GENERATIVE_AI_API_KEY` to Vercel dashboard (same value as `GEMINI_API_KEY` — it's the same Google API key)
- **During Phase 3:** Both `GEMINI_API_KEY` (used by old routes not yet migrated) and `GOOGLE_GENERATIVE_AI_API_KEY` (used by new Vercel AI SDK routes) are active
- **After Phase 3 complete:** Remove `GEMINI_API_KEY` from Vercel dashboard, remove from `lib/env.ts` Zod schema

---

## Rewrite Phases

### Important Constraints

- **Do not touch `pages/` directory until Phase 4.** The Socket.io server at `pages/api/socket/index.ts` uses Pages Router. It must continue working through Phases 1-3. Phase 4 replaces it with SSE and deletes the entire `pages/` directory.
- **The `@alpacahq/alpaca-trade-api` SDK stays.** Phase 4 only removes the WebSocket manager class (`lib/server/alpaca-server.ts`) and Socket.io transport. The Alpaca SDK is still needed for REST API calls (historical bars in `/api/alpaca`).
- **Test after every phase.** Each phase ends with a verification checklist. Do not proceed to the next phase until all checks pass.
- **Unit tests grow with each phase.** Vitest is set up from Phase 1 onward. Each phase must add unit tests that cover its deliverables (schemas, utilities, business logic). Tests are cumulative — Phase 2 tests build on Phase 1 tests, etc. All prior phase tests must continue passing. Run `bun test` at the end of every phase.

---

### Phase 1: Foundation (No Feature Changes) ✅ COMPLETE

1. **Switch npm → Bun** — `rm -rf node_modules package-lock.json && bun install`
2. **Replace ESLint with Biome** — remove eslint config, add `biome.json`, run `biome check --fix`
3. **Add Zod** — create `lib/env.ts` with validated env vars, add schemas to all API route inputs. Remove `scripts/check-env.js` (replaced by Zod validation).
4. **Fix security: move Alpaca keys server-side** — remove `NEXT_PUBLIC_` prefix, all Alpaca calls already go through API routes
5. **Fix middleware** — call `getUser()` once, reuse result. Also add `/crypto`, `/reports`, and `/settings` to the protected route list (currently unprotected).
6. **Enable TypeScript strict builds** — remove `ignoreBuildErrors`, fix all type errors
7. **Enable Biome in builds** — remove `ignoreDuringBuilds`, fix all lint errors
8. **Add next-themes** — replace hardcoded `className="dark"` with proper theme provider and toggle

**Verification:** All passing.

---

### Phase 2: State & Data Fetching

9. **Add TanStack Query** — create query client provider, convert all `useEffect` fetch patterns to `useQuery`/`useMutation`
10. **Add Zustand** — replace `AuthContext` with `useAuthStore`, replace `FavoritesContext` with `useFavoritesStore`
11. **Remove React Context providers** from layout (replaced by Zustand + TanStack Query)
12. **Add React error boundaries** — wrap major sections (charts, financial tables, chat) with error boundaries and `<Suspense>` fallbacks with skeleton loading states

**Verification:**
- Auth flow works end-to-end: sign up, sign in (email + Google OAuth), sign out, session persistence
- Favorites: add, remove, persist across page reloads, sync to Supabase
- Stock data loads on company pages with loading skeletons visible during fetch
- Dashboard populates with data (no waterfall fetches — check Network tab)
- Error boundaries catch and display errors gracefully (test by temporarily breaking an API route)
- Chart real-time data still works (`pages/api/socket` untouched)
- No React Context providers remain in `app/layout.tsx`

**Rollback:** Revert individual commits. Context providers and manual fetch patterns are preserved in git history.

---

### Phase 3: AI Modernization

13. **Add `GOOGLE_GENERATIVE_AI_API_KEY` to Vercel dashboard** before deploying any Phase 3 changes (same value as existing `GEMINI_API_KEY`)
14. **Add Vercel AI SDK + @ai-sdk/google** — `bun add ai @ai-sdk/google`
15. **Create `metric_explanations` table in Supabase** — columns: `id`, `symbol`, `metric`, `explanation` (jsonb), `created_at` (timestamptz, default now()). Add unique constraint on (symbol, metric). Add index on created_at for TTL queries.
16. **Rewrite `/api/context-chat`** → `/api/chat` using `streamText()` with Gemini 2.5 Pro + tool definitions
17. **Rewrite `/api/batch-explain`** → `/api/explain` using `generateText()` with Gemini 2.5 Flash + Zod structured output + Supabase explanation cache (1h TTL)
18. **Adapt `lib/prompts.ts` and `lib/system-prompts.ts`** — refactor prompt construction for Vercel AI SDK format (system prompt as separate parameter, tool descriptions as Zod schemas)
19. **Rewrite `/api/reports/generate`** using `generateText()` with tools + `maxSteps` for multi-step autonomous research
20. **Update chat frontend** — replace manual SSE parsing with `useChat()` from AI SDK. Clear legacy localStorage explanation cache keys on first load to prevent stale data from the old caching approach.
21. **Add rate limiting to AI endpoints** — simple per-user rate limit on `/api/chat`, `/api/explain`, and `/api/reports/generate` (e.g., check request count per user_id in the last N seconds via Supabase or in-memory counter). Prevents a single user from exhausting Gemini API quota. Even a basic implementation (e.g., 20 chat requests/min, 5 report generations/hour) is better than none.
22. **Remove raw `@google/generative-ai`** and `lib/ai/geminiClient.ts` (replaced by Vercel AI SDK's Google provider)
23. **Remove `GEMINI_API_KEY`** from `lib/env.ts` Zod schema and Vercel dashboard

**Verification:**
- Chat works: ask "What is Apple's P/E ratio?" — Gemini should call `getFinancialMetrics` tool, get data, synthesize answer
- Multi-step: ask "Compare AAPL and MSFT" — Gemini should call tools multiple times
- Explanations: hover over a metric, verify explanation loads. Check Supabase `metric_explanations` table — row should exist. Hover again — should be instant (cache hit, no Gemini call). Wait >1 hour or manually set `created_at` to 2 hours ago — next request should refresh the cache.
- Reports: generate a report, verify it completes and saves to Supabase
- `useChat()` streaming works — response appears word-by-word, not all at once
- No references to `@google/generative-ai` remain in codebase (`grep -r "generative-ai"`)
- `GEMINI_API_KEY` no longer in env validation or Vercel dashboard

**Rollback:** Revert individual commits. If rolling back the entire phase, re-add `GEMINI_API_KEY` to Vercel dashboard. The `metric_explanations` table can stay in Supabase (harmless).

---

### Phase 4: Real-time Modernization

24. **Create SSE endpoint** — `/api/stream/[symbol]/route.ts` that creates an Alpaca WebSocket connection per request, subscribes to the symbol, and streams bars as SSE events with event IDs for reconnection. Must detect stock vs. crypto symbols (crypto contains `/`, e.g., `ETH/USD`) and use the correct Alpaca stream: `data_stream_v2` for stocks, `crypto_stream_v1beta3` for crypto. **Note:** The current `alpaca-server.ts` has a bug where the crypto bar handler hardcodes `const symbol = "ETH/USD"` instead of extracting the symbol from the bar data — the SSE endpoint must fix this by properly reading the symbol from the Alpaca bar event.
25. **Add SSE reconnection logic to client** — handle `EventSource.onerror`, use `Last-Event-ID`, show reconnecting indicator only after 3+ seconds. Account for the fact that reconnections involve a full cold start (new serverless function → new Alpaca WS → subscribe) which takes 2-5 seconds, not sub-second.
26. **Update StockChart.tsx** — replace socket.io-client with native `EventSource`
27. **Update CryptoChart.tsx** — same SSE migration
28. **Remove Socket.io** — `bun remove socket.io socket.io-client`
29. **Delete `pages/` directory entirely** — removes Pages Router Socket.io handler and eliminates mixed router architecture
30. **Delete `lib/server/alpaca-server.ts`** — WebSocket manager class no longer needed (SSE route handler manages Alpaca connection directly). The `@alpacahq/alpaca-trade-api` SDK stays for REST calls.

**Verification:**
- Open a stock chart — real-time bars should appear via SSE (check Network tab for `EventSource` connection to `/api/stream/[symbol]`)
- Open a crypto chart (e.g., `BTC/USD` and `ETH/USD`) — same SSE verification. Confirm the crypto symbol is correctly parsed from the bar data (not hardcoded).
- Wait 60+ seconds — SSE should auto-reconnect. Reconnecting indicator appears briefly (2-5s) then disappears.
- Check that no gap in data is visible after reconnection at 1-minute timeframe
- `pages/` directory no longer exists
- `socket.io` and `socket.io-client` no longer in `package.json`
- `bun run build` succeeds
- Client bundle size decreased (~50KB less — verify with `next build` output)

**Rollback:** Revert individual commits. If rolling back the entire phase, restore `pages/api/socket/index.ts`, `lib/server/alpaca-server.ts`, and Socket.io dependencies from git history.

---

### Phase 5: Testing & CI/CD

**Testing:**

31. **Add Vitest** — config, first tests on API route handlers (mock Supabase/Alpaca/Gemini), test Zod schemas, test env validation
32. **Add Playwright** — config, E2E tests for: auth flow (sign in, sign out, protected route redirect), dashboard load, company page with chart rendering, AI chat interaction, report generation
33. **Add test scripts** to package.json: `bun test` (Vitest), `bun run test:e2e` (Playwright)

**CI/CD Pipeline (GitHub Actions):**

34. **CI workflow** (`.github/workflows/ci.yml`) — runs on every push to `dev/revamp` and on PRs to `main`:
    - Biome lint check (`biome check`)
    - TypeScript type check (`tsc --noEmit`)
    - Vitest unit/integration tests (`bun test`)
    - Build verification (`next build`)
35. **E2E workflow** (`.github/workflows/e2e.yml`) — runs on PRs to `main`:
    - Waits for Vercel preview deployment to complete (uses `vercel-preview-url` action)
    - Runs Playwright against the Vercel preview URL
    - Reports pass/fail on the PR
36. **Bundle size tracking** (`.github/workflows/ci.yml`) — added as a step in the CI workflow:
    - Runs `next build` and extracts bundle sizes from the build output
    - Comments on PR with bundle size diff vs `main` (uses `actions/github-script` to post the comment)
37. **Lighthouse CI** (`.github/workflows/lighthouse.yml`) — runs on PRs to `main`:
    - Runs Lighthouse against the Vercel preview URL
    - Enforces thresholds: Performance > 90, Accessibility > 95, Best Practices > 90
    - Comments results on the PR
38. **Renovate config** (`renovate.json`) — automated dependency update PRs:
    - Groups minor/patch updates into a single weekly PR
    - Pins major versions (requires manual review)
    - Auto-merges devDependency patches if CI passes

**Branch Protection (requires manual setup by user):**

39. **Configure branch protection rules on `main`** via GitHub Settings → Branches → Add rule:
    - Require status checks to pass (CI workflow)
    - Require branch to be up to date before merging
    - Require at least 1 approval on PRs (even self-approval — shows the pattern)

**What requires manual action by the user:**
- Step 35 (E2E workflow): Vercel automatically provides preview URLs on PRs, but if the repo is **private**, you need to add `VERCEL_TOKEN` as a GitHub Actions secret (Settings → Secrets → Actions → New secret). Get the token from https://vercel.com/account/tokens. If the repo is **public**, the preview URL is available without a token.
- Step 39 (Branch protection): Must be done manually in GitHub UI — cannot be configured via code. Go to repo Settings → Branches → Add branch protection rule for `main`.
- Everything else (steps 31-38) is fully code-based — I create the config files and workflow YAML, no manual setup needed.

**Verification:**
- `bun test` passes — all Vitest unit/integration tests green
- `bun run test:e2e` passes — all Playwright E2E tests green locally
- Tests cover: auth, dashboard, search, company page, chart, chat, reports, favorites
- Push to `dev/revamp` triggers CI workflow — all checks green in GitHub Actions
- Open a test PR to `main` — CI runs, bundle size comment appears, Lighthouse scores reported
- Renovate creates its onboarding PR (will appear automatically after `renovate.json` is pushed)

**Rollback:** Revert individual commits. Tests and CI configs are additive — removing them doesn't break the app.

---

### Phase 6: Polish

40. **Audit bundle size** — `next build` analysis, verify Socket.io is gone, check for unused deps (e.g., `@radix-ui/react-icons`, `tw-animate-css` if unused), remove any dead code
41. **Performance** — add `loading.tsx` skeletons for all routes, optimize TanStack Query stale times, verify no waterfall fetches
42. **Final security audit** — verify no API keys in client bundle, all inputs validated, no `any` types on API boundaries, rate limits on AI endpoints are working
43. **Supabase keepalive + cache cleanup** — add Vercel cron job (`vercel.json` + `/api/cron/keepalive` route) that pings Supabase daily to prevent 7-day auto-pause. The cron should also delete `metric_explanations` rows older than 24 hours to prevent unbounded table growth.

**Verification:**
- `next build` output shows bundle sizes — compare against pre-rewrite baseline
- Lighthouse performance score on dashboard page
- All API routes have Zod input validation
- `grep -r "NEXT_PUBLIC_ALPACA"` returns zero results
- Vercel cron job configured in `vercel.json` and `/api/cron/keepalive` route exists
- Deploy to Vercel preview branch to test cron execution

**Rollback:** Phase 6 changes are non-breaking polish. Individual commits can be reverted independently.

---

## Post-Rewrite: Manual Configuration

Items that cannot be done via code and require manual setup in external dashboards after the rewrite is complete:

- [ ] **GitHub: Add `VERCEL_TOKEN` secret** (only if repo is private) — GitHub → repo Settings → Secrets and variables → Actions → New repository secret. Get the token from https://vercel.com/account/tokens. Required for the E2E workflow to fetch Vercel preview URLs.
- [ ] **GitHub: Branch protection rules on `main`** — GitHub → repo Settings → Branches → Add branch protection rule. Set branch name pattern to `main`, enable: "Require status checks to pass before merging" (select the CI workflow), "Require branches to be up to date before merging", "Require approvals" (set to 1).
- [ ] **Vercel: Add `GOOGLE_GENERATIVE_AI_API_KEY`** — Vercel dashboard → project Settings → Environment Variables. Same value as existing `GEMINI_API_KEY`.
- [ ] **Vercel: Remove `GEMINI_API_KEY`** — after Phase 3 is complete and verified working.
- [ ] **Vercel: Remove `NEXT_PUBLIC_ALPACA_*` vars** — after Phase 1 replaces them with server-only `ALPACA_*` vars.
- [ ] **Supabase: Create `metric_explanations` table** — Supabase dashboard → SQL Editor. Run the migration SQL provided in Phase 3.

---

## New Database Tables

### metric_explanations (Phase 3)

- `id` uuid, primary key
- `symbol` text, not null
- `metric` text, not null
- `explanation` jsonb, not null
- `created_at` timestamptz, default now()
- Unique constraint on (symbol, metric) — upsert on cache refresh
- Index on created_at for TTL-based cache expiry queries
- Rows older than 1 hour are treated as stale and refreshed on next request
- Daily cron job (Phase 6) deletes rows older than 24 hours to prevent unbounded growth

---

## Post-Rewrite Environment Variables

- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (public — required by Supabase client)
- `ALPACA_API_KEY`, `ALPACA_SECRET_KEY`, `ALPACA_IS_PAPER` (server-only — fixed)
- `GOOGLE_GENERATIVE_AI_API_KEY` (server-only — same Gemini API key, now used via Vercel AI SDK)
- `NEXT_PUBLIC_VERCEL_URL`
- All validated at startup via Zod in `lib/env.ts`

---

## Future Improvements (Post-Rewrite)

### Real-time Fan-Out via Supabase Realtime

The Phase 4 SSE implementation creates a **1:1 mapping** between SSE client connections and Alpaca WebSocket connections. Each serverless function invocation is isolated — there is no shared state. This means:
- N concurrent users watching the same symbol = N separate Alpaca WebSocket connections
- Each reconnection (every 60s due to Vercel's function timeout) creates a new Alpaca WS connection with 2-5s startup latency
- Alpaca's free/paper tier has connection limits that could be hit under moderate load

This is acceptable for a portfolio project with low concurrent users, but the proper solution is a **fan-out architecture using Supabase Realtime**:

1. A single always-on process (Supabase Edge Function, Fly.io container, or a dedicated worker) maintains one set of Alpaca WebSocket connections
2. That process writes incoming bar data to a Supabase Realtime channel (or a Supabase table with Realtime enabled)
3. Clients subscribe to the Supabase Realtime channel instead of connecting to an SSE endpoint
4. Result: one Alpaca connection per symbol regardless of user count, instant "reconnection" (Supabase Realtime handles it), and no serverless timeout issues

This would replace the SSE endpoint entirely with Supabase's client-side Realtime library (already a dependency via `@supabase/supabase-js`). The tradeoff is that it requires an always-on compute component, which adds cost and breaks the "fully serverless, $0/month" constraint. Evaluate this when the project outgrows the 1:1 SSE approach.

---

## Portfolio Writeup Talking Points

Key architectural decisions to highlight in a project writeup:

1. **Agentic AI architecture** — Gemini autonomously calls financial data tools during conversation rather than relying on pre-packed context, demonstrating multi-step tool use with the Vercel AI SDK
2. **Model routing** — Flash for cheap/fast explanations, Pro for complex reasoning, showing cost-optimization awareness
3. **SSE over Socket.io** — chose SSE for unidirectional server-to-client streaming, reducing client bundle by ~50KB and matching the data flow semantics (no bidirectional communication needed). Includes auto-reconnection with Last-Event-ID for Vercel's 60s function timeout.
4. **Zustand + TanStack Query** — separated client state (Zustand) from server state (TanStack Query) for proper cache management, optimistic updates, and elimination of waterfall fetches
5. **Two-layer AI response caching** — Supabase table as persistent cross-user cache (1h TTL) + TanStack Query as client-side per-user cache with stale-while-revalidate. Reduces Gemini API costs to near-zero for common queries.
6. **Zod validation at system boundaries** — all API inputs, environment variables, and external API responses validated with Zod, generating TypeScript types from schemas (single source of truth)
7. **Biome over ESLint** — 100x faster linting and formatting in a single tool, demonstrating awareness of modern Rust-based JS tooling
8. **Provider abstraction** — Vercel AI SDK enables switching between Gemini, Claude, and GPT with a one-line change, showing provider-agnostic design
9. **Security hardening** — moved API keys server-side, enabled strict TypeScript builds, added input validation (contrast with the pre-rewrite state)
10. **Fully serverless architecture** — zero always-on compute. Vercel serverless functions + cron, Supabase managed database, Gemini API pay-per-token. $0/month infrastructure cost.
11. **CI/CD pipeline** — GitHub Actions runs lint, type check, unit tests, and build on every push. PRs get bundle size diff comments, Lighthouse performance scores, and Playwright E2E tests against Vercel preview deployments. Branch protection enforces all checks pass before merge. Renovate keeps dependencies current with automated PRs.
