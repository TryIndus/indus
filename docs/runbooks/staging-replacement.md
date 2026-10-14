# Dormant staging replacement configuration

This file records the retained staging replacement configuration. Staging is
not a prerequisite for merging to `main`. Deployment workflows on `main` do
not support publishing a staging deployment; inspect AWS and GitHub separately
to determine whether any older staging resources or workflow entry points
still exist.

To reactivate it, make a reviewed infrastructure change that creates or updates
the staging branch and workflow boundary, GitHub Environment and OIDC trust,
private Terraform configuration, GitOps bootstrap, and image publication
path. Then validate the newly provisioned environment before using it for
release evidence.

If staging is deliberately reactivated, configure these public GitHub staging
Environment variables before dispatch:

- `WEB_ORIGIN`: the HTTPS public origin, without a trailing slash.
- `COGNITO_AUTHORITY`: the Cognito user-pool issuer URL
  (`https://cognito-idp.us-east-1.amazonaws.com/<pool-id>`), used to identify the user pool.
- `COGNITO_CLIENT_ID`: the public web client ID.

Existing repository build-role and region variables are also required.
These values are public browser configuration; never supply provider keys here.

All four images must pass vulnerability scans before any image is pushed. Each
published digest receives a signature and SBOM attestation. Publishing must not
enable Argo applications, apply infrastructure, migrate databases, or change
traffic. Partial publication may leave unused immutable images; a failed
publication must not update deployment references.

Before activating the platform, provision its stateful dependencies, workload
roles, target groups, secrets, and private configuration. Verify a database
backup and approved rollback point before synchronizing migration jobs.
Retain previous verified digests for image rollback and use forward migrations
or restoration to a new database for data recovery. Production promotion,
Supabase migration, and legacy retirement require separate approval.
