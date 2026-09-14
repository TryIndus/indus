# AWS bootstrap and GitOps activation

Use this runbook only after a reviewed Terraform plan is approved. The
bootstrap creates billable AWS resources and must run from short-lived,
MFA-backed operator sessions. Never place AWS access keys or application
secret values in GitHub, Terraform variables, plans, state, or Git.

## Prerequisites

- One shared-services AWS account and isolated development, staging, and
  production accounts in AWS Organizations.
- One owned domain. Delegate a development subzone and a staging subzone to
  their respective accounts; keep the production application zone in the
  production account. Each environment Terraform root must be able to find
  its `route53_zone_name` in its own account.
- Terraform, AWS CLI, Helm, and kubectl installed locally.
- MFA-backed roles that can apply the reviewed shared and environment plans.

The account boundary is deliberate: shared services owns Terraform state,
ECR, and GitHub OIDC roles; each runtime environment owns its network,
cluster, data plane, edge, secrets, and observability resources. Account
creation and domain registration are not automated because they require
billing, recovery-contact, and ownership decisions outside this repository.

## 1. Bootstrap shared services

Copy `infra/terraform/bootstrap/shared/terraform.tfvars.example` to the
ignored `terraform.tfvars`, replace every account ID, and authenticate to the
shared-services account. Then create and review the plan:

```bash
terraform -chdir=infra/terraform/bootstrap/shared init
terraform -chdir=infra/terraform/bootstrap/shared plan -out=shared.tfplan
terraform -chdir=infra/terraform/bootstrap/shared show shared.tfplan
```

After explicit approval, apply exactly the saved plan. Record the state
bucket, KMS key ARN, ECR URLs, state-role ARNs, and GitHub role ARNs from the
outputs. Configure these repository variables:

- `AWS_SHARED_REGION`
- `AWS_BUILD_ROLE_ARN`
- `AWS_PROMOTION_ROLE_ARN`
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

The two Supabase values are publishable browser configuration, not provider
credentials. Create lowercase GitHub environments named `development`,
`staging`, and `production`; require reviewers for production.

## 2. Provision environments in order

For development first, copy the checked-in `backend.hcl.example` and
`terraform.tfvars.example` to their ignored filenames. Replace every
placeholder with the shared bootstrap outputs, the environment account ID,
the delegated Route 53 zone, and approved operator CIDRs. Authenticate to the
development account and run:

```bash
terraform -chdir=infra/terraform/environments/development init \
  -backend-config=backend.hcl
terraform -chdir=infra/terraform/environments/development plan \
  -out=development.tfplan
terraform -chdir=infra/terraform/environments/development show \
  development.tfplan
```

Apply only the reviewed saved plan. Repeat for staging only after development
acceptance, and for production only after staging acceptance and the required
two-person approval. Production must use the private EKS endpoint, so the
operator needs an approved network path before cluster bootstrap.

## 3. Supply runtime secrets

Terraform creates empty Secrets Manager containers. Over an audited,
short-lived session, store these keys in the environment's `legacy_next`
secret: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`,
`ALPACA_API_KEY`, `ALPACA_SECRET_KEY`, and `GEMINI_API_KEY`. Do not print the
payload or capture it in shell history. Confirm the legacy workload role can
read only this secret and its KMS key.

## 4. Hydrate and bootstrap GitOps

Replace the account-specific placeholders in
`infra/helm/indus-applications/values-<environment>.yaml` and
`infra/gitops/environments/<environment>/legacy-next.yaml` with the reviewed
Terraform outputs. Leave the image digest at its zero placeholder until the
release workflow opens the first promotion pull request.

Configure kubectl for the environment cluster, apply the namespace controls,
and install the pinned Argo CD chart:

```bash
aws eks update-kubeconfig --region ca-central-1 --name indus-development
kubectl apply -f infra/gitops/bootstrap/namespaces.yaml
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm upgrade --install argocd argo/argo-cd \
  --version 10.9.1 \
  --namespace argocd \
  --wait \
  --timeout 10m
kubectl apply -f infra/gitops/bootstrap/development.yaml
```

Verify every Argo CD application is healthy before allowing a workload
promotion. The replacement-platform application stays disabled during Phase
1; only the current Next.js workload and the required add-ons/policies run.

## 5. Release and promote

Every relevant push to `main` runs the `AWS legacy release` workflow for
development. It assumes the ECR publisher role with GitHub OIDC, builds the
current commit, blocks on high or critical image vulnerabilities, generates an
SBOM, pushes an immutable ECR tag, signs and attests the digest, verifies it
through the promotion role, and opens a pull request changing only the
development digest. Use a manual dispatch for the first release after the AWS
repository variables are configured.

Merge the promotion pull request after its checks pass. Argo CD then
reconciles that exact digest. After development acceptance, run `Promote AWS
legacy image` with the existing digest for staging, and later production. Each
environment gate verifies the signature and SBOM attestation and opens its own
digest-only pull request. Never rebuild an environment-specific image or copy
a mutable tag. Follow `aws-legacy-next.md` for smoke tests, production traffic
cutover, and rollback.

## Rollback

Revert the last GitOps promotion to restore the previous signed digest. During
the production rollback window, return the Route 53 weight to the Vercel
origin. Do not destroy Vercel, the prior image, or runtime secrets until the
window closes and the AWS deployment has passed its acceptance checks.
