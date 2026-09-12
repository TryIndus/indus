#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
Usage: bash scripts/docker/cleanup.sh [--status] [--indus] [--all-unused] [--volumes] [--force]

  --status       Show Docker's current disk usage without deleting anything.
  --indus        Permanently remove local Indus Supabase and test-stack data.
  --all-unused   Also remove unused tagged images from every local project.
  --volumes      Also remove unused volumes from every local project.
  --force        Do not ask before destructive cleanup.

Without options, this removes stopped containers, unused networks, dangling
images, and unused BuildKit cache. It never removes volumes by default.
EOF
}

status_only=false
indus_purge=false
all_unused=false
volumes=false
force=false

for argument in "$@"; do
  case "$argument" in
    --status) status_only=true ;;
    --indus) indus_purge=true ;;
    --all-unused) all_unused=true ;;
    --volumes) volumes=true ;;
    --force) force=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $argument" >&2; usage >&2; exit 2 ;;
  esac
done

if $status_only && ($indus_purge || $all_unused || $volumes || $force); then
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

is_indus_project() {
  case "$1" in
    indus|indus-db-tests|indus-auth-tests) return 0 ;;
    *) return 1 ;;
  esac
}

is_indus_resource() {
  local resource_name="$1"
  local project_id="$2"
  is_indus_project "$project_id" || [[ "$resource_name" == indus_* || "$resource_name" == indus-* || "$resource_name" == /indus_* || "$resource_name" == /indus-* ]]
}

resource_project_id() {
  local resource_type="$1"
  local resource_id="$2"
  local project_id

  project_id="$(docker "$resource_type" inspect --format '{{index .Labels "com.supabase.cli.project"}}' "$resource_id" 2>/dev/null || true)"
  if [[ -z "$project_id" || "$project_id" == "<no value>" ]]; then
    project_id="$(docker "$resource_type" inspect --format '{{index .Labels "com.docker.compose.project"}}' "$resource_id" 2>/dev/null || true)"
  fi
  printf '%s' "$project_id"
}

confirm_destructive_cleanup() {
  $force && return 0
  read -r -p "This permanently removes Docker data. Continue? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
}

purge_indus_resources() {
  echo "Stopping the local Indus Supabase stack without a backup."
  if command -v bunx >/dev/null 2>&1; then
    bunx supabase stop --workdir "$repo_root" --no-backup >/dev/null 2>&1 || true
  else
    echo "bunx is unavailable; removing identifiable residual Indus Docker resources directly." >&2
  fi

  declare -a containers=()
  while IFS= read -r resource_id; do
    [[ -n "$resource_id" ]] || continue
    project_id="$(docker inspect --format '{{index .Config.Labels "com.supabase.cli.project"}}' "$resource_id" 2>/dev/null || true)"
    if [[ -z "$project_id" || "$project_id" == "<no value>" ]]; then
      project_id="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$resource_id" 2>/dev/null || true)"
    fi
    resource_name="$(docker inspect --format '{{.Name}}' "$resource_id")"
    is_indus_resource "$resource_name" "$project_id" && containers+=("$resource_id")
  done < <(docker ps --all --quiet)
  if ((${#containers[@]})); then
    echo "Removing Indus Supabase and test-stack containers."
    docker rm --force "${containers[@]}" >/dev/null
  fi

  declare -a volumes_to_remove=()
  while IFS= read -r resource_id; do
    [[ -n "$resource_id" ]] || continue
    project_id="$(resource_project_id volume "$resource_id")"
    is_indus_resource "$resource_id" "$project_id" && volumes_to_remove+=("$resource_id")
  done < <(docker volume ls --quiet)
  if ((${#volumes_to_remove[@]})); then
    echo "Removing Indus Supabase and test-stack volumes."
    docker volume rm "${volumes_to_remove[@]}" >/dev/null
  fi

  declare -a networks=()
  while IFS= read -r resource_id; do
    [[ -n "$resource_id" ]] || continue
    project_id="$(resource_project_id network "$resource_id")"
    resource_name="$(docker network inspect --format '{{.Name}}' "$resource_id")"
    is_indus_resource "$resource_name" "$project_id" && networks+=("$resource_id")
  done < <(docker network ls --quiet)
  if ((${#networks[@]})); then
    echo "Removing Indus Supabase and test-stack networks."
    docker network rm "${networks[@]}" >/dev/null 2>&1 || true
  fi
}

echo "Docker disk usage before cleanup:"
docker system df --verbose

if $status_only; then
  exit 0
fi

if $indus_purge || $all_unused || $volumes; then
  confirm_destructive_cleanup
fi

if $indus_purge; then
  purge_indus_resources
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
