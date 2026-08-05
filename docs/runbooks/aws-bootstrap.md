# AWS environment bootstrap

## Safety and ownership

Use one AWS account each for shared services, development, staging, and
production. Operators authenticate with federation and MFA; GitHub receives no
long-lived AWS key. This repository does not apply infrastructure
automatically. Every apply needs a saved plan, peer review, correct-account
confirmation, and an approved change window for production.

Route 53 uses delegated environment subdomains because the gradual cutover is
a weighted CNAME and cannot be the zone apex. The primary workload region is
`ca-central-1`; CloudFront certificates, WAF, and recovery copies use
`us-east-1`.

## Bootstrap order

1. Apply `infra/terraform/bootstrap/shared` locally with a federated
   shared-account session. Migrate its local state into the new encrypted state
   bucket only after checking bucket versioning and the KMS recovery policy.
2. Configure GitHub variables `AWS_BUILD_ROLE_ARN`,
   `AWS_PROMOTION_ROLE_ARN`, and `ECR_REGISTRY` from Terraform outputs. Protect
   the development, staging, and production GitHub environments; require two
   reviewers for production.
3. Delegate each environment's Route 53 subdomain and copy the appropriate
   `backend.hcl.example` and `terraform.tfvars.example` to ignored local files.
4. For development, then staging, then production, bootstrap the empty RDS
   Proxy secret container before the full plan. Run a reviewed targeted apply
   for only
   `module.environment.aws_secretsmanager_secret.workload["database_proxy"]`,
   populate it with `scripts/aws/put-secret.sh <environment> database-proxy
   <file> --apply`, and verify that the database role already exists. This
   one-time ordering is required because RDS Proxy rejects a secret without a
   current `username`/`password` version. Never use the Aurora master user as
   an application credential.
5. Run `terraform init`, `terraform plan -out=<environment>.tfplan`, inspect
   the complete plan, and apply that exact plan. Never apply a speculative plan
   from CI.
6. Export the non-secret module output and hydrate the GitOps placeholders:

   ```bash
   terraform -chdir=infra/terraform/environments/development output -json environment > /tmp/development-output.json
   ruby scripts/hydrate-gitops.rb development /tmp/development-output.json
   ruby scripts/hydrate-gitops.rb development /tmp/development-output.json --write
   ```

7. Populate the remaining secret values using
   `docs/runbooks/secret-management.md`.
8. Set an explicit environment kubeconfig, run
   `scripts/aws/bootstrap-argocd.sh <environment>` to preview, then repeat with
   `--apply`. Argo CD owns everything after the root application.
9. Run `scripts/aws/verify-environment.sh <environment>` first in dry-run mode,
   then with `--execute-read-only`. Confirm alarms, backup recovery points,
   restricted admission, target health, and Argo convergence.

Production Terraform intentionally starts `replacement_traffic_weight = 0`.
Do not increase it until the migration and cutover gates pass. Production
backup-vault locks become immutable after three days; verify retention before
that compliance window closes.

## Failure and rollback

An infrastructure apply failure is not permission to retry blindly. Preserve
the plan and logs, inspect partial state with read-only commands, and either
apply a reviewed forward correction or use the service-specific rollback. Do
not delete stateful resources to force convergence. See
`docs/runbooks/rollback.md` and `docs/runbooks/backup-restore-dr.md`.
