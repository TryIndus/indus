#!/usr/bin/env bash
set -euo pipefail

# This cloud-init script intentionally contains no secret values. The first
# release is installed by the optimized deployment workflow through SSM.
dnf install -y docker amazon-cloudwatch-agent
install -d -m 0755 /etc/docker
cat > /etc/docker/daemon.json <<'JSON'
{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"}}
JSON
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
cat > /opt/aws/amazon-cloudwatch-agent/etc/indus-optimized.json <<'JSON'
{
  "agent": {"metrics_collection_interval": 60},
  "metrics": {
    "namespace": "Indus/Optimized",
    "append_dimensions": {"InstanceId": "${aws:InstanceId}"},
    "aggregation_dimensions": [["InstanceId"]],
    "metrics_collected": {
      "mem": {"measurement": ["mem_used_percent"]},
      "disk": {"measurement": ["used_percent"], "resources": ["/"], "ignore_file_system_types": ["sysfs", "devtmpfs", "tmpfs"]}
    }
  }
}
JSON
# The release installer starts the agent only when the optimized monitoring
# setting is enabled. Docker logs remain bounded on the host either way.
mkdir -p /opt/indus-optimized /run/indus-optimized
chmod 0700 /run/indus-optimized
