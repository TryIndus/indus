# AWS infrastructure

Terraform has two boundaries:

- `bootstrap/shared` runs once in the dedicated Indus member account. It creates
  encrypted remote state, immutable ECR repositories, and GitHub Actions OIDC
  roles.
- `environments/production` is the active environment and uses its own state
  key, VPC, IAM boundary, and copy of the environment module. The checked-in
  `environments/staging` configuration is dormant reference material; it is
  not required for merges to `main`. Source control alone does not establish
  whether staging resources still exist in AWS.

Terraform never stores runtime secret values.

Provider locks are committed for reproducibility. Local `.terraform/`, backend
files, plans, state, and variable files remain ignored.

```bash
cp infra/terraform/bootstrap/shared/terraform.tfvars.example \
  infra/terraform/bootstrap/shared/terraform.tfvars
terraform -chdir=infra/terraform/bootstrap/shared init
terraform -chdir=infra/terraform/bootstrap/shared plan -out=shared.tfplan

cp infra/terraform/environments/production/backend.hcl.example \
  infra/terraform/environments/production/backend.hcl
cp infra/terraform/environments/production/terraform.tfvars.example \
  infra/terraform/environments/production/terraform.tfvars
terraform -chdir=infra/terraform/environments/production init \
  -backend-config=backend.hcl
terraform -chdir=infra/terraform/environments/production plan \
  -out=production.tfplan
```

Apply only after reviewing the saved plan. See
`docs/runbooks/aws-bootstrap.md` for the required order, configuration, and
rollback procedure.
