# Supabase and Cognito Migration Rehearsal

## Scope and safety

These tools export Supabase users and authoritative product rows, transform them into the Rails schema, produce Cognito identity input, load an empty target, and reconcile canonical checksums. They do not execute a production migration or call Cognito.

Run against disposable databases first. Export directories contain personal data and must use encrypted storage, restrictive permissions, a documented owner, and a deletion deadline. Never commit them.

## Rehearsal

Choose separate empty directories and database URLs. The source account must be read-only; the target must be disposable and have every Rails migration applied.

```sh
umask 077
export SOURCE_DATABASE_URL='postgres://...'
scripts/migration/export-supabase.sh /secure/path/source-export

ruby scripts/migration/transform.rb transform \
  /secure/path/source-export \
  /secure/path/transformed \
  https://project.supabase.co/auth/v1
ruby scripts/migration/transform.rb validate /secure/path/transformed

export TARGET_DATABASE_URL='postgres://...'
scripts/migration/load-target.sh /secure/path/transformed
scripts/migration/validate-target.sh /secure/path/transformed
```

The loader refuses a target containing users, favorites, reports, or usage windows. The validator compares row counts and canonical checksums after reading the target back, and the transform rejects orphaned ownership references, malformed UUIDs, unsupported states, invalid symbols, duplicate emails, and invalid usage windows.

`metric_explanations` is a rebuildable shared cache. It is archived in the transformed dataset but not loaded as authoritative data.

## Cognito limitations

`cognito_identities.jsonl` retains each legacy subject in `custom:legacy_subject` and uses the existing Rails user UUID as the migration username. Password hashes and third-party Supabase sessions are not portable. Every migrated identity is therefore marked `password_reset_required`; MFA enrollment, OAuth provider linking, verified-email policy, and notification delivery must be rehearsed separately in Phase 4.

Before cutover, verify that each Cognito subject resolves to exactly one Rails user and that legacy subjects remain queryable for reconciliation. Do not switch `AUTH_PROVIDER=cognito` until issuer, client ID, JWKS validation, reset journeys, and rollback sign-in behavior pass staging.

## Reconciliation and abort gates

Record the manifest, tool revision, start/end time, source transaction boundary, counts, checksums, exceptions, and operator. Abort on any checksum, count, owner, identity, or sampled-record mismatch. Do not repair the transformed files by hand; correct the transform or source data and repeat from a new directory.

Before final migration, freeze incompatible writes or capture a documented delta boundary. This toolset performs a single bounded load and does not provide continuous dual-write conflict resolution.

Rollback during rehearsal is to discard the isolated target database and transformed dataset. During a production window, keep Supabase authoritative until reconciliation and traffic gates pass. If an abort gate fires, route traffic back to the legacy application, preserve evidence, and discard or quarantine partial target data according to the cutover runbook; never delete the source.
