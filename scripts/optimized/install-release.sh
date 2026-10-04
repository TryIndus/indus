#!/usr/bin/env bash
set -euo pipefail

release_dir=/opt/indus-optimized
runtime_dir=/run/indus-optimized
release_file="${1:?release manifest path is required}"
region="${AWS_REGION:?AWS_REGION is required}"

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
for secret in platform-api market-data research-worker; do
  arn_file="$release_dir/${secret}.secret-arn"
  [[ -f "$arn_file" ]] || { echo "missing secret ARN mapping for $secret" >&2; exit 1; }
  aws secretsmanager get-secret-value --region "$region" --secret-id "$(<"$arn_file")" --query SecretString --output text > "$runtime_dir/$secret.env"
  chmod 0600 "$runtime_dir/$secret.env"
done

registry="$(grep '^PLATFORM_API_IMAGE=' "$release_file" | cut -d= -f2- | cut -d/ -f1)"
aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$registry"
install -m 0644 "$release_file" "$release_dir/release.env"
install -m 0644 "$release_dir/indus-optimized.service" /etc/systemd/system/indus-optimized.service
systemctl daemon-reload
docker compose --project-directory "$release_dir" --env-file "$release_dir/release.env" config >/dev/null
docker compose --project-directory "$release_dir" --env-file "$release_dir/release.env" pull
systemctl enable --now indus-optimized.service
