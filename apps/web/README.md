# Indus Web

The Indus browser application is a React 19 and Vite single-page application.

## Boundaries

- TanStack Router owns browser navigation and rejects unauthenticated protected-route requests before rendering application content.
- Amazon Cognito is the identity boundary. The browser uses the OAuth 2.0 authorization-code flow with PKCE through Cognito's hosted sign-in, stores session state in session storage, refreshes access tokens through the OIDC client, and never receives a client secret.
- `src/lib/api.ts` is the typed Rails JSON boundary. It attaches the current access token, validates responses, supplies idempotency keys for mutations, and returns bounded errors that do not expose upstream payloads. Its Zod schemas follow the OpenAPI wire format and provide runtime validation; direct imports from the generated TypeScript client are deferred until that generator output is compatible with this application's strict TypeScript settings.
- `src/lib/market-stream.ts` opens authenticated SSE connections to the market-data service, validates events, resumes from the last event ID, and exposes reconnecting, stale, and unauthorized states explicitly.
- TanStack Query owns remote server state. Components do not call Rails or market providers directly.

## Local development

Copy `.env.example` to `.env.local` and supply local development values. Then run:

```sh
bun install --frozen-lockfile
bun run dev
```

The Rails API must allow the local Vite origin and validate Cognito access tokens issued to the configured public app client. Local Cognito callback and logout URLs must exactly match the values registered on that client.

## Verification

```sh
bun run lint
bun run typecheck
bun run test
bun run build
bun run test:e2e
```

The browser suite runs once in Chromium against a disposable PostgreSQL and Rails stack. It verifies anonymous fail-closed routing, the local sign-in lifecycle, a persisted favorite lifecycle, the Rails tenant boundary, failure recovery, responsive navigation, serious accessibility rules, and a compiled shell-load budget. External Cognito and market providers are replaced only when Rails runs in `test` with `E2E_TEST_BOUNDARY=true`; the browser, HTTP, authorization, idempotency, persistence, and serialization paths remain real. The stack and its database volume are removed after each run.

The web server is compiled with `VITE_E2E_AUTH=true`; test contexts must additionally opt in through a local-storage marker. Builds without that explicit flag cannot select the test identity adapter, and the unit suite verifies that unconfigured normal builds remain fail-closed.

`src/lib/contract-equivalence.test.ts` reads the committed generated client as text and checks the endpoint paths, methods, idempotency headers, and JSON field mappings used by the Zod adapter. This catches generator drift without compiling generator runtime code under the application's stricter TypeScript policy.

## Failure behavior

Missing identity configuration leaves the application fail-closed at sign-in. Invalid API payloads fail schema validation, non-success responses expose only status and request ID, and unavailable market streaming is a no-op. Search, fundamentals, favorites, portfolios, reports, and settings use the Rails `/v1` contract; their views retain explicit loading, retryable error, empty, and success behavior.
