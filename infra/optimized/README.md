# Optimized AWS profile

`infra/optimized` is an independent low-cost Indus deployment profile. The
existing `infra/terraform` tree remains the **main** profile and is not read,
renamed, or modified by this tree.

Optimized has a separate Terraform bootstrap, backend, IAM roles, ECR
repositories, VPC, EC2 host, standard RDS PostgreSQL database, S3 artifact
bucket, Cognito pool, secrets, and deployment workflow. It never uses a
Terraform remote-state reference to main.

The runtime is deliberately single-host and single-AZ: one `t3a.medium`
starting EC2 candidate, local persistent Valkey, and one `db.t4g.small`
starting RDS candidate. The database subnet group includes a second empty
subnet in a second AZ because RDS requires it; it does not create a standby.
There is no EKS, Aurora, RDS Proxy, MSK, ElastiCache, ALB, CloudFront, or NAT
gateway.

Bootstrap starts with local state because it creates the backend bucket. After
an operator has reviewed and applied it, migrate bootstrap state to the bucket
using a reviewed `terraform init -migrate-state`; configure the environment
backend from `environment/backend.hcl.example`. Keep all real backend and
variable files ignored.

See [the optimized AWS runbook](../../docs/runbooks/optimized-aws.md) for
provisioning, release, migration, recovery, and cost details.
Use the [cost worksheet](COSTS.md) with current regional pricing and measured
usage before any activation decision.
