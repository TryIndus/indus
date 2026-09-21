#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_project="${E2E_COMPOSE_PROJECT_NAME:-indus-web-e2e-$$}"
compose_files=(-f "$repository_root/compose.yaml" -f "$repository_root/compose.e2e.yaml")
export E2E_API_PORT="${E2E_API_PORT:-13100}"

cleanup() {
  docker compose --project-name "$compose_project" --profile application "${compose_files[@]}" \
    down --volumes --remove-orphans
}
trap cleanup EXIT INT TERM

docker compose --project-name "$compose_project" "${compose_files[@]}" \
  up --build --detach --wait postgres redis platform-api

cd "$repository_root/apps/web"
bunx playwright test "$@"
