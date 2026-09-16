# GitOps delivery

Terraform creates the cluster and prints the non-secret values consumed here.
Replace each checked-in `replace-*` placeholder in the corresponding control
plane and workload values before bootstrapping that environment. Secret values
are never stored here.

Argo CD owns add-ons, admission policies, and application workloads. The
`AWS legacy release` GitHub Actions workflow publishes a scanned, signed,
immutable image and opens a promotion pull request; it does not call Kubernetes
or mutate a deployment. Merging that pull request lets Argo CD reconcile the
exact digest. Promotion order is staging, then production.

The only imperative bootstrap is the pinned Argo CD installation described in
`docs/runbooks/aws-bootstrap.md`. After the root application is submitted,
self-healing and pruning are declarative. Do not enable automated sync in a
production cluster until placeholders, alert delivery, and rollback access have
been verified.
