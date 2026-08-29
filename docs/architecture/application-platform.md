# Application Platform Architecture

## Status

Phase 2 introduces the replacement application platform as a dormant, independently verified system. The root Next.js application and its Supabase deployment remain the production path until the Phase 4 cutover. Nothing in `apps/` is imported by, bundled with, or required to deploy the current application.

## Boundaries

### React web application

`apps/web` owns presentation, navigation, accessibility, and browser session handling. It uses runtime-validating Zod wire schemas aligned with OpenAPI and a small API client to call Rails. The independently generated TypeScript client remains a deterministic contract artifact, but is not compiled into the SPA because its generated implementation conflicts with the application's stricter compiler rules. The browser contains no business authorization rules, provider credentials, Gemini configuration, or direct database access. Live market data is represented by an interface that Phase 3 will connect to the Rust streaming service.

### Rails platform API

`apps/platform-api` owns users, favorites, portfolios, positions, reports, audit records, idempotency, quotas, and the transactional outbox. Controllers authenticate a caller, policies authorize the requested resource, and database constraints preserve durable invariants. Tenant-owned queries are scoped before lookup so an identifier from another tenant is indistinguishable from a missing resource.

Rails also owns two provider boundaries:

- The fundamentals interface preserves current Yahoo Finance behavior behind normalized application types.
- `ModelGateway` exposes provider-neutral tasks, prompt versions, structured results, usage, and errors. The Gemini adapter is the only initial model implementation and receives its token only from server configuration.

### Contracts

`contracts/openapi` is the source of truth for browser-facing HTTP behavior. `contracts/protobuf` contains versioned event envelopes and domain events used by later Kafka and Temporal integrations. Generated clients are reproducible outputs; CI rejects stale generated files and incompatible contract changes.

## Authentication transition

Authentication is an explicit adapter boundary rather than controller-specific token parsing. During the compatibility period, Rails validates a bearer token through the configured Supabase authentication endpoint and maps its immutable subject to an application user. The dormant Cognito adapter validates issuer, audience, signature, and expiry through JWKS but cannot become active until Phase 4 provisions and verifies the user pool.

Test-only authentication is available only in the Rails test environment. Development and production fail closed when their configured verifier is unavailable or ambiguous. Authorization remains a separate Pundit decision after authentication.

## Write reliability

Retried writes require an `Idempotency-Key`. Rails stores the key, caller, request fingerprint, and completed response. Reusing a key with a different payload is rejected. Domain events are inserted into the outbox in the same database transaction as the owning record; Phase 3 publishes them to Kafka and records delivery without introducing a database/broker dual write.

Audit events record actor, action, resource, outcome, correlation ID, and bounded metadata. Tokens, credentials, full prompts, and provider payloads are never audit fields.

## Model gateway

The gateway selects a server-configured model by task. Prompt templates, structured output schemas, server-side evidence allowlists, timeouts, and quotas are application-owned and versioned independently from the Gemini adapter. Citations must exactly match one of the bounded evidence records supplied by the server; provider-specific response objects never leave the adapter. Normalized errors distinguish authentication, quota, timeout, safety rejection, malformed output, and upstream availability so callers can apply bounded retry behavior.

Live model calls are not part of deterministic CI. Fixture-backed contract tests and golden evaluations cover request construction, output validation, safety failures, timeouts, and malformed responses. Phase 4 injects the personal Gemini token from Secrets Manager without rebuilding an image.

## Local topology

The default Compose profile starts PostgreSQL and Redis on loopback-only ports with isolated named volumes. The optional `application` profile builds Rails and React containers and exposes them only on loopback. Local credentials are disposable development values and must never be reused outside this Compose project.

Phase 3 extends this topology with Kafka, Temporal, and the Rust service. Phase 4 replaces local adapters with managed AWS services without changing application contracts.

## Rollback

Before Phase 4, rollback means stopping the dormant application profile and removing its disposable data volumes if necessary. The production Next.js/Supabase path is unaffected. Contract or schema changes use forward fixes once shared; never restore a database by checking out an older migration.
