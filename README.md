# Indus

Indus is a financial intelligence platform for authenticated stock and
cryptocurrency research, live market data, model assisted analysis, and
generated reports.

## Architecture

The main AWS infrastructure configuration in [`infra/terraform`](./infra/terraform/README.md)
is the canonical architecture and operations reference. It defines the
network, EKS workloads, Aurora PostgreSQL, RDS Proxy, ElastiCache, MSK,
Cognito, S3, and deployment boundaries. The checked-in application and
contract code defines product behavior. Infrastructure code describes what a
configuration provisions; it does not by itself prove which resources are
currently running in an AWS account.

- [`apps/web`](./apps/web/README.md) contains the React and Vite browser application.
- [`apps/platform-api`](./apps/platform-api/README.md) contains the Rails API, authorization, reports, and provider boundaries.
- [`services/market-data`](./services/market-data/README.md) contains Rust market ingestion, persistence, and authenticated streaming.
- [`contracts`](./contracts) contains versioned OpenAPI and Protobuf contracts.

The root Next.js and Supabase application is retained as a bounded rollback
implementation. New product behavior belongs in the React, Rails, and Rust
services.

## Local development and verification

Use the [application runbook](./docs/runbooks/local-application-platform.md)
for Rails and React work, and the
[distributed platform runbook](./docs/runbooks/local-distributed-platform.md)
for the complete local system. [Quality](./docs/QUALITY.md) defines the
required checks for each changed boundary.

## Durable references

- [Application platform](./docs/architecture/application-platform.md)
- [Market data](./docs/architecture/market-data.md)
- [Research workflows](./docs/architecture/distributed-research-workflows.md)
- [AWS bootstrap](./docs/runbooks/aws-bootstrap.md)
- [Rollback](./docs/runbooks/rollback.md)

## License

MIT. See [LICENSE](./LICENSE).
