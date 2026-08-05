# Secret management and rotation

Terraform creates encrypted Secrets Manager containers but never their values.
Create JSON in an encrypted temporary location, set mode `0600`, and use
`scripts/aws/put-secret.sh` only from a short-lived federated session. The
script is a dry run unless `--apply` is supplied. Never paste values into a
shell argument, Terraform input, ticket, PR, or log.

Required objects:

| Secret | Required JSON keys |
|---|---|
| `indus-<env>/database-proxy` | `username`, `password` for the least-privilege `indus_app` database role |
| `indus-<env>/platform-api` | `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY_BASE`, `GEMINI_API_KEY` |
| `indus-<env>/market-data` | `DATABASE_URL`, `ALPACA_API_KEY`, `ALPACA_SECRET_KEY` |
| `indus-<env>/research-worker` | `DATABASE_URL`, `REDIS_URL`, `GEMINI_API_KEY`, `TEMPORAL_API_KEY` |

`DATABASE_URL` points at RDS Proxy with TLS verification and the same
`indus_app` credential held by the proxy secret. Rails currently uses a static
database password; it does not refresh RDS IAM tokens. Rotate by creating the
new database credential, updating both proxy and workload secret versions,
waiting for proxy readiness, and restarting Rails/worker deployments through a
reviewed GitOps annotation change. Keep the prior version staged until all
connections and jobs are healthy, then revoke it. Kafka credentials are never
stored: Rails and Rust refresh MSK IAM tokens from IRSA.

Gemini rotation: add a new provider key, update both authorized secrets,
restart API and research workers, run one synthetic model evaluation, then
revoke the old key. Confirm no secret-shaped values appear in CloudWatch,
traces, pod events, or workflow artifacts. Secret access is audited in
CloudTrail; review unexpected `GetSecretValue` callers immediately.
