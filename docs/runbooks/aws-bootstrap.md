# AWS bootstrap and GitOps activation

Use this runbook only after a reviewed Terraform plan is approved. AWS creates billable resources and must run from a short-lived,
MFA-backed operator session. Never place AWS access keys or application secret
values in GitHub, Terraform variables, plans, state, or Git.

## Prerequisites

- One shared-services AWS account and isolated staging and production accounts.
- Route 53 hosted zones that match the checked-in environment inputs.
- Terraform, AWS CLI, Helm, and kubectl installed locally.
- MFA-backed roles that can apply the reviewed shared and environment plans.

## 1. Bootstrap shared services

Copy `infra/terraform/bootstrap/shared/terraform.tfvars.example` to ignored
`terraform.tfvars`, replace the account IDs, and authenticate to the shared
services account. Review the exact plan before applying it:

```bash
terraform -chdir=infra/terraform/bootstrap/shared init
terraform -chdir=infra/terraform/bootstrap/shared plan -out=shared.tfplan
terraform -chdir=infra/terraform/bootstrap/shared show shared.tfplan
```

After explicit approval, apply exactly the saved plan. Configure these
repository variables from its outputs:

- `AWS_SHARED_REGION=us-east-1`
- `AWS_BUILD_ROLE_ARN`
- `AWS_TERRAFORM_ROLE_ARN`
- `AWS_TERRAFORM_REGION=us-east-1`
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

## 2. Provision staging, then production

Copy the checked-in staging examples to ignored local files and replace every
placeholder with shared bootstrap outputs, account ID, and Route 53 zone. Run:

```bash
terraform -chdir=infra/terraform/environments/staging init \
  -backend-config=backend.hcl
terraform -chdir=infra/terraform/environments/staging plan \
  -out=staging.tfplan
terraform -chdir=infra/terraform/environments/staging show staging.tfplan
```

Apply only the reviewed saved plan. Do not provision production until staging
has passed deployment, authentication, provider, and rollback checks. Restrict
EKS API access to the approved operator network before cluster bootstrap.

## 3. Supply the one runtime secret

Terraform creates one empty Secrets Manager container named `legacy-next` per
environment. Over an audited, short-lived session, supply these keys:

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

Verify Argo CD applications are healthy before deployment. Only the current
Next.js workload and required add-ons run in Phase 1.

## 5. Configure branch deployment

Create `staging` from `main` after this PR merges. Configure GitHub Environment
variables `AWS_TERRAFORM_ROLE_ARN` and `AWS_TERRAFORM_REGION`, plus base64
secrets `TF_BACKEND_CONFIG_B64` and `TF_VARS_B64`, in each environment. The
encoded files are the environment's ignored `backend.hcl` and `terraform.tfvars`.

Use `./bin/indus deploy app staging` from `staging` or
`./bin/indus deploy app production` from `main`. Infrastructure is dispatched
with `./bin/indus deploy infra <staging|production> <plan|apply|destroy>`.
Staging destroy additionally requires `--confirm`; production destroy is not
available.

Merge reviewed changes from `staging` to `main` before production deployment.
