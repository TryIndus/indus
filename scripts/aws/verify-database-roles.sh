#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ $# -lt 1 || $# -gt 2 || ( $# -eq 2 && "$2" != "--execute-read-only" ) ]]; then
  echo "Usage: $0 ADMIN_SECRET_JSON [--execute-read-only]" >&2
  exit 1
fi

admin_file="$1"
mode="${2:-dry-run}"
[[ -f "$admin_file" ]] || { echo "Admin secret JSON does not exist: $admin_file" >&2; exit 1; }

permissions="$(stat -f '%Lp' "$admin_file" 2>/dev/null || stat -c '%a' "$admin_file")"
[[ "$permissions" == "600" || "$permissions" == "400" ]] || {
  echo "Admin secret JSON must have mode 0600 or 0400." >&2
  exit 1
}
jq -e '(.host | type == "string" and length > 0) and (.username | type == "string" and length > 0) and (.password | type == "string" and length > 0)' "$admin_file" >/dev/null

if [[ "$mode" != "--execute-read-only" ]]; then
  echo "Dry run: would verify login attributes, memberships, schema isolation, table grants, and security-definer ownership."
  exit 0
fi

admin_password="$(jq -r '.password' "$admin_file")"
trap 'unset admin_password PGPASSWORD' EXIT
PGPASSWORD="$admin_password" psql \
  --host "$(jq -r '.host' "$admin_file")" \
  --port "$(jq -r '.port // 5432' "$admin_file")" \
  --username "$(jq -r '.username' "$admin_file")" \
  --dbname "$(jq -r '.dbname // "indus"' "$admin_file")" \
  --set ON_ERROR_STOP=1 \
  --no-psqlrc \
  --file "$root_dir/scripts/aws/verify-database-roles.sql"
