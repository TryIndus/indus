# Indus Repository Guide

## Mission

Indus is a financial intelligence platform for authenticated stock and cryptocurrency research, live market charts, model-assisted explanations and chat, and generated research reports. Treat it as a production portfolio project: changes should demonstrate sound boundaries, security, reliability, and operational judgment.

## Sources of Truth

- The checked-in code and migrations describe the system that exists today.
- [`docs/QUALITY.md`](./docs/QUALITY.md) defines the local verification contract.
- [`docs/architecture/application-platform.md`](./docs/architecture/application-platform.md), [`docs/architecture/market-data.md`](./docs/architecture/market-data.md), and [`docs/architecture/distributed-research-workflows.md`](./docs/architecture/distributed-research-workflows.md) define the implemented service boundaries.
- Runbooks under `docs/runbooks/` define deployment, recovery, rollback, and local operation.
- `AGENTS.md` is the canonical agent context. `CLAUDE.md` must remain a relative symlink to it.

## Working Rules

### Scope and Safety

- Inspect the relevant implementation, tests, migrations, and documentation before editing.
- Preserve unrelated user changes in a dirty worktree.
- Make the smallest coherent change that fully addresses the request.
- Do not combine feature work, infrastructure work, dependency upgrades, and unrelated cleanup in one PR.
- Treat `main` as production. Merges may trigger configured deployment integrations, so every merge is a release; do not push directly to it.
- Do not mutate production data, cloud resources, secrets, or external services without explicit authorization.
- Prefer forward-only database fixes after a migration has reached any shared environment.
- Never expose credentials, tokens, private prompts, or full provider payloads in logs, tests, commits, or responses.

### Branches, Commits, and Pull Requests

- Branch from the current `origin/main` using a short-lived topic branch.
- Commit substantial work incrementally by logical concern; do not accumulate a large mixed diff.
- Use one-sentence commit messages that describe what changed.
- Stage minor amendments without a standalone commit unless the user requested a completed PR or push.
- Never amend, rewrite, or force-push history unless explicitly requested.
- Do not include coding-assistant attribution, co-author tags, or generated-by language in commits or PR metadata. Product terms such as Gemini or model-assisted features are allowed when technically relevant.
- Open a PR only when explicitly requested. Standalone and bottom-of-stack PRs target `main`; in an explicitly approved stack, each child PR targets its immediate parent and declares the dependency. State scope, verification, migration impact, rollback, and deferred work.

### Verification

Run checks in proportion to the changed boundary:

| Change | Required verification |
|---|---|
| Documentation or agent context only | `git diff --check`; validate paths, links, and symlinks |
| Legacy Next.js code or configuration | `bun run lint`, `bun run typecheck`, `bun run build`, and `bun run test` for logic changes |
| React/Vite application | Run lint, typecheck, tests, and build from `apps/web`; add relevant Playwright suites for browser-visible behavior |
| Rails API, schema, or providers | Run RSpec, RuboCop, Brakeman, and Bundler Audit with the pinned containerized Ruby toolchain |
| Rust market-data service | `bash scripts/verify-market-data.sh` |
| OpenAPI or Protobuf contract | Run contract lint, compatibility, and deterministic generation checks; commit regenerated clients |
| Distributed or cross-service boundary | `bun run test:phase3` |
| Terraform, Helm, container, or GitOps change | Run the equivalent checks from the AWS foundation workflow without applying infrastructure |

- Add tests for new behavior and existing behavior changed by the patch.
- Test failure paths, authorization boundaries, retries, and malformed inputs when relevant.
- Do not weaken assertions, coverage thresholds, lint rules, or compiler settings to make a change pass.
- Report commands that could not run and the exact reason.

## Current Architecture

The primary platform consists of:

- A React 19 and Vite single-page application in `apps/web`, with TanStack Router, TanStack Query, Zod, and authenticated SSE.
- A Ruby 3.4 and Rails 8 API in `apps/platform-api`, with PostgreSQL, Pundit authorization, idempotent writes, quotas, audit records, and a transactional outbox.
- A Rust market-data service in `services/market-data`, using Tokio and Axum for Alpaca ingestion, PostgreSQL persistence, Kafka delivery, and authenticated SSE fanout.
- Kafka for durable domain-event delivery and Temporal for recoverable multi-step report workflows.
- Google Gemini behind the provider-neutral Rails `ModelGateway`; prompts, evidence, schemas, quotas, and normalized failures remain application-owned.
- Amazon Cognito browser authentication and Cognito-only Rails access-token verification, plus Aurora PostgreSQL, ElastiCache, MSK, S3, EKS, Argo CD, Terraform, Helm, AWS Secrets Manager, and workload identity definitions for AWS.
- OpenAPI and Protobuf contracts under `contracts/`, with generated clients checked for deterministic regeneration.

