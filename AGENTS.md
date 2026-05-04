# Agents Guide

> Instructions and context for AI agents working on this codebase.

## Project Overview

**Indus** is a full-stack financial intelligence platform built with Next.js 15 (App Router), React 19, TypeScript 5, and Supabase. Users authenticate, browse stocks and crypto, view 50+ financial metrics per company, stream real-time price data, interact with an AI financial analyst, and generate AI-powered research reports.

Deployed on **Vercel Hobby** (free tier). Database and auth handled by **Supabase** (PostgreSQL + Auth).

## Rewrite Status

The codebase is undergoing a **6-phase modernization rewrite** on the `dev/revamp` branch. **No phases have been started yet** — the codebase is entirely in its pre-rewrite state. See `CLAUDE.md` for the full rewrite plan, phased rollout, architectural decisions, and verification checklists.

**Do not merge `dev/revamp` to `main`** until all 6 phases are complete and verified. The user will create the final PR.

### Rewrite Phases

1. **Foundation** — Bun, Biome, Zod, security fixes, strict TS builds, next-themes
2. **State & Data Fetching** — TanStack Query, Zustand, remove React Context
3. **AI Modernization** — Vercel AI SDK, Gemini 2.5 Pro/Flash, agentic tool use, `useChat()`
4. **Real-time** — SSE replaces Socket.io
5. **Testing & CI/CD** — Vitest, Playwright, GitHub Actions, Renovate
6. **Polish** — Bundle audit, performance, security audit, Supabase keepalive cron

## Current Tech Stack (Pre-Rewrite)

| Layer | Technology |
|---|---|
| Runtime & Package Manager | Node.js (npm) |
| Framework | Next.js 15.4.10 (App Router) + React 19.1.0 |
| Language | TypeScript 5 (strict mode **disabled** — `ignoreBuildErrors: true`) |
| Styling | Tailwind CSS v4 + shadcn/ui (Radix) + Lucide icons + tw-animate-css |
| Auth & DB | Supabase (PostgreSQL + Auth with Google OAuth + email/password) |
| AI | Google Gemini 2.5 Flash (`@google/generative-ai`) — manual SSE streaming, no tool use |
| State | React Context API (AuthContext, FavoritesContext) + manual useEffect/useState fetch patterns |
| Real-time | Socket.io v4.8.1 (Pages Router handler relays Alpaca WebSocket bars) |
| Validation | None |
| Testing | None |
| Linting | ESLint 9 (ignored during builds — `ignoreDuringBuilds: true`) |
| Charts | TradingView Lightweight Charts v5 |
| Financial Data | Alpaca Trade API + Yahoo Finance 2 |
| Date utils | date-fns v4 |
| Deployment | Vercel Hobby |

### Target Tech Stack (Post-Rewrite)

| Layer | Technology |
|---|---|
| Runtime & Package Manager | Bun |
| Framework | Next.js 15 (App Router) + React 19 |
| Language | TypeScript 5 (strict mode) |
| Styling | Tailwind CSS v4 + shadcn/ui (Radix) + Lucide icons + next-themes |
| Auth & DB | Supabase (PostgreSQL + Auth + Realtime) |
| AI | Vercel AI SDK v6 + `@ai-sdk/google` (Gemini 2.5 Pro / Flash) |
| State | Zustand (client) + TanStack Query (server/async) |
| Real-time | SSE via Next.js Route Handlers |
| Validation | Zod |
| Testing | Vitest + Playwright |
| Linting | Biome |
| Charts | TradingView Lightweight Charts v5 |
| Financial Data | Alpaca Trade API + Yahoo Finance 2 |
| Deployment | Vercel Hobby |

## Repository Structure

