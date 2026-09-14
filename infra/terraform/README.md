# AWS infrastructure

The AWS platform uses two Terraform boundaries:

- `bootstrap/shared` runs once in the shared-services account. It creates the
  encrypted remote-state bucket, immutable ECR repositories, and the GitHub
  Actions OIDC publisher role.
- `environments/{development,staging,production}` runs in the corresponding
  isolated AWS account. Each root has a distinct backend key and calls the
  same reviewed environment module.

Terraform never stores application secret values. It creates only Secrets
Manager containers and IAM access boundaries; an operator supplies values over
an audited, short-lived AWS session. Never pass secret values through `-var`,
`.tfvars`, plans, outputs, or CI logs. Workloads use IRSA and the Secrets Store
CSI driver to read only their assigned secret.

Commit every `.terraform.lock.hcl` file. It pins reviewed provider versions and
package checksums for reproducible local and CI execution; it contains neither
Terraform state nor secrets. Local `.terraform/` directories, backend files,
plans, state, and variable files remain ignored.

RDS Proxy has three Secrets Manager auth entries: platform runtime, market
writer, and migration-only. These are distinct PostgreSQL logins; do not reuse
one password across containers. Runtime configuration secrets hold the matching
proxy URLs, while only the migration service account can read the migration
credential.

Copy the checked-in examples to ignored local files, replace account-specific
placeholders, and bootstrap in this order:

```bash
cp infra/terraform/bootstrap/shared/terraform.tfvars.example \
  infra/terraform/bootstrap/shared/terraform.tfvars
terraform -chdir=infra/terraform/bootstrap/shared init
terraform -chdir=infra/terraform/bootstrap/shared plan -out=shared.tfplan

cp infra/terraform/environments/development/backend.hcl.example \
  infra/terraform/environments/development/backend.hcl
cp infra/terraform/environments/development/terraform.tfvars.example \
  infra/terraform/environments/development/terraform.tfvars
terraform -chdir=infra/terraform/environments/development init \
  -backend-config=backend.hcl
terraform -chdir=infra/terraform/environments/development plan \
  -out=development.tfplan
```

Apply is intentionally not wrapped in repository automation. Follow
`docs/runbooks/aws-legacy-next.md`, require plan review, and use a short-lived
federated operator session. Production uses deletion protection, multi-AZ
capacity, longer retention, required MFA, and a two-person apply gate.

The AWS foundation workflow performs non-mutating Terraform formatting and
validation plus Helm linting and rendering. After shared bootstrap, the AWS
legacy release workflow uses GitHub OIDC to publish, scan, sign, attest, and
promote immutable application images through digest-only GitOps pull requests.
