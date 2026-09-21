# Staging replacement image publishing

From the `staging` branch, run `./bin/indus deploy app staging --replacement`.
The existing application workflow builds Rails (also used by Sidekiq, outbox,
report consumers, migrations, and research workers), Rust market data, and the
React static web publisher. Replacement publishing rejects every other branch.
The default legacy deployment remains available without the flag.

Configure these public GitHub staging Environment variables before dispatch:

- `WEB_ORIGIN`: the HTTPS public origin, without a trailing slash.
- `COGNITO_AUTHORITY`: the Cognito user-pool issuer URL
  (`https://cognito-idp.us-east-1.amazonaws.com/<pool-id>`), used to identify the user pool.
- `COGNITO_CLIENT_ID`: the public web client ID.

Existing repository build-role and region variables are also required.
These values are public browser configuration; never supply provider keys here.

All four images must pass vulnerability scans before any image is pushed.
Each published digest receives a signature and SBOM attestation. A PR targeting
staging updates only image references and the web release identifier; both
verification workflows are explicitly dispatched on that PR's branch.
Publishing does not enable Argo applications, apply infrastructure, migrate
databases, or change traffic. Partial publication may leave unused immutable
images; a failed publication does not update deployment references.

Before activating the platform, provision its stateful dependencies, workload
roles, target groups, secrets, and private configuration. Verify a database
backup and approved rollback point before synchronizing migration jobs.
The current report path runs through Sidekiq and does not require a Temporal
Cloud namespace; the compatibility placeholders in the private Terraform
output are not consumed by the deployed workloads.
Retain previous verified digests for image rollback and use forward migrations
or restoration to a new database for data recovery. Production promotion,
Supabase migration, and legacy retirement require separate approval.
