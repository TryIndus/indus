# Optimized AWS operations

This runbook covers `infra/optimized`. See the [profile overview](README.md)
for topology and the [cost worksheet](COSTS.md) for sizing and spend. Use
reviewed plans and explicit authorization for applies, releases, DNS changes,
and data recovery.

## Operating constraints

- One application host and one private RDS instance run in one AZ. Host or AZ
  failure interrupts service. The second database subnet provides no standby.
- Access the host through SSM; only HTTP and HTTPS are exposed publicly.
- Keep optimized state, resources, IAM roles, secrets, and Cognito identities
  separate from the main profile. The account-level OIDC provider and an
  authorized operator identity can be reused.
- Valkey persists to EBS, but abrupt host loss can lose recent queue work.
- Monitor memory, CPU credits, disk, database connections, latency, ingestion,
  and Sidekiq backlog. Retain 4 GiB host memory until a load test supports less.

## Provision

1. Create GitHub Environments `optimized-production-plan` and
   `optimized-production`, restricted to `main`. Require approval on the latter.
2. Copy the [bootstrap variables example](terraform/bootstrap/terraform.tfvars.example)
   to its ignored counterpart. Supply the account ID and existing OIDC provider
   ARN. Initialize Terraform, review a saved plan, and apply the bootstrap.
3. Migrate bootstrap state into the new optimized backend with a reviewed
   `terraform init -migrate-state`. Record the backend bucket, KMS key, ECR
   repositories, and role ARNs. Do not reuse the main profile's state.
4. Configure ignored files from the environment
   [backend](terraform/environment/backend.hcl.example) and
   [variables](terraform/environment/terraform.tfvars.example) examples. Choose
   a nonoverlapping VPC CIDR, two AZs, and optimized ECR ARNs. The second AZ
   needs only the private subnet required by the RDS subnet group.
5. Configure these settings in both GitHub Environments:

   | Setting | Value |
   | --- | --- |
   | `OPTIMIZED_TF_BACKEND_CONFIG_B64` | Base64-encoded private backend file |
   | `OPTIMIZED_TF_VARS_B64` | Base64-encoded private variables file |
   | `OPTIMIZED_AWS_REGION` | Optimized region |
   | `OPTIMIZED_PLAN_ROLE_ARN` | Optimized plan role |
   | `OPTIMIZED_TERRAFORM_ROLE_ARN` | Optimized apply role |

6. Dispatch `optimized-infrastructure` from `main`. `plan` previews changes;
   `apply` saves a plan and publishes its summary, then waits for approval
   before applying that exact plan.

RDS uses `apply_immediately`: inspect pending modifications before every apply.
The [capacity retry workflow](../../scripts/capacity/README.md) permits only its
approved resize, rejects pending changes, and retries capacity errors. A
successful resize interrupts connections and opens a follow-up issue.

## Secrets and identity

Terraform creates secret containers; an audited operator supplies their values
in Docker env-file format (`KEY=value`, one per line). Keep credentials out of
Terraform, user data, release manifests, and workflow output.

| Service | Configuration |
| --- | --- |
| Rails and workers | TLS-required `DATABASE_URL`, optimized Cognito issuer/client/UserInfo URL, web origin, artifact bucket, model provider, and Temporal Cloud settings as applicable |
| Market data | TLS-required `DATABASE_URL`, `MARKET_JWKS_URL`, `MARKET_JWT_ISSUER`, `MARKET_JWT_AUDIENCE`, `MARKET_ALLOWED_ORIGINS`, and Alpaca credentials |

Use the RDS-managed master secret to provision a PostgreSQL runtime role with
the database and schema privileges required by Rails and Rust. Do not configure
Kafka or ElastiCache IAM settings here. To rotate secrets, update Secrets
Manager and restart the optimized systemd service; startup refreshes the
root-owned files under `/run/indus-optimized`.

The Cognito pool has its own users and issuer; MFA is off. Before enabling
`enable_branded_cognito_email`, confirm SES production sending access in the
region and set `branded_email_zone_id` to the existing `tryindus.ca` zone.
Terraform creates the SES identity and DKIM records there. Keep the flag off
until delivery prerequisites are met; the default Cognito sender remains available.

## Publish and deploy

1. Set public GitHub variables `OPTIMIZED_WEB_ORIGIN`,
   `OPTIMIZED_COGNITO_AUTHORITY`, and `OPTIMIZED_COGNITO_CLIENT_ID` from the
   optimized outputs. Set the instance ID, release-role ARN, and runtime secret
   ARNs in the deployment environment. See the
   [release workflow](../../.github/workflows/optimized-application.yml) for names.
