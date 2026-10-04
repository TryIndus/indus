#!/usr/bin/env bash
set -euo pipefail

# This cloud-init script intentionally contains no secret values. The first
# release is installed by the optimized deployment workflow through SSM.
dnf install -y docker
compose_version=v5.5.0
compose_sha256=c57ab918abd5b05ca7e7d0f275875dd1330a695074f309dc9eab1b49efafcd4b
install -d -m 0755 /usr/local/lib/docker/cli-plugins
curl --fail --location --silent --show-error \
  "https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-linux-x86_64" \
  --output /usr/local/lib/docker/cli-plugins/docker-compose
printf '%s  %s\n' "$compose_sha256" /usr/local/lib/docker/cli-plugins/docker-compose | sha256sum --check
chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose
systemctl enable --now docker
docker compose version
mkdir -p /opt/indus-optimized /run/indus-optimized
chmod 0700 /run/indus-optimized
