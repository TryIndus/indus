# Immutable build and promotion

`release-images.yml` builds each image once on `main`, pushes to immutable ECR,
generates an SPDX SBOM, rejects unresolved high/critical findings, and creates
keyless Cosign signatures and attestations. The build role can publish; the
separate promotion role can only pull and is trusted exclusively by protected
GitHub environment subjects.

Start `promote-images.yml` with the three exact `@sha256` references and their
40-character source commit. It verifies repository names, signatures, issuer,
workflow identity, and SBOM attestations. Staging must match development
exactly; production must match staging exactly. The workflow opens a PR and
never calls Kubernetes. Argo CD deploys only after review and merge.

Before approval, verify required CI, provenance, image scan, migration job,
deployment health, SLO dashboard, and rollback digest. Production uses a
minimum 30-minute canary observation and the traffic gates in
`migration-cutover.md`. Rollback changes GitOps references back to the prior
signed digest; never rebuild an old tag.
