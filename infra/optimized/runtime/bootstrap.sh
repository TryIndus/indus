#!/usr/bin/env bash
set -euo pipefail

# This cloud-init script intentionally contains no secret values. The first
# release is installed by the optimized deployment workflow through SSM.
dnf upgrade --refresh -y
dnf install -y docker
systemctl enable --now docker
mkdir -p /opt/indus-optimized /run/indus-optimized
chmod 0700 /run/indus-optimized