2. Dispatch `optimized-application` with `publish`. It scans and pushes images,
   then opens a PR updating `releases/production.env` with immutable digests.
   Review and merge that manifest.
3. Dispatch `deploy` from `main`. The host fetches its secrets, pulls pinned
   images, runs the Rails migration job, and starts the application.
4. Verify health. The installer checks that `web-proxy` is running; this alone
   does not establish application readiness.

Check Rails `/readyz`, Rust `/health/ready`, an authenticated `/api/v1/...`
request, and authenticated SSE for `AAPL` and slash-delimited crypto such as
`BTC/USD`, including reconnection with a replay cursor. Caddy serves the SPA,
routes `/api` to Rails, and routes `/stream` to Rust without SSE buffering.

The web image rebuilds Caddy with a pinned Go toolchain and
[locked modules](images/web/caddy/go.mod) to patch dependencies in the upstream
binary. Proxy routing tests and the runtime vulnerability scan run before merge.

## DNS and www

Use the existing authoritative Route 53 zone:

| Name | Record | Target |
| --- | --- | --- |
| `tryindus.ca` | A | Host Elastic IP |
| `www.tryindus.ca` | CNAME | `tryindus.ca` |

Replace any registrar-forwarding `www` record. Keep ports 80 and 443 reachable
for HTTPS and certificate renewal. Caddy serves both names and permanently
redirects `www` to the apex, preserving paths and queries. Allow the previous
DNS TTL to expire, then verify without disabling certificate validation:

```bash
curl --head 'https://www.tryindus.ca/research?symbol=BTC%2FUSD'
```

Expect `301` with `Location: https://tryindus.ca/research?symbol=BTC%2FUSD`.
Run `node --test scripts/optimized/web-proxy.test.mjs` with Docker for isolated
routing tests using the production-pinned image and a trusted temporary CA.
These tests do not access AWS or request public certificates.

### Temporary proxy repair

If a repair must precede the updated web image:

1. Back up the running Caddyfile under `/opt/indus-optimized/ops-backups/`.
2. Validate the replacement with the running Caddy binary and install it as
   `/opt/indus-optimized/www-redirect.Caddyfile`.
3. Mount it read-only at `/etc/caddy/Caddyfile` for `web-proxy` through
   `/opt/indus-optimized/compose.override.yaml`. Validate the merged Compose
   configuration and recreate only `web-proxy` with `up -d --no-deps web-proxy`.
4. After deploying an image containing the redirect, compare its Caddyfile with
   the mounted file, remove only that mount, and recreate `web-proxy`. Preserve
   unrelated override settings; delete the override file only if empty.

The override survives releases and restarts. To undo a repair, restore the prior
DNS record and proxy configuration and recreate `web-proxy`. A plain apex A
record provides no automatic Vercel failover.

## Rollback and recovery

| Failure | Procedure |
| --- | --- |
| Bad release | Review `/opt/indus-optimized/previous-release.env`, restore the prior manifest through the release process, and dispatch `deploy`. Installer startup failure also attempts to restore the saved manifest. Verify health afterward. |
| Lost host | Replace it through a reviewed plan, restore configuration and secrets, and verify health before switching DNS. Recover Valkey from available backups; account for lost recent queue work. |
| Database damage | Restore a tested RDS backup and reconcile writes after the recovery point. Image rollback does not undo migrations or data writes; schema corrections are forward-only. |
| Identity migration | Map subjects through an audited process. Rails ownership uses `(issuer, external_subject)`; changing Cognito pools does not preserve ownership automatically. |

## Monitoring

`enable_supplementary_monitoring` defaults to `false`. Basic EC2/RDS metrics,
RDS backups, bounded Docker logs, and SSM remain available. Check health and
spend directly while notifications are disabled.

1. To change monitoring, update the flag in private variables and apply a
   reviewed plan.
2. Through SSM, run this on the host with `AWS_REGION` set:

   ```bash
   /opt/indus-optimized/install-release.sh \
     /opt/indus-optimized/release.env --reconcile-monitoring
   ```

3. Verify the CloudWatch agent state. When enabled, confirm SNS subscriptions
   and test alarm delivery. Reconciliation does not restart the application.

The flag controls CloudWatch alarms and agent metrics, SNS, RDS events and
Performance Insights, an HTTPS health check, and budget notifications. A later
application start also reconciles the agent setting.
