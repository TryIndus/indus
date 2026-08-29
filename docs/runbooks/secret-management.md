# Secret management and rotation

Terraform creates encrypted Secrets Manager containers but never their values.
Create JSON in an encrypted temporary location, set mode `0600`, and use
`scripts/aws/put-secret.sh` only from a short-lived federated session. The
script is a dry run unless `--apply` is supplied. Never paste values into a
shell argument, Terraform input, ticket, PR, or log.

Required objects:

| Secret | Required JSON keys |
|---|---|
| `indus-<env>/database-platform` | `username`, `password` for `indus_platform` |
| `indus-<env>/database-market` | `username`, `password` for `indus_market_writer` |
| `indus-<env>/database-migration` | `username`, `password`, `DATABASE_URL` for `indus_migrator` |
| `indus-<env>/platform-api` | `DATABASE_URL` using `indus_platform`, plus `SECRET_KEY_BASE`, `GEMINI_API_KEY` |
| `indus-<env>/market-data` | `DATABASE_URL` using `indus_market_writer`, plus `ALPACA_API_KEY`, `ALPACA_SECRET_KEY` |
| `indus-<env>/research-worker` | `DATABASE_URL` using `indus_platform`, plus `GEMINI_API_KEY`, `TEMPORAL_API_KEY` |

Every `DATABASE_URL` points at RDS Proxy with `sslmode=require`. Runtime URLs
must use the credential assigned to that workload family; the market writer
must never receive a platform URL. The migration URL uses `indus_migrator` and
is visible only to the `database-migrator` service account. Helm supplies
an owner role plus `search_path=public,pg_catalog` to the Rails migration job
and `search_path=market_data,pg_catalog` to the Rust migration job. This keeps
SQLx migration history in the market schema. Never put an owner role in a
runtime URL.

Rails and Rust use static database passwords and do not refresh RDS IAM tokens.
Rotate one identity at a time: generate a new value in a protected JSON file,
run the reviewed role-bootstrap command, update the corresponding proxy and
runtime secret versions, wait for proxy readiness, and restart only the owning
deployments through GitOps. Keep the prior secret versions staged until new
connections and jobs are healthy. The migration identity is rotated separately
and is not deployed outside hook jobs. Re-run the read-only database boundary
verifier after every database credential rotation. Kafka credentials are never
stored: Rails and Rust refresh MSK IAM tokens from workload identity.

Redis credentials are also never stored in AWS environments: platform-api and
Sidekiq sign short-lived ElastiCache connection tokens from their own IRSA
roles. The cache endpoint, cache name, port, and IAM user ID are non-secret
GitOps values.

Gemini rotation: add a new provider key, update both authorized secrets,
restart API and research workers, run one synthetic model evaluation, then
revoke the old key. Confirm no secret-shaped values appear in CloudWatch,
traces, pod events, or workflow artifacts. Secret access is audited in
CloudTrail; review unexpected `GetSecretValue` callers immediately.
