# Indus - AI-Powered Financial Dashboard

## What This Project Is

Indus is a full-stack financial intelligence platform where users authenticate, browse and search stocks/crypto, view 50+ financial metrics per company, stream real-time price data, interact with an AI financial analyst agent (multi-step tool use), and generate AI-powered research reports. It serves as a portfolio showcase of modern full-stack system design.

---

## Current Tech Stack (Pre-Rewrite)

- **Runtime**: Node.js (npm)
- **Framework**: Next.js 15.4.10 (App Router) + React 19.1.0
- **Language**: TypeScript 5
- **Styling**: Tailwind CSS v4 + shadcn/ui (Radix primitives) + Lucide icons
- **Auth & DB**: Supabase (PostgreSQL + Auth with Google OAuth + email/password)
- **Real-time**: Socket.io v4.8.1 (relays Alpaca WebSocket bars to clients)
- **Charts**: TradingView Lightweight Charts v5
- **AI**: Google Gemini 2.5 Flash (`@google/generative-ai`) — manual SSE streaming, no tool use, no agent orchestration
- **Financial Data**: Alpaca Trade API (real-time + historical bars), Yahoo Finance 2 (fundamentals)
- **State**: React Context API (AuthContext, FavoritesContext) + manual useEffect/useState fetch patterns
- **Validation**: None
- **Testing**: None
- **Linting**: ESLint 9 (ignored during builds)
- **Date utils**: date-fns v4
- **Deployment**: Vercel Hobby

## Known Issues (Pre-Rewrite)

- Alpaca API keys exposed as `NEXT_PUBLIC_*` (client-side visible — security vulnerability)
- TypeScript and ESLint errors ignored in builds (`ignoreBuildErrors: true`, `ignoreDuringBuilds: true`)
- No test suite
- `supabase.auth.getUser()` called twice in middleware
- Socket.io adds ~50KB to client bundle for a unidirectional data flow
- Manual SSE streaming logic in `/api/context-chat` (~190 lines of boilerplate)
- No input validation on any API route
- No agent capabilities — AI is single-turn Q&A with pre-packed context, not agentic

---

## Target Tech Stack (Post-Rewrite)

### Decisions Made

| Layer | Choice | Rationale |
|---|---|---|
| **Deployment** | Vercel Hobby | Best-in-class Next.js DX, free tier covers portfolio use, SSE supported up to 120s |
| **Framework** | Next.js 15 (App Router) + React 19 | Already modern — clean up usage, properly leverage RSC and Server Actions |
| **Database & Auth** | Supabase (stay) | Already integrated, auth + realtime + PostgreSQL in one. Keep project active to avoid 7-day pause. |
| **AI Provider** | Vercel AI SDK v6 + `@ai-sdk/google` (Gemini) | Replaces manual streaming with `useChat()`/`streamText()`, enables agentic tool use, provider-swappable |
| **AI Models** | Gemini 2.5 Flash (explanations), Gemini 2.5 Pro (chat + reports) | Cost-optimized: Flash for fast/cheap single-turn, Pro for reasoning-heavy multi-turn and long-form |
| **State Management** | Zustand (client state) + TanStack Query (server/async state) | Eliminates Context re-render issues, replaces all manual fetch patterns with caching/revalidation |
| **Real-time** | SSE via Next.js Route Handlers (replace Socket.io) | Unidirectional flow = SSE is the right primitive. Zero client library. Saves ~50KB bundle. |
| **Validation** | Zod | Runtime validation + TypeScript type inference on all API boundaries, env vars, external API responses |
| **Testing** | Vitest (unit/integration) + Playwright (E2E) | Industry standard. Vitest for API routes/utils, Playwright for auth flows and chart rendering. |
| **Linting/Formatting** | Biome (replaces ESLint + Prettier) | Single tool, 10-100x faster, zero config |
| **Charts** | TradingView Lightweight Charts v5 (keep) | Purpose-built for OHLCV candlestick data, ~40KB, no better alternative |
| **Styling** | Tailwind CSS v4 + shadcn/ui + Lucide (keep) + add next-themes | Already best-practice. Add next-themes for proper dark/light toggle instead of hardcoded dark. |
| **Package Manager / Runtime** | Bun (replace npm) | 10-25x faster installs, native TypeScript execution, built-in test runner, drop-in Node.js compatible |
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
| `/api/explain` | POST | Batch metric explanations | Gemini 2.5 Flash via `generateText()` |
| `/api/reports/generate` | POST | Multi-step research report generation | Gemini 2.5 Pro via `generateText()` + tools + `maxSteps` |
| `/api/reports` | GET | List user reports | — |
| `/api/reports/[id]` | GET/DELETE | Get or delete a report | — |
| `/api/stock-data` | GET | Financial metrics from Yahoo Finance | — |
| `/api/alpaca` | POST | Historical candlestick bars | — |
| `/api/stream/[symbol]` | GET | SSE real-time price stream | — |
| `/api/metric-definition` | GET | Static metric definitions | — |

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

