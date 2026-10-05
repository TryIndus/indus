# Capacity retry workflow

`.github/workflows/capacity-retry.yml` runs every six hours on `main` and can
also be dispatched manually. Its matrix is the reviewed list of pending
infrastructure size changes. Each entry supplies its own Terraform root, GitHub
Environment, AWS role and region variables, backend and tfvars secrets, backend
identity checks, resource address and type, one permitted size attribute, the
desired value, optional scheduling attributes and preflight, and retryable
provider error codes. New AWS resources and other Terraform roots can use the
same plan guard by adding a reviewed matrix entry.

For each entry, the workflow saves a targeted Terraform plan and inspects its
JSON representation. It applies the saved plan only when **exactly one** managed
resource has an in-place update, the address and type match the entry, and the
only before/after differences are the allowed size attribute reaching the
declared value and explicitly declared scheduling attributes. A no-op plan
stops quietly. Any replacement, additional resource change, or unrelated drift
fails closed. A single recognized capacity error is treated as a retryable
outcome; other apply failures fail the run.

An accepted size change can interrupt the affected service. Each target must
use a GitHub Environment whose OIDC role can update that resource without a
human MFA session. The environment must be restricted to `main` and must not
require reviewers if unattended retries are desired. Match `lock_group` to the
manual infrastructure workflow for the same Terraform state so their applies
cannot overlap. Successful applies open a GitHub issue linked to the run. Set
the optional `CAPACITY_RETRY_ASSIGNEE` variable in the target GitHub
Environment to a repository collaborator to send that person an issue
assignment notification.

The RDS target sets `apply_immediately` so the resize starts when capacity is
accepted. Its preflight rejects any existing RDS pending modifications because
AWS would apply those immediately too. Other targets can omit the preflight
when it is not relevant.

The workflow does not discover pending capacity errors automatically. Operators
add and later remove reviewed entries as infrastructure changes are requested.
Do not use it for database migrations, replacements, broad reconciliation,
destruction, or changes to multiple fields. Run `node --test
scripts/capacity/guard-plan.test.mjs` after editing the guard, then validate the
GitHub workflow with actionlint.
