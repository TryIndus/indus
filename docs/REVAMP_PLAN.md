# Indus Enterprise Revamp Plan

## Purpose

Rebuild Indus as a production-grade financial intelligence platform that demonstrates backend engineering, distributed systems, cloud infrastructure, security, observability, and operational discipline. Preserve working product behavior while replacing the current Next.js and Supabase architecture through small, reversible releases.

This is the target architecture, not a description of the current repository. Do not introduce a target technology until its phase is explicitly started.

## Architectural Principles

- Migrate with a strangler pattern; do not attempt a single cutover rewrite.
- Keep service boundaries justified by ownership, scaling, or failure isolation.
- Use Ruby on Rails for product and business logic.
- Use Rust only for concurrency-sensitive market-data processing and streaming.
- Keep Google Gemini as the sole model provider and integrate it directly through Google's supported API and SDK.
- Prefer asynchronous Kafka events between services; use synchronous APIs only when the caller needs an immediate answer.
- Make PostgreSQL the transactional source of truth.
- Treat schemas, migrations, authorization, observability, and rollback procedures as part of every feature.
- Promote the same immutable container images through development, staging, and production.
- Require measurable reliability and security outcomes instead of technology adoption alone.

## Target Stack

| Concern | Target |
|---|---|
| Web application | React, TypeScript, Vite, TanStack Query, TanStack Router, Tailwind CSS |
| Product API | Ruby on Rails in API mode, REST, OpenAPI, Active Record, Pundit |
| Background work | Sidekiq for ordinary jobs; Temporal for durable multi-step workflows |
| Real-time market data | Rust, Tokio, Axum, Serde, rustls |
| Service contracts | OpenAPI for public HTTP APIs; Protocol Buffers and Buf for internal event schemas |
| Transactional data | Amazon Aurora PostgreSQL, RDS Proxy |
| Time-series data | Amazon Timestream for normalized bars and market events |
| Cache and job queues | Amazon ElastiCache for Redis |
| Event backbone | Amazon MSK Serverless with Apache Kafka |
| Models | Google Gemini through the official Google Gen AI SDK/API |
| Object storage | Amazon S3 for generated reports, exports, raw events, and audit artifacts |
| Identity | Amazon Cognito using OAuth 2.0/OIDC, JWTs, MFA, and scoped roles |
| Containers | Amazon EKS, Amazon ECR, Kubernetes, Helm |
| Delivery | GitHub Actions with AWS OIDC, Argo CD, immutable image promotion |
| Infrastructure | Terraform with reusable modules and isolated environment state |
| Edge | Route 53, ACM, CloudFront, AWS WAF, Application Load Balancer |
| Secrets and encryption | AWS Secrets Manager, KMS, IAM roles for service accounts |
| Observability | OpenTelemetry, Amazon Managed Prometheus, Amazon Managed Grafana, CloudWatch, Tempo-compatible tracing |
| Testing | RSpec, Vitest, Playwright, axe-core, Rust tests, property tests, Testcontainers, contract tests, k6 |
| Supply-chain security | Dependabot, Trivy, SBOM generation, image signing and verification |

Ruby on Rails replaces the previously proposed Go platform API. Adding both Rails and Go would create overlapping backend ownership without a defensible operational benefit.

## System Boundaries

### React Web Application

- Serves the authenticated dashboard, search, company, crypto, report, portfolio, and settings experiences.
- Uses generated API clients from the Rails OpenAPI contract.
- Uses TanStack Query for remote state and a small local store only for ephemeral UI state.
- Connects directly to the Rust streaming endpoint for live market updates.
- Builds to static assets stored in S3 and distributed through CloudFront.
- Contains no provider credentials or business authorization rules.

### Rails Platform API

- Owns users' application profiles, favorites, portfolios, reports, permissions, and audit records.
- Validates Cognito JWTs and applies resource authorization with Pundit.
- Owns the public REST API and publishes its OpenAPI contract.
- Uses Active Record migrations and database constraints for persistent invariants.
- Coordinates normal asynchronous work with Sidekiq.
- Starts and observes durable report workflows through Temporal.
- Publishes domain events through an outbox table to avoid database/Kafka dual-write loss.
- Does not proxy high-volume market streams through Rails.

