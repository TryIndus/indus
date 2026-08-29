# Database identity bootstrap and verification

Aurora has three login identities. `indus_platform` serves Rails API, Sidekiq,
outbox, report consumers, and research workflows. `indus_market_writer` serves
only the Rust market-data runtime. `indus_migrator` is a non-inheriting member
of the no-login `indus_platform_owner` and `indus_market_owner` roles and is
available only to Argo CD migration hooks.

The platform owner controls `public`; the market owner controls `market_data`.
Runtime roles receive DML and sequence privileges through owner-specific
default privileges. The market maintenance functions are security definers
owned by `indus_market_owner`, so the writer can create partitions and apply
retention without receiving schema `CREATE`. Neither runtime role has access to
the other schema.

## Prepare protected inputs

Export the AWS-managed Aurora master secret to a temporary JSON file without
printing it. Create three independent password values of at least 24 characters
in files whose JSON `username` values are respectively `indus_platform`,
`indus_market_writer`, and `indus_migrator`. Set every file to mode `0600`.
Secret values must not enter Terraform variables, plans, shell arguments, or
operator logs.

Preview, then execute only from an approved federated session and maintenance
window:

```bash
scripts/aws/bootstrap-database-roles.sh /secure/admin.json \
  /secure/platform.json /secure/market.json /secure/migration.json
scripts/aws/bootstrap-database-roles.sh /secure/admin.json \
  /secure/platform.json /secure/market.json /secure/migration.json --apply
```

Populate the three matching proxy secrets with those credential documents.
Add `DATABASE_URL` to the migration document before upload; it connects as
`indus_migrator` through RDS Proxy with TLS. Populate runtime secrets according
to `secret-management.md`. Delete protected temporary copies through the
approved secure-file process after versions and audit records are confirmed.

## Migrate and prove isolation

Argo runs the Rails and Rust migration jobs with the migration credential, an
explicit owner role, and an owner-specific search path. SQLx therefore creates
its migration history in `market_data`, not `public`. Runtime pods never run
migrations. After both hooks
succeed, preview and run the read-only verifier:

```bash
scripts/aws/verify-database-roles.sh /secure/admin.json
scripts/aws/verify-database-roles.sh /secure/admin.json --execute-read-only
```

The verifier fails if a login is privileged or inheriting, memberships are
missing, either runtime can use the other schema, the market writer can access
a platform table, or market maintenance functions are not owner-controlled
security definers. Also test one authenticated API read/write and one fixture
market event before promotion.

For offline verification, run `scripts/aws/test-database-roles.sh` with Ruby
3.4, PostgreSQL 17, and the locked Rails/Rust dependencies installed. It creates
and removes a disposable local cluster, runs both real migration stacks, proves
SQLx history stays in `market_data`, exercises partition maintenance, and
asserts both cross-schema reads fail.

## Rollback and rotation

Do not grant an owner role to a runtime identity to recover from a migration
failure. Stop promotion, retain the failed hook logs, and ship a forward
migration with the existing migration identity. For credential rotation,
change and verify only one login at a time, retain the prior Secrets Manager
version until fresh connections succeed, and revoke it after the observation
window. A compromised market credential is contained to `market_data`; a
compromised platform credential cannot read or mutate market tables.
