#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/docker/cleanup.sh [--status] [--all-unused] [--volumes] [--force]

  --status       Show Docker's current disk usage without deleting anything.
  --all-unused   Also remove unused tagged images; asks for confirmation.
  --volumes      Also remove unused volumes; asks for confirmation.
  --force        Do not ask before --all-unused or --volumes cleanup.

Without options, this removes stopped containers, unused networks, dangling
images, and unused BuildKit cache. It never removes volumes by default.
EOF
}

status_only=false
all_unused=false
volumes=false
force=false

for argument in "$@"; do
  case "$argument" in
    --status) status_only=true ;;
    --all-unused) all_unused=true ;;
    --volumes) volumes=true ;;
    --force) force=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $argument" >&2; usage >&2; exit 2 ;;
  esac
done

if $status_only && ($all_unused || $volumes || $force); then
  echo "--status cannot be combined with cleanup options." >&2
  exit 2
fi

command -v docker >/dev/null 2>&1 || {
  echo "Docker is not installed or is not on PATH." >&2
  exit 1
}

docker info >/dev/null 2>&1 || {
  echo "The Docker daemon is not available. Start Docker Desktop and retry." >&2
  exit 1
}

echo "Docker disk usage before cleanup:"
docker system df --verbose

if $status_only; then
  exit 0
fi

if ($all_unused || $volumes) && ! $force; then
  read -r -p "This can remove unused Docker data from every local project. Continue? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

echo "Removing stopped containers, unused networks, dangling images, and unused BuildKit cache."
docker container prune --force
docker network prune --force
docker image prune --force
docker builder prune --force

if $all_unused; then
  echo "Removing unused tagged images."
  docker image prune --all --force
fi

if $volumes; then
  echo "Removing unused volumes."
  docker volume prune --force
fi

echo "Docker disk usage after cleanup:"
docker system df --verbose
