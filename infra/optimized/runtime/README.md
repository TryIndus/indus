# Optimized runtime

This Compose graph is only for the independent optimized EC2 host. It does not
replace the EKS/GitOps deployment in `infra/terraform`.

The release agent writes digest-pinned image references to
`/opt/indus-optimized/release.env` and retrieves runtime secrets into
`/run/indus-optimized/*.env` with owner-only permissions. Never copy secret
values into this directory, this repository, cloud-init, or the Compose file.

Start order is Valkey, one explicit Rails `migrate` job, Rails/worker processes,
market data migrations and ingestion, then Caddy. `RAILS_SKIP_DB_PREPARE=true`
prevents the Rails web process from racing the one-off migration job.
