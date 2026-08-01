#!/usr/bin/env bash
set -Eeuo pipefail

started_stack=0

cleanup() {
  if [[ "$started_stack" == "1" ]]; then
    bun run db:stop
  fi
}
trap cleanup EXIT INT TERM

command -v docker >/dev/null 2>&1 || {
  echo "Docker is required for database verification." >&2
  exit 1
}

if bunx supabase status >/dev/null 2>&1; then
  echo "Using the running local Supabase stack."
else
  echo "Starting a disposable local Supabase stack."
  bun run db:start:test
  started_stack=1
fi

bun run db:reset
bunx supabase test db
