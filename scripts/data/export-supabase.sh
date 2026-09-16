#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 OUTPUT_DIRECTORY" >&2
  exit 64
fi

if [[ -z "${SUPABASE_DATABASE_URL:-}" ]]; then
  echo "SUPABASE_DATABASE_URL must contain the direct, TLS-protected Supabase Postgres URL." >&2
  exit 64
fi

export_dir="$1"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
dump_path="${export_dir}/supabase-${timestamp}.dump"
manifest_path="${dump_path}.sha256"

mkdir -p "$export_dir"
umask 077

pg_dump --format=custom --no-owner --no-privileges --file "$dump_path" "$SUPABASE_DATABASE_URL"
pg_restore --list "$dump_path" >/dev/null
shasum -a 256 "$dump_path" >"$manifest_path"

echo "Export created: $dump_path"
echo "Checksum manifest: $manifest_path"
