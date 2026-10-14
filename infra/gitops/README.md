# GitOps delivery

Terraform creates the cluster and prints the non-secret values consumed here.
Replace each checked-in `replace-*` placeholder in the corresponding control
plane and workload values before bootstrapping that environment. Secret values
are never stored here.

Argo CD owns add-ons, admission policies, and application workloads. The active
production cluster watches `main`; `./bin/indus deploy app production` publishes
immutable images and opens a digest-only pull request against that deployment
branch. Argo CD reconciles the exact merged digest. The checked-in staging
values are dormant reference material; inspect AWS and any older staging
branch before assuming its cluster or deployment path has been retired.

The only imperative bootstrap is the pinned Argo CD installation described in
`docs/runbooks/aws-bootstrap.md`. After the root application is submitted,
self-healing and pruning are declarative. Do not enable automated sync in a
production cluster until placeholders, alert delivery, and rollback access have
been verified.