```
app/
  api/
    alpaca/             # Historical candlestick bars (Alpaca REST)
    batch-explain/      # AI metric explanations (Gemini Flash) → renamed to /api/explain in Phase 3
    context-chat/       # AI chat with pre-packed context (Gemini Flash) → rewritten as /api/chat in Phase 3
    metric-definition/  # Static metric definitions
    reports/            # List reports (GET)
    reports/[id]/       # Get/delete a report (GET/DELETE)
    reports/generate/   # AI report generation (Gemini) → rewritten in Phase 3
    stock-data/         # Financial metrics from Yahoo Finance
  auth/                 # Authentication pages (sign in, sign up)
  auth/auth-code-error/ # OAuth error handling
  auth/callback/        # OAuth callback handler
  company/[symbol]/     # Dynamic company detail pages
  crypto/               # Cryptocurrency pages
  dashboard/            # Main dashboard
  help/                 # Help documentation
  reports/              # AI-generated research reports UI
  search/               # Stock search
  settings/             # User settings
  types/                # Type definitions
  layout.tsx            # Root layout (AuthProvider > FavoritesProvider > ConditionalLayout)
  globals.css           # Global styles + Tailwind theme
components/
  ui/                   # shadcn/ui primitives
  chat/                 # AI chat interface components
  StockChart.tsx        # TradingView stock chart with Socket.io real-time data
  CryptoChart.tsx       # TradingView crypto chart with Socket.io real-time data
  FinancialTable.tsx    # Financial metrics table for stocks
  CryptoFinancialTable.tsx # Financial metrics table for crypto
  Header.tsx            # App header / navigation
  ConditionalLayout.tsx # Layout wrapper (sidebar, header)
  app-sidebar.tsx       # Sidebar navigation
  FavoriteButton.tsx    # Favorite toggle button
  FavoritesSection.tsx  # Favorites list in sidebar/dashboard
  *.tsx                 # Other feature components
hooks/
  use-mobile.ts         # Mobile detection hook
  useExplanation.ts     # AI explanation fetching hook
lib/
  ai/
    geminiClient.ts     # Gemini API wrapper (raw @google/generative-ai) → replaced by Vercel AI SDK in Phase 3
    geminiSystemPrompt.ts # System prompt for Gemini
  context/
    AuthContext.tsx      # Auth state provider (React Context) → replaced by Zustand in Phase 2
    FavoritesContext.tsx # Favorites CRUD (React Context) → replaced by Zustand + TanStack Query in Phase 2
  server/
    alpaca-server.ts    # Server-side Alpaca WebSocket manager → deleted in Phase 4 (replaced by SSE route)
  supabase/
    client.ts           # Supabase browser client
    server.ts           # Supabase server client
  metric-definitions.ts # Financial metric definitions (static data)
  prompts.ts            # Prompt construction for batch explain → adapted for AI SDK in Phase 3
  system-prompts.ts     # System prompts for AI chat → adapted for AI SDK in Phase 3
  types.ts              # Shared TypeScript types
  utils.ts              # Utility functions (cn, formatters)
pages/
  api/socket/index.ts   # Pages Router Socket.io handler → deleted in Phase 4 (replaced by SSE)
middleware.ts           # Supabase auth session refresh + route protection
next.config.ts          # Next.js config (ignoreBuildErrors, ignoreDuringBuilds, serverExternalPackages)
```

## Key Architectural Patterns (Current)

### API Routes

All external API calls (Alpaca, Yahoo Finance) go through server-side Next.js route handlers. **However**, Alpaca API keys are currently exposed as `NEXT_PUBLIC_*` client-side variables — a security vulnerability fixed in Phase 1.

### AI System (Current)

The AI chat uses the raw `@google/generative-ai` SDK with manual SSE streaming. It is **single-turn Q&A** with pre-packed context, not agentic. No tool use, no multi-step reasoning. The `context-chat` route packs all relevant stock data into the prompt before calling Gemini.

Metric explanations (`batch-explain`) are generated per-request with no server-side caching — every request hits the Gemini API even for previously explained metrics. Caching is client-only (localStorage).

### State Management (Current)

- **AuthContext** — React Context provider for auth state (user session, sign out)
- **FavoritesContext** — React Context provider for favorites CRUD (add, remove, sync to Supabase)
- **Manual fetch patterns** — `useEffect` + `useState` for all server data (stock data, reports, historical bars)

### Real-time Data (Current)

Socket.io server runs in the **Pages Router** (`pages/api/socket/index.ts`) while the rest of the app uses App Router — a mixed routing architecture. The server-side `AlpacaWebSocketManager` class (`lib/server/alpaca-server.ts`) maintains Alpaca WebSocket connections and relays bar data to connected Socket.io clients. Both `StockChart.tsx` and `CryptoChart.tsx` consume this via `socket.io-client`.

### Validation (Current)

No input validation on any API route. No environment variable validation. TypeScript errors and ESLint errors are both suppressed during builds.

## Known Issues

