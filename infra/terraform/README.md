# AWS infrastructure

Terraform has two boundaries:

- `bootstrap/shared` runs once in the shared-services account. It creates
  encrypted remote state, immutable ECR repositories, and GitHub Actions OIDC
  roles.
- `environments/{staging,production}` runs in isolated runtime accounts. Each
  uses a distinct state key and the same environment module.

Terraform never stores runtime secret values.

Provider locks are committed for reproducibility. Local `.terraform/`, backend
files, plans, state, and variable files remain ignored.

```bash
cp infra/terraform/bootstrap/shared/terraform.tfvars.example \
  infra/terraform/bootstrap/shared/terraform.tfvars
terraform -chdir=infra/terraform/bootstrap/shared init
terraform -chdir=infra/terraform/bootstrap/shared plan -out=shared.tfplan

cp infra/terraform/environments/staging/backend.hcl.example \
  infra/terraform/environments/staging/backend.hcl
cp infra/terraform/environments/staging/terraform.tfvars.example \
  infra/terraform/environments/staging/terraform.tfvars
terraform -chdir=infra/terraform/environments/staging init \
  -backend-config=backend.hcl
terraform -chdir=infra/terraform/environments/staging plan \
  -out=staging.tfplan
```

Apply only after reviewing the saved plan. See
`docs/runbooks/aws-bootstrap.md` for the required order, configuration, and
rollback procedure.
