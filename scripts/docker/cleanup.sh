#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/docker/cleanup.sh [--status] [--force]

  --status  Show Docker's current disk usage without deleting anything.
  --force   Skip confirmation before deleting Indus Docker resources.

Without options, the script permanently removes Docker containers, images,
volumes, and networks identifiable as Indus. Other projects are not pruned.
EOF
}

status_only=false
force=false

for argument in "$@"; do
  case "$argument" in
    --status) status_only=true ;;
    --force) force=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $argument" >&2; usage >&2; exit 2 ;;
  esac
done

if $status_only && $force; then
  echo "--status cannot be combined with --force." >&2
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

echo "Docker disk usage:"
docker system df --verbose

if $status_only; then
  exit 0
fi

is_indus_project() {
  case "$1" in
    indus|indus-db-tests|indus-auth-tests) return 0 ;;
    *) return 1 ;;
  esac
}

is_indus_name() {
  case "$1" in
    indus|indus-*|indus_*|/indus|/indus-*|/indus_*) return 0 ;;
    *) return 1 ;;
  esac
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

is_indus_image() {
  local image_id="$1"
  local image_source
  local image_title
  local repository
  local repo_tags

  image_source="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.source"}}' "$image_id" 2>/dev/null || true)"
  image_title="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.title"}}' "$image_id" 2>/dev/null || true)"
  if [[ "$image_source" == "https://github.com/TryIndus/indus" || "$image_title" == "indus" ]]; then
    return 0
  fi

  repo_tags="$(docker image inspect --format '{{join .RepoTags " "}}' "$image_id" 2>/dev/null || true)"
  for repository in $repo_tags; do
    repository="${repository%:*}"
    is_indus_name "${repository##*/}" && return 0
  done
  return 1
}

declare -a containers=()
declare -a images=()
declare -a volumes=()
declare -a networks=()

while IFS= read -r resource_id; do
  [[ -n "$resource_id" ]] || continue
  project_id="$(docker inspect --format '{{index .Config.Labels "com.supabase.cli.project"}}' "$resource_id" 2>/dev/null || true)"
  if [[ -z "$project_id" || "$project_id" == "<no value>" ]]; then
    project_id="$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$resource_id" 2>/dev/null || true)"
  fi
  resource_name="$(docker inspect --format '{{.Name}}' "$resource_id")"
  image_id="$(docker inspect --format '{{.Image}}' "$resource_id")"
  if is_indus_project "$project_id" || is_indus_name "$resource_name" || is_indus_image "$image_id"; then
    containers+=("$resource_id")
  fi
done < <(docker ps --all --quiet)

while IFS= read -r resource_id; do
  [[ -n "$resource_id" ]] || continue
  project_id="$(resource_project_id volume "$resource_id")"
  if is_indus_project "$project_id" || is_indus_name "$resource_id"; then
    volumes+=("$resource_id")
  fi
done < <(docker volume ls --quiet)

while IFS= read -r resource_id; do
  [[ -n "$resource_id" ]] || continue
  project_id="$(resource_project_id network "$resource_id")"
  resource_name="$(docker network inspect --format '{{.Name}}' "$resource_id")"
  if is_indus_project "$project_id" || is_indus_name "$resource_name"; then
    networks+=("$resource_id")
  fi
done < <(docker network ls --quiet)

while IFS= read -r resource_id; do
  [[ -n "$resource_id" ]] || continue
  is_indus_image "$resource_id" && images+=("$resource_id")
done < <(docker image ls --all --quiet | sort -u)

echo "Indus resources selected: ${#containers[@]} containers, ${#images[@]} images, ${#volumes[@]} volumes, ${#networks[@]} networks."
if ((${#containers[@]} + ${#images[@]} + ${#volumes[@]} + ${#networks[@]} == 0)); then
  exit 0
fi

if ! $force; then
  read -r -p "Permanently delete every selected Indus Docker resource? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

((${#containers[@]} == 0)) || docker rm --force "${containers[@]}" >/dev/null
((${#volumes[@]} == 0)) || docker volume rm "${volumes[@]}" >/dev/null
((${#networks[@]} == 0)) || docker network rm "${networks[@]}" >/dev/null
((${#images[@]} == 0)) || docker image rm --force "${images[@]}" >/dev/null

echo "Indus Docker cleanup complete."
docker system df
