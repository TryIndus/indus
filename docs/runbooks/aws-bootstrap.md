# AWS bootstrap and GitOps activation

Use this runbook only after a reviewed Terraform plan is approved. AWS creates billable resources. Bootstrap uses a short-lived,
MFA-backed operator session; subsequent workflows use AWS OIDC. Never place AWS access keys or application secret
values in GitHub, Terraform variables, plans, state, or Git.

## Prerequisites

- One shared-services AWS account and isolated staging and production accounts.
- Route 53 hosted zones that match the checked-in environment inputs.
- Terraform, AWS CLI, Helm, and kubectl installed locally.
- MFA-backed roles that can apply the reviewed shared and environment plans.
- For workflow-driven Terraform, an execution role and GitHub OIDC provider
  provisioned by the account administrator in each runtime account. Trust must
  require audience `sts.amazonaws.com` and subject
  `repo:TryIndus/indus:environment:staging` or
  `repo:TryIndus/indus:environment:production`, respectively. The role needs
  permissions to manage the environment resources and assume its shared state
  role. These administrator-managed execution roles are not created by the
  environment stack, so staging destroy cannot delete its own credentials.

## 1. Bootstrap shared services

Copy `infra/terraform/bootstrap/shared/terraform.tfvars.example` to ignored
`terraform.tfvars`, replace the account IDs, and authenticate to the shared
services account. Review the exact plan before applying it:

Set `terraform_execution_role_arns` to the pre-provisioned staging and production
execution-role ARNs. This grants those exact roles access to their shared state
role without the operator-only MFA condition.

```bash
terraform -chdir=infra/terraform/bootstrap/shared init
terraform -chdir=infra/terraform/bootstrap/shared plan -out=shared.tfplan
terraform -chdir=infra/terraform/bootstrap/shared show shared.tfplan
```

After explicit approval, apply exactly the saved plan. Configure these
repository variables from its outputs:

- `AWS_SHARED_REGION=us-east-1`
- `AWS_BUILD_ROLE_ARN`

Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` in each
GitHub Environment to that environment's public Supabase build configuration.

## 2. Provision an environment

Copy the checked-in staging examples to ignored local files and replace every
placeholder with shared bootstrap outputs, account ID, and Route 53 zone. Run:

```bash
terraform -chdir=infra/terraform/environments/staging init \
  -backend-config=backend.hcl
terraform -chdir=infra/terraform/environments/staging plan \
  -out=staging.tfplan
terraform -chdir=infra/terraform/environments/staging show staging.tfplan
```

Apply only the reviewed saved plan. Use the corresponding `production` paths
for production. Staging is optional developer infrastructure. Before production
traffic cutover, verify deployment, authentication, provider, and rollback behavior. Restrict
EKS API access to the approved operator network before cluster bootstrap.

## 3. Supply the one runtime secret

Terraform creates one empty Secrets Manager container named `legacy-next` per
environment for application configuration. Aurora also manages its own database
credential secret. Over an audited, short-lived session, supply these runtime keys:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `ALPACA_API_KEY`
- `ALPACA_SECRET_KEY`
- `GEMINI_API_KEY`

Do not print the payload or capture it in shell history. Confirm the legacy
workload role can read only this secret.

## 4. Bootstrap GitOps

Replace account-specific placeholders in
`infra/helm/indus-applications/values-<environment>.yaml` and
`infra/gitops/environments/<environment>/legacy-next.yaml` with Terraform
outputs. Leave the zero digest until the deployment workflow opens its first
deployment PR.

```bash
aws eks update-kubeconfig --region us-east-1 --name indus-staging
kubectl apply -f infra/gitops/bootstrap/namespaces.yaml
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm upgrade --install argocd argo/argo-cd \
  --version 10.9.1 --namespace argocd --wait --timeout 10m
kubectl apply -f infra/gitops/bootstrap/staging.yaml
```

Verify the add-on and policy applications are healthy before deployment. The
application cannot become healthy until its placeholder image and account
values have been replaced. Only the current
Next.js workload and required add-ons run in Phase 1.

## 5. Configure branch deployment

When developers need a shared deployed environment, create `staging` from
`main`. Configure GitHub Environment variables `AWS_TERRAFORM_ROLE_ARN` and
`AWS_TERRAFORM_REGION`, plus base64 secrets `TF_BACKEND_CONFIG_B64` and
`TF_VARS_B64`, in each environment. The encoded files are the environment's
ignored `backend.hcl` and `terraform.tfvars`.

Restrict the staging GitHub Environment to branch `staging` and production to
branch `main`; the AWS trust policies use environment subjects. Set each
environment's `AWS_TERRAFORM_ROLE_ARN` to its administrator-provisioned execution
role. Install a GitHub App on this repository with Contents and Pull Requests
write permissions, set `DEPLOY_APP_ID`, and store its private key as
`DEPLOY_APP_PRIVATE_KEY`. The application workflow uses its token so deployment
PRs trigger required CI checks.

Use `./bin/indus deploy app staging` from `staging` or
`./bin/indus deploy app production` from `main`. Infrastructure is dispatched
with `./bin/indus deploy infra <staging|production> <plan|apply|tear-up|tear-down|destroy>`.
`tear-down` removes EKS, Aurora instances, RDS Proxy, CloudFront, ALB, NAT,
application DNS records, and their dependent routes and workload IAM resources.
It retains the Aurora cluster volume, Cognito, DNS zone, VPC/subnets, secrets,
buckets, and backups. Retained storage and services can still incur charges.
`tear-up` restores the runtime. After a tear-up, update the recreated resource
outputs in GitOps values and repeat the Argo CD installation and bootstrap commands in step 4
before deploying the application. Both staging tear-down and full staging
destroy require `--confirm`; production lifecycle operations are not available.
Full `destroy` also deletes staging database contents and bucket objects; it is
not the operation for pausing an unused developer environment.
If the backup vault contains recovery points, AWS refuses its deletion until an
operator explicitly removes them or waits for retention expiry.

Merge reviewed feature pull requests into `main` before production deployment.
Use `staging` only when developers need a shared deployed environment.
