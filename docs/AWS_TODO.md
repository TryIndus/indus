# AWS follow-up work

This list tracks AWS work that is useful but not required for the current
application deployment. Promote an item into a scoped change only when its
phase is explicitly approved.

## Identity and account operations

- Replace the misleading management-account IAM username `root-user` with IAM
  Identity Center access or a clearly named administrator identity.
- Use a dedicated project-account recovery address instead of the alert-delivery
  address, and keep both addresses on the `tryindus.ca` domain.
- Complete project-account root-user recovery setup, hardware MFA, and alternate
  security, operations, and billing contacts.
- Periodically review the MFA-protected EKS administrator principals and remove
  obsolete operators.

## Security and resilience

- Move EKS operator access from individual public `/32` CIDRs to a managed VPN
  or another private administrative path, then disable the public endpoint.
- Evaluate AWS WAF managed rules and rate limits at CloudFront after normal
  traffic patterns are measured.
- Enable and review organization-level CloudTrail, GuardDuty, Security Hub, and
  AWS Config with centralized retention when the operating budget permits.
- Run scheduled Aurora and AWS Backup restore exercises and record recovery-time
  and recovery-point results.
- Add synthetic authenticated availability checks after the AWS application is
  serving traffic.

## Naming and lifecycle

- Decide whether transitional `legacy-next` names should become `app` or
  `web-app`; batch any renames because several replacements may be disruptive.
- Align the shortened `legacy` target-group names with the chosen workload name
  during that same rename.
- Tear down staging when developers do not need it and periodically verify that
  the tear-up workflow restores it successfully.

## Platform completion

- Build and deploy the first immutable application image before assigning AWS
  any Route 53 traffic weight.
- Complete authenticated smoke, accessibility, provider, rollback, and alert
  tests before increasing the AWS traffic weight.
- Retire Vercel and Supabase only in their explicitly approved revamp phases;
  remove rollback DNS and transitional credentials after the exit criteria pass.