**Server side:** A Next.js Route Handler (`/api/stream/[symbol]`) maintains the Alpaca WebSocket connection server-side and writes bar data to a `ReadableStream` as SSE events.

**Client side:** Native `EventSource` API connects to the SSE endpoint. Zero library needed. The `StockChart` and `CryptoChart` components consume events and update the TradingView chart.

**Bundle impact:** Removes `socket.io-client` (~50KB) and `socket.io` (server). Net client bundle reduction: ~50KB.

---

## Rewrite Plan — Priority Order

### Phase 1: Foundation (No Feature Changes)
1. **Switch npm → Bun** — `rm -rf node_modules package-lock.json && bun install`
2. **Replace ESLint with Biome** — remove eslint config, add `biome.json`, run `biome check --fix`
3. **Add Zod** — create `lib/env.ts` with validated env vars, add schemas to all API route inputs
4. **Fix security: move Alpaca keys server-side** — remove `NEXT_PUBLIC_` prefix, all Alpaca calls already go through API routes
5. **Fix middleware** — call `getUser()` once, reuse result
6. **Enable TypeScript strict builds** — remove `ignoreBuildErrors`, fix all type errors
7. **Enable Biome in builds** — remove `ignoreDuringBuilds`, fix all lint errors
8. **Add next-themes** — replace hardcoded `className="dark"` with proper theme provider and toggle

### Phase 2: State & Data Fetching
9. **Add TanStack Query** — create query client provider, convert all `useEffect` fetch patterns to `useQuery`/`useMutation`
10. **Add Zustand** — replace `AuthContext` with `useAuthStore`, replace `FavoritesContext` with `useFavoritesStore`
11. **Remove React Context providers** from layout (replaced by Zustand + TanStack Query)

