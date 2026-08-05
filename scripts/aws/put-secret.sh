#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 ENVIRONMENT WORKLOAD JSON_FILE [--apply]" >&2
  exit 2
}

[[ $# -ge 3 && $# -le 4 ]] || usage
environment="$1"
workload="$2"
json_file="$3"
mode="${4:-}"

[[ "$environment" =~ ^(development|staging|production)$ ]] || usage
[[ "$workload" =~ ^(database-platform|database-market|database-migration|platform-api|market-data|research-worker)$ ]] || usage
[[ -f "$json_file" ]] || { echo "Secret JSON file does not exist." >&2; exit 2; }

permissions="$(stat -f '%Lp' "$json_file" 2>/dev/null || stat -c '%a' "$json_file")"
[[ "$permissions" == "600" || "$permissions" == "400" ]] || {
  echo "Secret JSON file must be readable only by its owner (chmod 600)." >&2
  exit 2
}
jq -e 'type == "object" and length > 0 and all(.[]; type == "string" and length > 0)' "$json_file" >/dev/null

case "$workload" in
  database-platform)
    jq -e '.username == "indus_platform" and has("password")' "$json_file" >/dev/null
    ;;
  database-market)
    jq -e '.username == "indus_market_writer" and has("password")' "$json_file" >/dev/null
    ;;
  database-migration)
    jq -e '.username == "indus_migrator" and has("password") and has("DATABASE_URL")' "$json_file" >/dev/null
    ;;
esac

secret_id="indus-${environment}/${workload}"
if [[ "$mode" != "--apply" ]]; then
  echo "Dry run: would create a new version of Secrets Manager secret $secret_id from $json_file."
  echo "No secret value was read by AWS and no external state changed. Re-run with --apply after peer approval."
  exit 0
fi

command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required." >&2; exit 1; }
aws secretsmanager put-secret-value \
  --secret-id "$secret_id" \
  --secret-string "file://${json_file}" \
  --query '{ARN:ARN,VersionId:VersionId,VersionStages:VersionStages}'
echo "Secret version created. Securely delete the local JSON file according to the secret-management runbook."
