# Indus

Indus is a financial-intelligence platform for authenticated stock and crypto
research, live market data, model-assisted analysis, and generated reports.

## Current deployment

Production runs on the independent optimized AWS profile: a single EC2 host,
single-AZ PostgreSQL RDS instance, local Valkey, Cognito, S3, and four
digest-pinned application images in ECR. `tryindus.ca` resolves directly to
the host Elastic IP. There is no EKS, Aurora, RDS Proxy, MSK, ElastiCache,
CloudFront, ALB, NAT gateway, or separate optimized subdomain deployment.

See [the optimized infrastructure guide](./infra/optimized/README.md) and
[runbook](./docs/runbooks/optimized-aws.md) for provisioning, release,
recovery, and rollback procedures.

## Application architecture

- `apps/web` - React 19 and Vite browser application.
- `apps/platform-api` - Rails API, authorization, reports, and provider
  boundaries.
- `services/market-data` - Rust ingestion, persistence, and authenticated
  streaming.
- `contracts` - versioned OpenAPI and Protobuf contracts.
- `infra/optimized` - the active low-cost AWS deployment profile.

The root Next.js and Supabase application is retained only as a bounded
rollback implementation. It is not the production deployment path.

## Local development

Use the [application runbook](./docs/runbooks/local-application-platform.md)
for Rails and React work, or the
[distributed-platform runbook](./docs/runbooks/local-distributed-platform.md)
for the complete local system. The repository verification contract is in
[docs/QUALITY.md](./docs/QUALITY.md).

## Documentation

- [Application platform](./docs/architecture/application-platform.md)
- [Market data](./docs/architecture/market-data.md)
- [Research workflows](./docs/architecture/distributed-research-workflows.md)
- [Optimized AWS runbook](./docs/runbooks/optimized-aws.md)
- [Rollback runbook](./docs/runbooks/rollback.md)

## License

MIT. See [LICENSE](./LICENSE).