### Phase 3: AI Modernization
12. **Add Vercel AI SDK + @ai-sdk/google** — `bun add ai @ai-sdk/google`
13. **Rewrite `/api/context-chat`** → `/api/chat` using `streamText()` with Gemini 2.5 Pro + tool definitions
14. **Rewrite `/api/batch-explain`** → `/api/explain` using `generateText()` with Gemini 2.5 Flash + Zod structured output
15. **Rewrite `/api/reports/generate`** using `generateText()` with tools + `maxSteps` for multi-step autonomous research
16. **Update chat frontend** — replace manual SSE parsing with `useChat()` from AI SDK
17. **Remove raw `@google/generative-ai`** and `lib/ai/geminiClient.ts` (replaced by Vercel AI SDK's Google provider)

### Phase 4: Real-time Modernization
18. **Create SSE endpoint** — `/api/stream/[symbol]/route.ts` that maintains Alpaca WS server-side, streams bars via SSE
19. **Update StockChart.tsx** — replace socket.io-client with native `EventSource`
20. **Update CryptoChart.tsx** — same SSE migration
21. **Remove Socket.io** — `bun remove socket.io socket.io-client`, delete `lib/server/alpaca-server.ts`

### Phase 5: Testing
22. **Add Vitest** — config, first tests on API route handlers and Zod schemas
23. **Add Playwright** — config, E2E tests for auth flow, dashboard load, chart rendering, AI chat
24. **Add test scripts** to package.json

### Phase 6: Polish
25. **Audit bundle size** — `next build` analysis, verify Socket.io is gone, check for unused deps
26. **Performance** — add `loading.tsx` skeletons, optimize TanStack Query stale times
27. **Final security audit** — verify no API keys in client bundle, all inputs validated

---

## Key Files (Current)

- `app/layout.tsx` — Root layout with AuthProvider > FavoritesProvider > ConditionalLayout
- `middleware.ts` — Supabase auth, protects /dashboard, /company, /search
- `lib/server/alpaca-server.ts` — Server-side Alpaca WebSocket manager (to be replaced by SSE route)
- `lib/ai/geminiClient.ts` — Gemini API wrapper (to be replaced by Vercel AI SDK)
- `lib/context/AuthContext.tsx` — Auth state provider (to be replaced by Zustand)
- `lib/context/FavoritesContext.tsx` — Favorites CRUD (to be replaced by Zustand + TanStack Query)
- `components/StockChart.tsx` / `CryptoChart.tsx` — TradingView charts with socket.io (to use SSE)

## Environment Variables

### Current
- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_ALPACA_API_KEY`, `NEXT_PUBLIC_ALPACA_SECRET_KEY`, `NEXT_PUBLIC_ALPACA_IS_PAPER` (SECURITY ISSUE)
- `GEMINI_API_KEY` (server-only)
- `NEXT_PUBLIC_VERCEL_URL`

### Post-Rewrite
- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (public — required by Supabase client)
- `ALPACA_API_KEY`, `ALPACA_SECRET_KEY`, `ALPACA_IS_PAPER` (server-only — fixed)
- `GOOGLE_GENERATIVE_AI_API_KEY` (server-only — same Gemini API key, now used via Vercel AI SDK)
- `NEXT_PUBLIC_VERCEL_URL`
- All validated at startup via Zod in `lib/env.ts`

## Database Tables (Supabase)

- `favorites` (user_id, symbol, created_at)
- `reports` (id, user_id, symbol, company_name, status, report_content, summary, created_at)

## Portfolio Writeup Talking Points

Key architectural decisions to highlight in a project writeup:

1. **Agentic AI architecture** — Gemini autonomously calls financial data tools during conversation rather than relying on pre-packed context, demonstrating multi-step tool use with the Vercel AI SDK
2. **Model routing** — Flash for cheap/fast explanations, Pro for complex reasoning, showing cost-optimization awareness
3. **SSE over Socket.io** — chose SSE for unidirectional server-to-client streaming, reducing client bundle by ~50KB and matching the data flow semantics (no bidirectional communication needed)
4. **Zustand + TanStack Query** — separated client state (Zustand) from server state (TanStack Query) for proper cache management, optimistic updates, and elimination of waterfall fetches
5. **Zod validation at system boundaries** — all API inputs, environment variables, and external API responses validated with Zod, generating TypeScript types from schemas (single source of truth)
6. **Biome over ESLint** — 100x faster linting and formatting in a single tool, demonstrating awareness of modern Rust-based JS tooling
7. **Provider abstraction** — Vercel AI SDK enables switching between Gemini, Claude, and GPT with a one-line change, showing provider-agnostic design
8. **Bun runtime** — 10-25x faster installs than npm, native TypeScript execution, modern JavaScript runtime showcasing awareness of next-generation tooling
9. **Security hardening** — moved API keys server-side, enabled strict TypeScript builds, added input validation (contrast with the pre-rewrite state)