### Rust Market Data Service

- Maintains upstream Alpaca WebSocket connections and bounded REST backfills.
- Normalizes provider payloads into versioned internal events.
- Publishes normalized events to Kafka and persists time-series data asynchronously.
- Fans live updates out to browsers through authenticated SSE endpoints.
- Implements backpressure, reconnection with jitter, heartbeat monitoring, stale-feed detection, and graceful shutdown.
- Exposes health, readiness, metrics, and trace endpoints.
- Does not own users, portfolios, reports, or authorization policy.

### Research Workflow

- Temporal owns the report workflow state, retries, deadlines, cancellation, and recovery.
- Rails activities load authorized portfolio and company context.
- Market-data activities request bounded snapshots rather than opening live streams.
- Gemini tool calls use allowlisted, schema-validated tools and server-controlled instructions.
- Generated claims retain source metadata and an as-of timestamp.
- Final report artifacts are stored in S3; metadata and lifecycle state remain in Aurora PostgreSQL.
- Gemini model names, limits, and safety settings are server configuration, never browser input.

### Event Backbone

Initial topics:

- `market.bars.v1`
- `market.quotes.v1`
- `reports.lifecycle.v1`
- `portfolios.activity.v1`
- `audit.security.v1`

Every event includes a schema version, event ID, producer, occurred-at timestamp, correlation ID, and idempotency key. Consumers must tolerate duplicates and reject unsupported schema versions explicitly.

## Data Architecture

### Aurora PostgreSQL

Own transactional tables such as users, portfolios, positions, favorites, reports, report sources, workflow references, audit events, idempotency keys, and the transactional outbox. Enforce foreign keys, check constraints, indexes, ownership boundaries, and migration rollback or forward-fix procedures.

### Amazon Timestream

Store normalized quotes, bars, feed-health measurements, and derived market aggregates. Define retention separately for memory and magnetic storage. Transactional application state must never depend solely on Timestream.

### Redis

Use separate logical concerns or clusters for caching, rate limiting, and Sidekiq. Every cache entry requires an owner, TTL, invalidation rule, and failure behavior. Redis is not a source of truth.

### Amazon S3

Store immutable report artifacts, data exports, raw ingestion samples used for replay, and compliance evidence. Enable encryption, versioning, lifecycle rules, restricted bucket policies, and access logging.

## API and Security Standards

- Version public endpoints under `/v1` and publish OpenAPI documentation.
- Use cursor pagination, idempotency keys for retried writes, bounded request bodies, and consistent error envelopes.
- Authenticate at the edge and authorize every resource in Rails; authentication alone is insufficient.
- Keep provider keys in Secrets Manager and expose them only to the owning workload through IAM roles.
- Encrypt traffic in transit and data at rest with managed KMS keys.
- Apply WAF rules, rate limits, request timeouts, and maximum stream counts.
- Use private subnets for data systems and least-privilege security groups.
- Enforce Kubernetes network policies, non-root containers, read-only root filesystems, resource limits, and restricted pod security standards.
- Record security-sensitive actions in append-oriented audit events without logging secrets, tokens, prompts containing private data, or full provider payloads.
- Generate SBOMs, scan dependencies and images, sign release images, and verify signatures during deployment.

## Reliability and Observability

Define initial service-level objectives before production cutover:

- Rails read API: 99.9% monthly availability; p95 under 300 ms excluding third-party latency.
- Live market stream: 99.9% connection availability during supported market windows; p95 internal event delay under 2 seconds.
- Report workflows: 99% complete or reach a terminal actionable failure within 10 minutes.
- No acknowledged Kafka event may be silently discarded.

All services must emit structured logs, OpenTelemetry traces, RED metrics, dependency metrics, deployment metadata, and correlation IDs. Alerts should map to user-visible symptoms or exhausted error budgets and link to a runbook.

## AWS Topology

