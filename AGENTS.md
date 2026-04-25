# Agents Guide

> Instructions and context for AI agents working on this codebase.

## Project Overview

**Indus** is a full-stack financial intelligence platform built with Next.js 15 (App Router), React 19, TypeScript 5, and Supabase. Users authenticate, browse stocks and crypto, view 50+ financial metrics, stream real-time price data via SSE, interact with an agentic AI financial analyst (Claude via Vercel AI SDK), and generate AI-powered research reports.

Deployed on **Vercel Hobby** (free tier). Database and auth handled by **Supabase** (PostgreSQL + Auth).

## Tech Stack

| Layer | Technology |
|---|---|
| Runtime | Node.js + pnpm |
| Framework | Next.js 15 (App Router) + React 19 |
| Language | TypeScript 5 (strict mode) |
| Styling | Tailwind CSS v4 + shadcn/ui (Radix) + Lucide icons + next-themes |
| Auth & DB | Supabase (PostgreSQL + Auth + Realtime) |
| AI | Vercel AI SDK v6 + `@ai-sdk/anthropic` (Claude Sonnet 4.6 / Haiku 4.5) |
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
  api/              # Next.js API route handlers
  auth/             # Authentication pages
  company/[symbol]/ # Dynamic company detail pages
  crypto/           # Cryptocurrency pages
  dashboard/        # Main dashboard
  reports/          # AI-generated research reports
  search/           # Stock search
  settings/         # User settings
  help/             # Help documentation
  layout.tsx        # Root layout
  globals.css       # Global styles + Tailwind theme
components/
  ui/               # shadcn/ui primitives
  chat/             # AI chat interface components
  *.tsx             # Feature components (charts, tables, favorites)
hooks/              # Custom React hooks
lib/
  ai/               # AI client and prompts
  context/          # React Context providers (legacy, migrating to Zustand)
  server/           # Server-side services
  supabase/         # Supabase client initialization
  types.ts          # Shared TypeScript types
  utils.ts          # Utility functions
  metric-definitions.ts # Financial metric definitions
middleware.ts       # Supabase auth session refresh + route protection
```

## Key Architectural Patterns

### API Routes
All external API calls (Alpaca, Yahoo Finance) go through server-side Next.js route handlers. No API keys are exposed to the client.

### AI Agent System
The AI chat uses Vercel AI SDK's `streamText()` with tool definitions. Claude autonomously decides which tools to call (fetch stock prices, get financial metrics, compare companies) and synthesizes results. Model routing: Haiku 4.5 for quick explanations, Sonnet 4.6 for multi-turn chat and report generation.

### State Management
- **Zustand** for client-only state (auth session, favorites, UI preferences)
- **TanStack Query** for all server data (stock data, reports, historical bars) with caching and revalidation

### Real-time Data
Server-side route handlers maintain Alpaca WebSocket connections and relay bar data to clients via Server-Sent Events (SSE). Clients use the native `EventSource` API.

### Validation
Zod schemas validate all API route inputs, environment variables, and external API responses. Types are inferred from schemas (single source of truth).

## Environment Variables

| Variable | Visibility | Purpose |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Public | Supabase instance URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Public | Supabase anonymous key |
| `ALPACA_API_KEY` | Server-only | Alpaca Trade API key |
| `ALPACA_SECRET_KEY` | Server-only | Alpaca secret key |
| `ALPACA_IS_PAPER` | Server-only | Paper trading flag |
| `ANTHROPIC_API_KEY` | Server-only | Claude API key |
| `NEXT_PUBLIC_VERCEL_URL` | Public | Vercel deployment URL |

All environment variables are validated at startup via Zod in `lib/env.ts`.

## Database

**Supabase PostgreSQL** with the following tables:

- `favorites` — user_id, symbol, created_at
- `reports` — id, user_id, symbol, company_name, status, report_content, summary, created_at

Auth tables are managed by Supabase Auth (email/password + Google OAuth).

## Development Guidelines

### Code Style
- Biome handles linting and formatting. Run `pnpm check` before committing.
- TypeScript strict mode is enabled. Do not add `@ts-ignore` or `any` without justification.
- No commented-out code. No `console.log` in committed code (use structured logging if needed).

### Testing
- Unit/integration tests: Vitest. Run with `pnpm test`.
- E2E tests: Playwright. Run with `pnpm test:e2e`.
- Test API route handlers and Zod schemas. Test auth flows and chart rendering E2E.

### Commits
- One logical change per commit.
- Commit messages: imperative mood, concise, explain the why if non-obvious.

### Security
- Never expose API keys to the client. Only `NEXT_PUBLIC_*` variables are client-visible.
- Validate all API inputs with Zod at the route handler boundary.
- Use parameterized queries (Supabase client handles this).

## Active Work

This codebase is undergoing a modernization rewrite. See `CLAUDE.md` for the full rewrite plan, phased rollout, and architectural decisions. The rewrite is tracked on the `dev/revamp` branch.

### Rewrite Phases
1. **Foundation** — pnpm, Biome, Zod, security fixes, strict TS builds, next-themes
2. **State & Data Fetching** — TanStack Query, Zustand, remove React Context
3. **AI Modernization** — Vercel AI SDK, Claude, agentic tool use, `useChat()`
4. **Real-time** — SSE replaces Socket.io
5. **Testing** — Vitest + Playwright
6. **Polish** — Bundle audit, performance, security audit
