#!/usr/bin/env bash
set -euo pipefail

release_dir=/opt/indus-optimized
runtime_dir=/run/indus-optimized
release_file="${1:?release manifest path is required}"
region="${AWS_REGION:?AWS_REGION is required}"
umask 077

[[ "$release_file" == "$release_dir"/* ]] || { echo "release manifest must be under $release_dir" >&2; exit 1; }
for key in PLATFORM_API_IMAGE RESEARCH_WORKER_IMAGE MARKET_DATA_IMAGE WEB_IMAGE INDUS_HOSTNAME; do
  value="$(grep -E "^${key}=" "$release_file" | cut -d= -f2-)"
  [[ -n "$value" && "$value" != replace-* ]] || { echo "missing $key" >&2; exit 1; }
done
for key in PLATFORM_API_IMAGE RESEARCH_WORKER_IMAGE MARKET_DATA_IMAGE WEB_IMAGE; do
  value="$(grep -E "^${key}=" "$release_file" | cut -d= -f2-)"
  [[ "$value" =~ @sha256:[0-9a-f]{64}$ ]] || { echo "$key must be digest pinned" >&2; exit 1; }
done

install -d -m 0700 "$runtime_dir"
available_kib="$(df -Pk "$release_dir" | awk 'NR == 2 { print $4 }')"
[[ "$available_kib" =~ ^[0-9]+$ && "$available_kib" -ge 5242880 ]] || { echo "need at least 5 GiB free disk" >&2; exit 1; }
memory_kib="$(awk '/MemTotal:/ { print $2 }' /proc/meminfo)"
[[ "$memory_kib" =~ ^[0-9]+$ && "$memory_kib" -ge 3670016 ]] || { echo "need at least 3.5 GiB memory" >&2; exit 1; }
refresh_secrets() {
  for secret in platform-api market-data research-worker; do
    arn_file="$release_dir/${secret}.secret-arn"
    [[ -f "$arn_file" ]] || { echo "missing secret ARN mapping for $secret" >&2; exit 1; }
    temporary_file="$runtime_dir/$secret.env.next"
    aws secretsmanager get-secret-value --region "$region" --secret-id "$(<"$arn_file")" --query SecretString --output text > "$temporary_file"
    [[ -s "$temporary_file" ]] || { echo "empty runtime secret for $secret" >&2; exit 1; }
    chmod 0600 "$temporary_file"
    mv "$temporary_file" "$runtime_dir/$secret.env"
  done
}
refresh_secrets
if [[ "${2:-}" == "--refresh-secrets" ]]; then
  exit 0
fi

registry="$(grep '^PLATFORM_API_IMAGE=' "$release_file" | cut -d= -f2- | cut -d/ -f1)"
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
install -m 0600 "$release_file" "$release_dir/release.env"
install -m 0644 "$release_dir/indus-optimized.service" /etc/systemd/system/indus-optimized.service
systemctl daemon-reload
docker compose --project-directory "$release_dir" --env-file "$release_dir/release.env" config >/dev/null
docker compose --project-directory "$release_dir" --env-file "$release_dir/release.env" pull
systemctl enable indus-optimized.service
systemctl restart indus-optimized.service
ready=false
for attempt in {1..60}; do
  if docker compose --project-directory "$release_dir" --env-file "$release_dir/release.env" ps --status running --services | grep -qx web-proxy; then
    ready=true
    break
  fi
  sleep 5
done
if [[ "$ready" != true ]]; then
  echo "optimized release did not start the web proxy" >&2
  if [[ -f "$release_dir/previous-release.env" ]]; then
    install -m 0600 "$release_dir/previous-release.env" "$release_dir/release.env"
    systemctl restart indus-optimized.service
  fi
  exit 1
fi
