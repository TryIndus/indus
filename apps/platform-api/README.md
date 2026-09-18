# Platform API

The platform API is the Rails boundary for the Indus application.

## Runtime

- Ruby 3.4.10 and Rails 8.1.3.1
- PostgreSQL for durable state
- Sidekiq and Redis for asynchronous work
- Amazon Cognito access-token verification and verified profile lookup
- Google Gemini behind `ModelGateway`

Use the repository's containerized Rails toolchain rather than the host Ruby installation. Dependencies are pinned in `Gemfile.lock`.

## Configuration

The service fails closed when required identity, database, or model configuration is absent. Secrets are supplied through the process environment and must never be committed.

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | PostgreSQL connection URL |
| `REDIS_URL` | Sidekiq Redis URL |
| `KAFKA_BROKERS` | Comma-separated Kafka bootstrap brokers |
| `KAFKA_AUTH_MODE` | `plaintext` locally or `msk_iam` with AWS workload identity |
| `REPORT_ARTIFACT_BUCKET` | S3-compatible bucket for generated report artifacts |
| `OBJECT_STORAGE_ENDPOINT` | Optional path-style endpoint used by local MinIO |
| `COGNITO_JWT_ISSUER` | Exact Cognito user-pool issuer |
| `COGNITO_CLIENT_ID` | Public app-client ID accepted by the API |
| `COGNITO_USERINFO_URL` | HTTPS Cognito user-info endpoint used to retrieve verified profile attributes |
| `GEMINI_API_KEY` | Server-side Gemini credential |
| `GEMINI_MODEL` | Model selection; defaults to `gemini-3.8-flash` |
| `OTEL_TRACES_EXPORTER` | Trace exporter; defaults to `none` so local and test runs make no export attempts |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP collector endpoint when the exporter is explicitly enabled |

Production also requires Rails' standard `SECRET_KEY_BASE`. No Rails master key or encrypted credential file is used.

## Boundaries

Every `/v1` request requires a signed Cognito access token. The API fixes the issuer and app-client ID in server configuration, rejects ID tokens, confirms that Cognito returns the same subject and a verified email, and then lets Pundit scope every tenant-owned query by the internal user identifier. Mutations require an `Idempotency-Key`; the mutation, audit event, and replay response commit in one transaction. Reusing a key with the same request replays the recorded response, while changing the request returns `409`. Reports are created together with an outbox event in that transaction; workers may process that event only after commit. Provider credentials and provider payloads do not cross the API boundary.

Model-backed operations are owned by a task registry in `ModelGateway`. Each task pins a prompt version, receives bounded server-side evidence, supplies Gemini with a structured response schema when supported, rejects unrecognized citations, normalizes usage and provider failures, and consumes a per-user quota before invocation. Quota writes use a dedicated database connection so a billable provider failure cannot roll the charge back with the surrounding idempotency transaction.

Committed outbox rows are published to Kafka, and an idempotent consumer enqueues report generation on Sidekiq. Activity leases prevent overlapping model and artifact work, while retries mark permanently failed reports. Research claims must cite allowlisted evidence with matching as-of values before artifacts are stored.

`GET /healthz` proves the process can serve HTTP. `GET /readyz` additionally verifies PostgreSQL connectivity and returns `503` when it is unavailable. Neither endpoint requires authentication.

## Verification

From the repository root, run the Rails commands through the pinned tool image with a writable bundle volume. A PostgreSQL test database is required.

```sh
bundle exec rails db:prepare
bundle exec rspec
bundle exec rubocop
bundle exec brakeman --no-pager
```

The service tests use generated signing keys and deterministic provider fixtures. They never call Cognito, Gemini, or Yahoo over the network.

## Rollback

Before traffic is cut over, rollback consists of stopping this service; the current Next.js runtime remains unchanged. Once this schema contains production writes, use forward-only corrective migrations and the controlled cutover runbook rather than reversing migrations that may discard data.
