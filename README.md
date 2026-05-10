# Indus - AI-Powered Financial Intelligence Platform

https://github.com/user-attachments/assets/82d2c5de-a971-4c8b-8481-fa68fcffc9e4

Indus is an intelligent financial analysis platform that provides comprehensive stock market data, real-time charts, and AI-powered insights to help investors make informed decisions. Built with Next.js, TypeScript, Socket.io, Alpaca API, Yahoo Finance, Google Gemini, and TradingView.

## Prerequisites

- [Bun](https://bun.sh/) v1.0 or later
- A [Supabase](https://supabase.com/) project (free tier works)
- An [Alpaca](https://alpaca.markets/) account (paper trading is fine)
- A [Google AI Studio](https://aistudio.google.com/) API key (for Gemini)

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/vicdenz/indus.git
cd indus
```

### 2. Install dependencies

```bash
bun install
```

### 3. Set up environment variables

Copy the example env file and fill in your keys:

```bash
cp .env.example .env.local
```

Edit `.env.local` with your credentials:

| Variable | Where to get it |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase dashboard > Project Settings > API |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase dashboard > Project Settings > API |
| `ALPACA_API_KEY` | Alpaca dashboard > Paper Trading > API Keys |
| `ALPACA_SECRET_KEY` | Alpaca dashboard > Paper Trading > API Keys |
| `ALPACA_IS_PAPER` | Set to `true` for paper trading (recommended) |
| `GEMINI_API_KEY` | Google AI Studio > Get API key |

### 4. Set up Supabase tables

In your Supabase SQL Editor, run:

```sql
create table favorites (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users not null,
  symbol text not null,
  created_at timestamptz default now(),
  unique(user_id, symbol)
);

create table reports (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users not null,
  symbol text not null,
  company_name text,
  status text default 'pending',
  report_content text,
  summary text,
  created_at timestamptz default now()
);

alter table favorites enable row level security;
alter table reports enable row level security;

create policy "Users can manage their own favorites"
  on favorites for all using (auth.uid() = user_id);

create policy "Users can manage their own reports"
  on reports for all using (auth.uid() = user_id);
```

### 5. Run the development server

```bash
bun run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

## Available Scripts

| Command | Description |
|---|---|
| `bun run dev` | Start the development server |
| `bun run build` | Create a production build |
| `bun start` | Run the production server |
| `bun run lint` | Run Biome lint checks |
| `bun run lint:fix` | Auto-fix lint issues |
| `bun run format` | Format code with Biome |
| `bun test` | Run unit tests (Vitest) |
| `bun run test:watch` | Run tests in watch mode |

## Features

### Comprehensive Financial Analytics

- **Real-time Stock Data** - Live prices, market data, and financial metrics via Yahoo Finance and Alpaca APIs
- **Interactive Charts** - Professional trading charts powered by TradingView's Lightweight Charts
- **50+ Financial Metrics** - Valuation ratios, margins, growth rates, financial health indicators, and more
- **Cryptocurrency Support** - Track popular cryptocurrencies alongside traditional stocks

### AI-Powered Intelligence

- **Context-Aware Explanations** - Hover over any metric to get intelligent explanations powered by Google's Gemini AI
- **Interactive Chat** - Click on any metric to open an AI chat panel for deeper analysis
- **Educational Content** - Built-in definitions and explanations for all financial terms
- **Streaming Responses** - Real-time AI responses with proper context understanding

### Advanced Search & Discovery

- **Universal Search** - Find any publicly traded company or cryptocurrency
- **Categorized Browsing** - Explore stocks by sector (Tech, Finance, Healthcare, Energy, etc.)
- **Trending Stocks** - Discover trending and popular investments
- **Favorites System** - Save and track your favorite companies

### User Management

- **Supabase Authentication** - Secure login with email/password or Google OAuth
- **Personal Dashboard** - Customized experience with saved favorites
- **Session Management** - Persistent login state across devices

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Next.js 15 (App Router) + React 19 |
| Language | TypeScript 5 (strict mode) |
| Styling | Tailwind CSS v4 + shadcn/ui (Radix) + Lucide icons + next-themes |
| Auth & DB | Supabase (PostgreSQL + Auth with Google OAuth) |
| AI | Google Gemini via `@google/generative-ai` |
| Real-time | Socket.io (relays Alpaca WebSocket bars to clients) |
| Charts | TradingView Lightweight Charts v5 |
| Financial Data | Alpaca Trade API + Yahoo Finance 2 |
| Validation | Zod (API inputs + environment variables) |
| Linting | Biome |
| Testing | Vitest |
| Deployment | Vercel |

## License

This project is licensed under the MIT License - see the LICENSE file for details.