- Alpaca API keys exposed as `NEXT_PUBLIC_*` (client-side visible — security vulnerability)
- TypeScript and ESLint errors ignored in builds (`ignoreBuildErrors: true`, `ignoreDuringBuilds: true`)
- No test suite
- `supabase.auth.getUser()` called twice in middleware (lines 33 and 36 of `middleware.ts`)
- Socket.io adds ~50KB to client bundle for unidirectional data flow
- Manual SSE streaming logic in `/api/context-chat` (~190 lines of boilerplate)
- No agent capabilities — AI is single-turn Q&A, not agentic
- No server-side caching for AI explanations
- Socket.io server uses Pages Router while the rest uses App Router — mixed routing
- No React error boundaries or loading states
- `yahoo-finance2` requires `serverExternalPackages` config to avoid bundling issues

## Environment Variables (Current)

| Variable | Visibility | Purpose |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Public | Supabase instance URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Public | Supabase anonymous key |
| `NEXT_PUBLIC_ALPACA_API_KEY` | Public (SECURITY ISSUE) | Alpaca Trade API key |
| `NEXT_PUBLIC_ALPACA_SECRET_KEY` | Public (SECURITY ISSUE) | Alpaca secret key |
| `NEXT_PUBLIC_ALPACA_IS_PAPER` | Public | Paper trading flag |
| `GEMINI_API_KEY` | Server-only | Gemini API key (raw SDK) |
| `NEXT_PUBLIC_VERCEL_URL` | Public | Vercel deployment URL |

No environment variable validation exists. All `process.env` access uses non-null assertions (`!`).

### Post-Rewrite Environment Variables

| Variable | Visibility | Purpose |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Public | Supabase instance URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Public | Supabase anonymous key |
| `ALPACA_API_KEY` | Server-only | Alpaca Trade API key (fixed) |
| `ALPACA_SECRET_KEY` | Server-only | Alpaca secret key (fixed) |
| `ALPACA_IS_PAPER` | Server-only | Paper trading flag |
| `GOOGLE_GENERATIVE_AI_API_KEY` | Server-only | Gemini API key (via Vercel AI SDK) |
| `NEXT_PUBLIC_VERCEL_URL` | Public | Vercel deployment URL |

All validated at startup via Zod in `lib/env.ts`.

## Database (Supabase)

**Supabase PostgreSQL** with the following tables:

### Existing

- `favorites` — user_id, symbol, created_at
- `reports` — id, user_id, symbol, company_name, status, report_content, summary, created_at

### Planned (Phase 3)

- `metric_explanations` — id, symbol, metric, explanation (jsonb), created_at (timestamptz)
  - Unique constraint on (symbol, metric) — upsert on cache refresh
  - Index on created_at for TTL-based cache expiry queries
  - Rows older than 1 hour are treated as stale and refreshed on next request

Auth tables are managed by Supabase Auth (email/password + Google OAuth).

## Development Guidelines

### Code Style

- **Current**: ESLint 9 (ignored during builds). No formatter configured.
- **Post-rewrite**: Biome handles linting and formatting. Run `bun check` before committing.
- TypeScript strict mode will be enabled in Phase 1. Do not add `@ts-ignore` or `any` without justification.
- No commented-out code. No `console.log` in committed code (use structured logging if needed).

### Testing

- **Current**: No tests exist.
- **Post-rewrite**: Unit/integration tests via Vitest (`bun test`). E2E tests via Playwright (`bun test:e2e`). Test API route handlers, Zod schemas, auth flows, and chart rendering.

### Commits

- One logical change per commit.
- Commit messages: imperative mood, concise, explain the why if non-obvious.

### Security

- Never expose API keys to the client. Only `NEXT_PUBLIC_*` variables are client-visible.
- Validate all API inputs with Zod at the route handler boundary (post Phase 1).
- Use parameterized queries (Supabase client handles this).

### Important Constraints

- **Do not touch `pages/` directory until Phase 4.** The Socket.io server must continue working through Phases 1-3.
- **The `@alpacahq/alpaca-trade-api` SDK stays.** Phase 4 only removes Socket.io transport and the WebSocket manager class.
- **`yahoo-finance2` requires `serverExternalPackages`** in `next.config.ts` to avoid bundling issues. Preserve this config during the rewrite.
- **Do not merge to `main`.** All work stays on `dev/revamp`.
- **Small, incremental commits.** Each sub-step gets its own commit.
- **Test after every phase.** See verification checklists in `CLAUDE.md`.
