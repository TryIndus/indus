# Indus Web

The replacement Indus browser application is a React 19 and Vite single-page application. It is introduced alongside the existing Next.js application so migration can proceed route by route without changing the production entrypoint.

## Boundaries

- TanStack Router owns browser navigation and rejects unauthenticated protected-route requests before rendering application content.
- The Supabase adapter is the temporary identity boundary. Only the public project URL and anonymous key enter the browser; provider and service credentials remain server-side.
- `src/lib/api.ts` is the typed Rails JSON boundary. It attaches the current access token, validates responses, and returns bounded errors that do not expose upstream payloads.
- `src/lib/market-stream.ts` defines the Phase 3 live-market interface. The initial implementation deliberately opens no provider connection.
- TanStack Query owns remote server state. Components do not call Rails or market providers directly.

## Local development

Copy `.env.example` to `.env.local` and supply local development values. Then run:

```sh
bun install --frozen-lockfile
bun run dev
```

The Rails API must allow the local Vite origin and validate the Supabase bearer token during the compatibility period.

## Verification

```sh
bun run lint
bun run typecheck
bun run test
bun run build
bun run test:e2e
```

The browser suite verifies anonymous fail-closed routing, serious accessibility rules, responsive browser profiles, and a local shell-load budget. Authenticated end-to-end journeys require a disposable test account and will be added when the Rails compatibility API is available; unit routing tests already exercise authenticated route rendering through the injected identity boundary.

## Failure behavior

Missing identity configuration leaves the application fail-closed at sign-in. Invalid API payloads fail schema validation, non-success responses expose only status and request ID, and unavailable market streaming is a no-op until the Phase 3 adapter is installed.