- Use separate AWS accounts for shared services, development, staging, and production.
- Provision networking, EKS, data services, DNS, certificates, secrets, and observability through Terraform.
- Run Rails API, Sidekiq, Temporal workers, Rust ingestion, and Rust streaming workloads on EKS.
- Keep managed stateful services outside the cluster: Aurora, ElastiCache, MSK, Timestream, and S3.
- Use ECR for images and Argo CD for declarative cluster reconciliation.
- Use GitHub Actions only to verify changes, build and sign images, publish artifacts, and update GitOps references.
- Use CloudFront for the React application and route API/stream traffic through WAF and an Application Load Balancer.
- Back up Aurora, version critical S3 buckets, test restore procedures, and document regional recovery objectives.

## Repository Direction

Move toward a monorepo while the system is one product:

```text
apps/
  web/                 React/Vite application
  platform-api/        Rails API
services/
  market-data/         Rust ingestion and streaming
  research-worker/     Temporal workflow workers
contracts/
  openapi/
  protobuf/
infra/
  terraform/
  helm/
  gitops/
docs/
  architecture/
  runbooks/
  decisions/
```

Use one ownership boundary per directory, generated clients from committed contracts, and language-native dependency management within each application.

## Migration Roadmap

Each phase ships through a separate PR. Do not start the next phase until the current phase's acceptance criteria pass in staging.

### Phase 0: Architecture Baseline

- Record architecture decisions for Rails, Rust, Kafka, Temporal, Cognito, Aurora, Timestream, EKS, and Gemini.
- Define service ownership, API/event contracts, SLOs, data classification, threat model, and cutover metrics.
- Capture current behavior with contract and browser characterization tests.
- Inventory current Supabase data, identities, provider integrations, and operational dependencies.

Acceptance criteria:

- Decisions and rejected alternatives are documented.
- Existing user journeys have executable characterization coverage.
- Migration and rollback owners are explicit.

### Phase 1: AWS and Delivery Foundation

- Create the account and network topology with Terraform.
- Provision ECR, EKS, Route 53, ACM, Secrets Manager, KMS, and baseline observability.
- Establish GitHub Actions OIDC, image builds, signing, Helm charts, and Argo CD promotion.
- Deploy minimal health-check workloads to development and staging.

Acceptance criteria:

- A clean account can be bootstrapped from versioned code.
- No long-lived AWS credentials exist in GitHub.
- Rollback to a prior image is tested.

### Phase 2: Rails Platform API

- Create the Rails API with PostgreSQL, RSpec, Pundit, OpenAPI, structured logging, and OpenTelemetry.
- Model favorites, portfolios, reports, audit events, idempotency keys, and the transactional outbox.
- Implement Cognito JWT verification behind a temporary compatibility boundary.
- Add Sidekiq for bounded background work.
- Shadow current read behavior before moving writes.

Acceptance criteria:

- Request, model, policy, migration, and contract tests pass.
- Tenant-boundary tests prove cross-user access is denied.
- Shadow-read differences are measured and resolved.

### Phase 3: React Application Extraction

- Create the Vite React application and generated Rails API client.
- Migrate authentication, dashboard, search, company, crypto, reports, and settings incrementally.
- Preserve accessibility, responsive behavior, charts, and error/loading states.
- Serve staging assets through S3 and CloudFront.

Acceptance criteria:

- Existing critical journeys pass in Chromium, Firefox, WebKit, and mobile Chromium.
- Accessibility and performance budgets do not regress.
- No server secret is included in browser bundles.

### Phase 4: Identity and Transactional Data Migration

- Configure Cognito OAuth/OIDC, MFA policy, token lifetimes, and role claims.
- Provision Aurora PostgreSQL and RDS Proxy.
- Build repeatable Supabase-to-Aurora data exports, transformations, validation, and reconciliation reports.
- Migrate identities with an explicit password-reset or just-in-time migration strategy.
- Dual-read, then dual-write only where necessary and for a bounded period.

Acceptance criteria:

- Row counts, checksums, ownership relationships, and sampled records reconcile.
- Authentication, revocation, and account recovery work end to end.
- A rehearsed rollback preserves writes and identity consistency.

