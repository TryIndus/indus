# Indus - AI-Powered Financial Dashboard

## What This Project Is

Indus is a full-stack financial intelligence platform where users authenticate, browse and search stocks/crypto, view 50+ financial metrics per company, stream real-time price data, interact with an AI financial analyst agent (multi-step tool use), and generate AI-powered research reports. It serves as a portfolio showcase of modern full-stack system design.

---

## Behavioral Rules

These apply to every task, every message, regardless of context.

### Commits

- Always make small, incremental commits. Each logical change gets its own commit.
- One-sentence commit messages. Describe what changed, not why (the PR does that).
- Never batch multiple unrelated changes into a single commit.
- Never amend a commit unless explicitly asked.
- Always commit after completing a discrete piece of work — don't accumulate uncommitted changes.
- At the end of every response, if there are any uncommitted changes, commit them following these same rules.
- Never mention AI, Claude, or any AI tool in commit messages, PR titles, PR descriptions, or co-author tags. All commits and PRs must read as if written by a human developer.

### Code Quality

- Run `bun run build` after any code change to verify zero TypeScript and zero lint errors before considering the work done.
- Run `bun test` after any change that touches logic, schemas, or utilities.
- Preserve `serverExternalPackages: ['yahoo-finance2']` in `next.config.ts` — removing it breaks the build.
- Preserve the `punycode` webpack warning suppression in `next.config.ts` until the upstream dependency is resolved.
- Shared Zod schemas live in `lib/schemas/api.ts` so they can be imported by both routes and tests.
- Test files live in `__tests__/` mirroring the source structure.

### Pull Requests

- Open a PR after each phase is complete, but only when the user explicitly asks for it.
- PRs go from `dev/revamp` to `main`.

### Branch Strategy

- All work happens on `dev/revamp`. Do not merge to `main` until the full rewrite is complete.
- `main` remains the stable production deployment.

### Documentation Sync

- Any change to `CLAUDE.md` must also be reflected in `AGENTS.md`. Keep both files in sync.

---

## Current Tech Stack

- **Runtime**: Bun
- **Framework**: Next.js 15.4.10 (App Router) + React 19.1.0
- **Language**: TypeScript 5 (strict mode)
- **Styling**: Tailwind CSS v4 + shadcn/ui (Radix primitives) + Lucide icons + next-themes
- **Auth & DB**: Supabase (PostgreSQL + Auth with Google OAuth + email/password)
- **Real-time**: SSE via Next.js Route Handlers (streams Alpaca WebSocket bars to clients)
- **Charts**: TradingView Lightweight Charts v5
- **AI**: Google Gemini 2.5 Flash (`@google/generative-ai`) — manual SSE streaming, no tool use
- **Financial Data**: Alpaca Trade API (real-time + historical bars), Yahoo Finance 2 (fundamentals)
- **State**: Zustand for client state + TanStack Query for async/server state
- **Validation**: Zod (API inputs + environment variables)
- **Testing**: Vitest
- **Linting**: Biome
- **Date utils**: date-fns v4
- **Deployment**: Vercel Hobby

## Key Files

- `app/layout.tsx` — Root layout with AppProviders > ConditionalLayout
- `components/AppProviders.tsx` — TanStack Query, theme, and auth session bootstrap provider
- `middleware.ts` — Supabase auth, protects /dashboard, /company, /search, /crypto, /reports, /settings
- `app/api/stream/[symbol]/route.ts` — SSE endpoint for live stock and crypto bars
- `lib/realtime/alpaca-stream.ts` — Shared Alpaca stream normalization and SSE helpers
- `lib/ai/geminiClient.ts` — Gemini API wrapper
- `lib/prompts.ts` — Prompt construction for batch explain
- `lib/system-prompts.ts` — System prompts for AI
- `lib/schemas/api.ts` — Shared Zod schemas for all API routes and env validation
- `lib/env.ts` — Validated environment variables (imports schemas from `lib/schemas/api.ts`)
- `lib/stores/auth-store.ts` — Zustand auth/session state and sign out
- `lib/stores/favorites-store.ts` — Zustand favorites state with TanStack Query mutations
- `components/PriceChart.tsx` — Shared TradingView chart with EventSource live updates
- `components/StockChart.tsx` / `CryptoChart.tsx` — Stock/crypto chart wrappers
- `next.config.ts` — Next.js config with `serverExternalPackages: ['yahoo-finance2']`, punycode warning suppression

## Environment Variables

- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (public — required by Supabase client)
- `ALPACA_API_KEY`, `ALPACA_SECRET_KEY`, `ALPACA_IS_PAPER` (server-only)
- `GEMINI_API_KEY` (server-only)
- `NEXT_PUBLIC_VERCEL_URL` (optional)
- All validated at startup via Zod in `lib/env.ts`

## Database Tables (Supabase)

- `favorites` (user_id, symbol, created_at)
- `reports` (id, user_id, symbol, company_name, status, report_content, summary, created_at)

Schema migrations are tracked in `supabase/migrations/` and numbered sequentially. Run them manually in the Supabase SQL Editor when setting up a new project.

## Revamp Plan

The detailed rewrite plan (phases, architecture, verification checklists) lives in [`REVAMP_PLAN.md`](./REVAMP_PLAN.md).
