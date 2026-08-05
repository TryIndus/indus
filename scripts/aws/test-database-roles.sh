#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/indus-db-roles.XXXXXX")"
test_data="$test_root/data"
test_port="${INDUS_DB_ROLE_TEST_PORT:-55439}"

cleanup() {
  pg_ctl -D "$test_data" -m fast stop >/dev/null 2>&1 || true
  case "$test_root" in
    "${TMPDIR:-/tmp}"/indus-db-roles.*) rm -r "$test_root" ;;
  esac
}
trap cleanup EXIT

for command in initdb pg_ctl createdb psql pg_isready bundle cargo; do
  command -v "$command" >/dev/null 2>&1 || { echo "Missing required command: $command" >&2; exit 1; }
done
if pg_isready -h 127.0.0.1 -p "$test_port" >/dev/null 2>&1; then
  echo "Port $test_port is already in use; set INDUS_DB_ROLE_TEST_PORT to an unused local port." >&2
  exit 1
fi

initdb -D "$test_data" -U postgres --auth=trust --no-locale >/dev/null
pg_ctl -D "$test_data" -o "-p $test_port -h 127.0.0.1" -w start >/dev/null
createdb -h 127.0.0.1 -p "$test_port" -U postgres indus_roles_test

platform_password="platform-local-role-test-0001"
market_password="market-local-role-test-0000001"
migration_password="migration-local-role-test-001"
migration_url="postgresql://indus_migrator:${migration_password}@127.0.0.1:${test_port}/indus_roles_test"

INDUS_PLATFORM_DB_PASSWORD="$platform_password" \
INDUS_MARKET_DB_PASSWORD="$market_password" \
INDUS_MIGRATION_DB_PASSWORD="$migration_password" \
psql -h 127.0.0.1 -p "$test_port" -U postgres -d indus_roles_test \
  --no-psqlrc --set ON_ERROR_STOP=1 --file "$root_dir/scripts/aws/database-roles.sql" >/dev/null

(
  cd "$root_dir/apps/platform-api"
  DATABASE_URL="$migration_url" \
  PGOPTIONS='-c role=indus_platform_owner -c search_path=public,pg_catalog' \
  RAILS_ENV=production \
  SECRET_KEY_BASE_DUMMY=1 \
  bundle exec rails db:migrate >/dev/null
)

DATABASE_URL="$migration_url" \
PGOPTIONS='-c role=indus_market_owner -c search_path=market_data,pg_catalog' \
cargo run --locked --manifest-path "$root_dir/services/market-data/Cargo.toml" \
  --bin indus-market-data -- migrate >/dev/null

psql -h 127.0.0.1 -p "$test_port" -U postgres -d indus_roles_test \
  --no-psqlrc --set ON_ERROR_STOP=1 --file "$root_dir/scripts/aws/verify-database-roles.sql" >/dev/null

[[ "$(psql -h 127.0.0.1 -p "$test_port" -U postgres -d indus_roles_test -Atqc "SELECT to_regclass('public._sqlx_migrations') IS NULL")" == "t" ]]
[[ "$(psql -h 127.0.0.1 -p "$test_port" -U postgres -d indus_roles_test -Atqc "SELECT to_regclass('market_data._sqlx_migrations') IS NOT NULL")" == "t" ]]

PGPASSWORD="$market_password" psql -h 127.0.0.1 -p "$test_port" -U indus_market_writer \
  -d indus_roles_test --no-psqlrc --set ON_ERROR_STOP=1 \
  -Atqc 'SELECT market_data.ensure_monthly_partitions(2)' >/dev/null
if PGPASSWORD="$market_password" psql -h 127.0.0.1 -p "$test_port" -U indus_market_writer \
  -d indus_roles_test --no-psqlrc -Atqc 'SELECT count(*) FROM public.users' >/dev/null 2>&1; then
  echo "Market writer unexpectedly read a platform table." >&2
  exit 1
fi
if PGPASSWORD="$platform_password" psql -h 127.0.0.1 -p "$test_port" -U indus_platform \
  -d indus_roles_test --no-psqlrc -Atqc 'SELECT count(*) FROM market_data.bars' >/dev/null 2>&1; then
  echo "Platform runtime unexpectedly read a market table." >&2
  exit 1
fi

echo "Disposable PostgreSQL role integration passed."
