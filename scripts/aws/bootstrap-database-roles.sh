#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ $# -lt 4 || $# -gt 5 || ( $# -eq 5 && "$5" != "--apply" ) ]]; then
  echo "Usage: $0 ADMIN_SECRET_JSON PLATFORM_SECRET_JSON MARKET_SECRET_JSON MIGRATION_SECRET_JSON [--apply]" >&2
  exit 1
fi

for command in jq psql; do
  command -v "$command" >/dev/null 2>&1 || { echo "Missing required command: $command" >&2; exit 1; }
done

admin_file="$1"
platform_file="$2"
market_file="$3"
migration_file="$4"
mode="${5:-dry-run}"

secure_json_file() {
  local file="$1"
  [[ -f "$file" ]] || { echo "Secret JSON does not exist: $file" >&2; exit 1; }
  local permissions
  permissions="$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file")"
  [[ "$permissions" == "600" || "$permissions" == "400" ]] || {
    echo "Secret JSON must have mode 0600 or 0400: $file" >&2
    exit 1
  }
}

for file in "$admin_file" "$platform_file" "$market_file" "$migration_file"; do
  secure_json_file "$file"
done

jq -e '.host | type == "string" and length > 0' "$admin_file" >/dev/null
jq -e '.username | type == "string" and length > 0' "$admin_file" >/dev/null
jq -e '.password | type == "string" and length > 0' "$admin_file" >/dev/null
jq -e '.username == "indus_platform" and (.password | type == "string" and length >= 24)' "$platform_file" >/dev/null
jq -e '.username == "indus_market_writer" and (.password | type == "string" and length >= 24)' "$market_file" >/dev/null
jq -e '.username == "indus_migrator" and (.password | type == "string" and length >= 24)' "$migration_file" >/dev/null

if [[ "$mode" != "--apply" ]]; then
  echo "Dry run: validated protected credential files for indus_platform, indus_market_writer, and indus_migrator."
  echo "Re-run with --apply from an approved federated session to change database roles."
  exit 0
fi

admin_host="$(jq -r '.host' "$admin_file")"
admin_port="$(jq -r '.port // 5432' "$admin_file")"
admin_database="$(jq -r '.dbname // "indus"' "$admin_file")"
admin_username="$(jq -r '.username' "$admin_file")"
admin_password="$(jq -r '.password' "$admin_file")"
platform_password="$(jq -r '.password' "$platform_file")"
market_password="$(jq -r '.password' "$market_file")"
migration_password="$(jq -r '.password' "$migration_file")"

trap 'unset admin_password platform_password market_password migration_password PGPASSWORD INDUS_PLATFORM_DB_PASSWORD INDUS_MARKET_DB_PASSWORD INDUS_MIGRATION_DB_PASSWORD' EXIT

PGPASSWORD="$admin_password" \
INDUS_PLATFORM_DB_PASSWORD="$platform_password" \
INDUS_MARKET_DB_PASSWORD="$market_password" \
INDUS_MIGRATION_DB_PASSWORD="$migration_password" \
psql \
  --host "$admin_host" \
  --port "$admin_port" \
  --username "$admin_username" \
  --dbname "$admin_database" \
  --set ON_ERROR_STOP=1 \
  --no-psqlrc \
  --file "$root_dir/scripts/aws/database-roles.sql"

echo "Database login, owner, and default-privilege roles were reconciled. Run migrations, then the read-only role verifier."
