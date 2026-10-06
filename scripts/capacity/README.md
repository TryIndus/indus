# Capacity retry workflow

`.github/workflows/capacity-retry.yml` runs every twelve hours on `main` and can
also be dispatched manually. Its matrix is the reviewed list of pending
infrastructure size changes. Each entry supplies its own Terraform root, GitHub
Environment, AWS role and region variables, backend and tfvars secrets, backend
identity checks, resource address and type, one permitted size attribute, the
desired value, optional scheduling attributes and preflight, and retryable
provider error codes. The configured production entry currently targets RDS.
The guard is service-agnostic: its tests also exercise an EC2 `instance_type`
update. New AWS resources and other Terraform roots can use it by adding a
reviewed matrix entry with access to the relevant Terraform state.

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
cannot overlap. Once a target reaches its desired size, the workflow ensures one
GitHub issue exists for that target and desired value. A later no-op run retries
notification if issue creation failed after a successful apply. Set
the optional `CAPACITY_RETRY_ASSIGNEE` variable in the target GitHub
Environment to a repository collaborator to send that person an issue
assignment notification.

The RDS target sets `apply_immediately` so the resize starts when capacity is
accepted. Its preflight rejects any existing RDS pending modifications because
AWS would apply those immediately too. Other targets can omit the preflight
when it is not relevant.

The workflow does not discover pending capacity errors automatically. Operators
add and later remove reviewed entries as infrastructure changes are requested.
It supports a single Terraform-managed resource whose resize plans as an
in-place update. Resources that require replacement, capacity reservations,
multi-resource changes, or asynchronous capacity checks need a separate
reviewed adapter; adding their names to the matrix alone is insufficient.
Do not use it for database migrations, broad reconciliation, or destruction.
Run `node --test scripts/capacity/*.test.mjs` after editing the workflow, then validate the
GitHub workflow with actionlint.