### Phase 5: Rust Market Data Platform

- Implement Alpaca adapters, normalized schemas, Kafka publishing, backfills, and Timestream persistence.
- Add authenticated SSE fan-out with connection quotas and backpressure.
- Replay captured provider fixtures and test disconnect, duplication, reordering, and stale-feed scenarios.
- Move the React application from Next.js streaming routes to the Rust endpoint.

Acceptance criteria:

- Load tests meet stream latency and connection targets.
- Chaos tests demonstrate recovery without silent event loss.
- Every market event is traceable from provider receipt to client delivery.

### Phase 6: Gemini Research Workflows

- Integrate Gemini directly through Google's supported API/SDK.
- Define versioned prompts, structured outputs, allowlisted tools, safety settings, quotas, and evaluation datasets.
- Implement Temporal report workflows with idempotent activities and cancellation.
- Store artifacts in S3 and source metadata in Aurora.
- Migrate explanation, chat, and report behavior without introducing Bedrock.

Acceptance criteria:

- Golden evaluations cover factual grounding, tool selection, malformed output, prompt injection, and provider failure.
- Reports retain citations and data timestamps.
- Retries cannot duplicate reports or quota charges.

### Phase 7: Production Hardening

- Complete dashboards, alerts, runbooks, on-call exercises, capacity tests, backup restoration, and disaster-recovery rehearsal.
- Enforce WAF, network policies, workload identity, admission policies, vulnerability thresholds, and signed images.
- Run penetration, dependency, container, infrastructure, and authorization testing.

Acceptance criteria:

- SLO dashboards and actionable alerts are operational.
- Restore and rollback exercises meet documented objectives.
- No unresolved critical security finding remains.

### Phase 8: Cutover and Decommissioning

- Freeze incompatible schema changes during the final migration window.
- Perform final data synchronization and reconciliation.
- Shift traffic gradually with explicit abort thresholds.
- Observe at full traffic before removing compatibility paths.
- Decommission Vercel and Supabase only after the rollback window expires and backups are verified.

Acceptance criteria:

- Production traffic runs entirely on the target platform.
- Error rate, latency, data integrity, and workflow completion remain within thresholds.
- Legacy credentials, routes, infrastructure, and data copies are retired deliberately.

## Verification Strategy

Every phase should select the layers relevant to its risk:

- Static analysis and formatting for every language and infrastructure definition.
- Unit and property tests for business rules, parsers, and state transitions.
- Migration and database tests against real PostgreSQL.
- Request and policy tests for Rails authorization boundaries.
- Provider-fixture and replay tests for market ingestion.
- Contract tests for OpenAPI, Protobuf, and Kafka compatibility.
- Integration tests using containers for PostgreSQL, Redis, and Kafka where practical.
- Browser and accessibility tests for critical user journeys.
- Load, soak, and failure-injection tests for streaming and workflows.
- Terraform validation, policy checks, and disposable-environment plans.
- Post-deployment smoke tests and automated rollback signals.

Verification depth should scale with blast radius, failure cost, and uncertainty. Prefer tests that prove meaningful boundaries and failure behavior over a target ratio of test code to production code.

## Pull Request Requirements

Every implementation PR must include:

- One coherent change with explicit in-scope and out-of-scope statements.
- Schema, API, event, configuration, and operational documentation updates where applicable.
- Tests for new behavior and relevant failure paths.
- Migration, deployment, observability, and rollback notes.
- Evidence from the applicable local and staging verification layers.
- No unrelated refactor bundled into a migration phase.

## Completion Criteria

The revamp is complete when:

- React, Rails, Rust, and Gemini own the boundaries defined above.
- AWS infrastructure is reproducible through Terraform and reconciled through GitOps.
- Cognito, Aurora, Timestream, Redis, MSK, and S3 have tested security and recovery procedures.
- Critical journeys, tenant isolation, streaming recovery, report workflows, and provider failures have durable automated coverage.
- SLOs, alerts, traces, dashboards, and runbooks support production operation.
- The Next.js, Supabase, and Vercel runtime dependencies are removed after a verified rollback window.
