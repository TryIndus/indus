#!/usr/bin/env bash
set -Eeuo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export COMPOSE_PROJECT_NAME="indus-validation-${GITHUB_RUN_ID:-local}"
compose=(docker compose -f "$repo_root/compose.yaml" -f "$repo_root/compose.workflows.yaml" --profile application --profile distributed)
topic="platform-validation-${GITHUB_RUN_ID:-local}"
payload="indus-platform-validation-${GITHUB_RUN_ID:-local}"

cleanup() {
  "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${compose[@]}" config --quiet
"${compose[@]}" up --detach --wait postgres redis redpanda platform-api market-data web

curl --fail --silent http://127.0.0.1:13000/healthz >/dev/null
curl --fail --silent http://127.0.0.1:13000/readyz >/dev/null
curl --fail --silent http://127.0.0.1:18081/health/live >/dev/null
curl --fail --silent http://127.0.0.1:18081/health/ready >/dev/null
curl --fail --silent http://127.0.0.1:14173/ >/dev/null

"${compose[@]}" exec -T postgres psql -U indus -d indus_development -v ON_ERROR_STOP=1 \
  -c "CREATE TABLE platform_validation (value text NOT NULL); INSERT INTO platform_validation VALUES ('$payload');" >/dev/null
"${compose[@]}" exec -T redis redis-cli SET platform-validation "$payload" >/dev/null
"${compose[@]}" exec -T redpanda rpk topic create "$topic" --brokers redpanda:9092 >/dev/null
printf '%s\n' "$payload" | "${compose[@]}" exec -T redpanda \
  rpk topic produce "$topic" --brokers redpanda:9092 >/dev/null

"${compose[@]}" restart postgres redis redpanda >/dev/null
"${compose[@]}" up --detach --wait postgres redis redpanda >/dev/null

"${compose[@]}" exec -T postgres psql -U indus -d indus_development -At \
  -c "SELECT value FROM platform_validation" | grep --fixed-strings --line-regexp "$payload" >/dev/null
"${compose[@]}" exec -T redis redis-cli GET platform-validation \
  | grep --fixed-strings --line-regexp "$payload" >/dev/null
timeout 30 "${compose[@]}" exec -T redpanda \
  rpk topic consume "$topic" --num 1 --offset start --brokers redpanda:9092 \
  | grep --fixed-strings "$payload" >/dev/null

"${compose[@]}" restart platform-api market-data >/dev/null
"${compose[@]}" up --detach --wait platform-api market-data >/dev/null
curl --fail --silent http://127.0.0.1:13000/readyz >/dev/null
curl --fail --silent http://127.0.0.1:18081/health/ready >/dev/null