The root Next.js and Supabase application remains in the repository as a bounded rollback path. Do not add new product behavior to it unless the requested work explicitly concerns rollback compatibility or legacy removal.

## Current Implementation Invariants

### Application and Provider Boundaries

- Keep credentials server-only and source deployed secrets through Secrets Manager and workload identity. Browser configuration may contain only explicitly public endpoints and identity-client values.
- Treat `contracts/openapi/` as the HTTP source of truth and `contracts/protobuf/` as the event source of truth. Regenerate committed clients after contract changes.
- Authenticate every protected Rails request, then authorize tenant-owned resources through Pundit scopes before lookup.
- Require idempotency keys for retried mutations and commit domain state, audit records, and outbox events atomically.
- Keep prompts, model selection, evidence allowlists, structured output validation, timeouts, and quotas behind `ModelGateway`; provider payloads must not escape the adapter.
- Fail closed when identity verification, authorization, quota enforcement, or required evidence is unavailable.

### Database

- Add Rails schema changes as sequential files in `apps/platform-api/db/migrate/` and market-data changes in `services/market-data/migrations/`; never edit an applied migration.
- Enforce durable invariants with PostgreSQL constraints and application authorization with explicit tenant scoping.
- Add or update database-backed tests for migrations, constraints, idempotency, quotas, outbox behavior, and tenant isolation.
- Preflight existing data before validating a new constraint in a shared environment.
- Apply migrations through the service's established deployment process, then verify migration history and resulting database objects.
- Use forward-only corrections after a migration reaches a shared environment.

### Real-Time Data

- Preserve the Rust Alpaca-to-Kafka/PostgreSQL/SSE boundary; browsers must not receive Alpaca credentials.
- Preserve deterministic event IDs, transactional Kafka publication, duplicate-safe consumption, rejected-event storage, and bounded backpressure.
- Preserve authenticated stream limits, replay cursors, gap and stale events, reconnect behavior, and disconnect cleanup.
- Test both stock and slash-delimited cryptocurrency symbols when changing stream handling.

### Legacy Next.js Configuration

- Preserve `serverExternalPackages: ["yahoo-finance2"]` in `next.config.ts`.
- Preserve the `punycode` webpack warning suppression until the upstream dependency is removed.
- Do not disable TypeScript, lint, build, or runtime validation failures.

## Repository Map

- `apps/web/` — primary React/Vite browser application.
- `apps/platform-api/` — Rails API, domain state, provider gateways, event publication, and report workflows.
- `services/market-data/` — Rust ingestion, storage, Kafka, and SSE service.
- `contracts/` — versioned OpenAPI and Protobuf sources plus generated clients.
- `infra/` — Terraform, Helm, GitOps, workload images, and AWS deployment definitions.
- `app/`, `components/`, `hooks/`, `lib/`, `__tests__/`, `e2e/`, and `supabase/` — legacy Next.js and Supabase rollback implementation.
- `scripts/` — isolated local verification orchestration.
- `docs/` — durable architecture and operational documentation.

## Documentation Standards

- Keep `README.md` focused on stable setup, commands, architecture orientation, and links to durable documents.
- Keep detailed documentation under `docs/`; retain `README.md` and repository control files at the root.
- Remove temporary progress narration, speculative claims, stale issue lists, and duplicated instructions.
- Document decisions, invariants, failure behavior, operations, and rollback information that will remain useful after the current task.
- Update the relevant architecture document and runbook when a boundary or operational procedure changes.
- Update only `AGENTS.md` for agent guidance; verify that `CLAUDE.md` still resolves to it.

## Key Current Files

- `apps/platform-api/app/services/model_gateway.rb` — model task, prompt, evidence, quota, and result boundary.
- `apps/platform-api/app/services/events/` — Kafka envelopes, publication, replay, and idempotent consumption.
- `apps/platform-api/app/services/reports/` — Temporal workflow activities and artifact persistence.
- `apps/web/src/lib/api.ts` — authenticated, runtime-validated Rails API client.
- `apps/web/src/lib/market-stream.ts` — authenticated SSE, replay, and reconnect client.
- `services/market-data/src/` — ingestion, persistence, Kafka, authentication, and streaming implementation.
- `infra/terraform/` — AWS stateful and platform infrastructure.
- `infra/helm/` and `infra/gitops/` — workload and reconciliation definitions.
- `docs/architecture/` — application, market-data, and workflow boundaries.
- `docs/runbooks/` — deployment, recovery, local operation, and rollback procedures.
