# Low-risk AWS cost reductions

The environment module keeps the existing two-node production capacity, private database, backups, authentication, and application images. Infrastructure is applied separately through `Deploy infrastructure`; merging this change does not apply Terraform.

## Suspend supplementary monitoring

`enable_supplementary_monitoring` defaults to `false` in production and staging. It omits application and VPC flow CloudWatch log groups, VPC flow logging, PostgreSQL log exports, Performance Insights, CloudWatch alarms, SNS alert delivery, the monthly budget notifications, and account cost anomaly alerts. EKS `audit` and `authenticator` control-plane logs remain enabled as security records. Aurora backups and the core application infrastructure remain enabled. Set the flag to `true` in the environment Terraform configuration to restore these resources, then apply a reviewed infrastructure plan. Disabling it destroys the listed managed resources and stops new monitoring data collection. Deleting the Terraform-managed log groups also deletes their retained log events; re-enabling monitoring creates empty groups. Existing CloudWatch metrics already emitted by AWS may remain available under AWS retention rules.

This change reduces observability and cost notifications. Operators must inspect service health and AWS spend directly while the flag is disabled.

## Logging

EKS retains `audit` and `authenticator` logging by default and omits the verbose `api` stream. For incident response, set `eks_log_types = ["api", "audit", "authenticator"]` in the environment Terraform configuration and apply a reviewed plan. Rejected VPC flows remain logged, with a ten-minute aggregation window instead of one minute. Application errors, database exports, log retention, and alarms are unchanged. Savings depend on the actual contribution of these streams to ingestion; do not assume the entire CloudWatch bill disappears.

## Remove RDS Proxy without dropping existing clients

`database_access_mode` defaults to `proxy`, preserving existing clients and resource identities through Terraform moved blocks. Do not choose `direct` until the secret and workload cutover below is complete. Aurora remains private, encrypted, TLS-required, backed up, and protected against deletion in production.

1. Set `database_access_mode = "prepare-direct"` in the environment's private Terraform variables. Update the production GitHub environment's `TF_VARS_B64` from the private configuration without printing or committing its contents. Run `Deploy infrastructure` from `main` with operation `plan`, review the plan, then run operation `apply`. This adds PostgreSQL ingress from the existing EKS cluster security group while retaining RDS Proxy. Confirm the plan does not replace Aurora, alter DNS, or destroy database resources.
2. Obtain `data_platform.aurora_endpoint` from Terraform's environment output. Change only the hostname in `DATABASE_URL` for the platform-api, market-data, research-worker, and database-migration runtime secrets in Secrets Manager. Preserve the database, username, password, TLS parameters, and every unrelated secret field. Preserve the prior secret version IDs as rollback points; never display secret contents in logs or terminal output. Use the Aurora writer endpoint, not an instance IP. The GitOps endpoint value is informational: updating it does not rewrite these runtime secrets.
3. Allow secret synchronization, then restart all database clients: platform-api, sidekiq, platform-outbox, reports-consumer, market-data, and research-worker if enabled. Verify the migration job uses the new secret. A secret rotation alone does not change the environment of an already-running pod.
4. Check database connection capacity at the maximum configured replica counts, including rolling-update overlap and migration jobs. Rails pools are bounded by `RAILS_MAX_THREADS` (default 5) and Rust currently uses at most 10 connections per instance. Check worker concurrency against Rails pools, connection errors, and Aurora's available connection limit. Do not remove the proxy if direct connections cannot fit with operational headroom.
5. Validate health, authenticated company research, live chart reconnects, favorites, report creation/completion, and background processing. Confirm Aurora connections succeed and proxy client connections have drained to zero after old pods terminate. Keep the proxy available during this observation period.
6. Set `database_access_mode = "direct"`, update the private Terraform variables, and review a new infrastructure plan. It should remove only proxy-specific resources while retaining direct private access, Aurora, backups, and application infrastructure. Apply the saved reviewed plan using the existing workflow. This is the step that removes the proxy charge.
7. Re-render the GitOps bootstrap from current Terraform outputs through the existing bootstrap tooling. Its existing `rdsProxyEndpoint` configuration key now accepts the selected database endpoint for compatibility; `DATABASE_URL` remains authoritative.

There is no schema migration or data movement. Based on September 25 billing, removing RDS Proxy avoids about US$86 per 30 days; the actual savings appear only after the resource is removed.

## Rollback

Before proxy removal, restore the previous runtime-secret versions and restart the database clients; the proxy is still available. After removal, change the mode back to `prepare-direct`, plan and apply to recreate the proxy, obtain its new endpoint, update runtime secrets to that endpoint, restart clients, and validate health before optionally returning to `proxy`. A recreated proxy's hostname may differ: never assume the old hostname works. No database restore is required.

For logging rollback, set `enable_supplementary_monitoring = true` in a topic PR and apply a reviewed infrastructure plan. New log groups start empty; audit and authenticator records remain available throughout.

## Verification

Run Terraform formatting, backend-free initialization and validation for all three roots, and `terraform -chdir=infra/terraform/environments/production test`. Tests use mocked providers and do not access AWS or state. Run the deployment lifecycle and GitOps renderer tests, Helm lint/render checks, and workflow validation from `.github/workflows/aws-foundation.yml`.

Live production plans and runtime cutover require authenticated AWS access and the private environment configuration. Offline tests validate configuration and cutover modes, not deployed connection capacity. One-node production capacity, NAT replacement, Kafka removal, and database engine changes are deferred.
