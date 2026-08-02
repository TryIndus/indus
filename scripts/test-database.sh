#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/indus-db-test.XXXXXX)"

cleanup() {
  bunx supabase stop --workdir "$test_root" --no-backup >/dev/null 2>&1 || true
  case "$test_root" in
    /tmp/indus-db-test.*) rm -r "$test_root" ;;
    *) echo "Refusing to remove unexpected test path: $test_root" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

command -v docker >/dev/null 2>&1 || {
  echo "Docker is required for database verification." >&2
  exit 1
}

docker info >/dev/null 2>&1 || {
  echo "The Docker daemon is not available." >&2
  exit 1
}

mkdir -p "$test_root/supabase"
cp "$repo_root/supabase/config.test.toml" "$test_root/supabase/config.toml"
cp -R "$repo_root/supabase/migrations" "$test_root/supabase/migrations"
cp -R "$repo_root/supabase/tests" "$test_root/supabase/tests"

echo "Starting isolated Supabase database verification."
bunx supabase start --workdir "$test_root" \
  -x edge-runtime,gotrue,imgproxy,kong,logflare,mailpit,postgres-meta,postgrest,realtime,storage-api,studio,supavisor,vector
bunx supabase db reset --local --workdir "$test_root"
bunx supabase test db --local --workdir "$test_root"
