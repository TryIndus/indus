#!/usr/bin/env bash
set -euo pipefail

metrics_file="${1:-}"
[[ -f "$metrics_file" ]] || { echo "Usage: $0 METRICS_JSON" >&2; exit 2; }
jq -e '
  (.window_minutes | type == "number" and . >= 10) and
  (.error_rate | type == "number" and . >= 0) and
  (.p95_latency_ms | type == "number" and . >= 0) and
  (.reconciliation_mismatches | type == "number" and . >= 0) and
  (.stream_delay_seconds | type == "number" and . >= 0) and
  (.workflow_terminal_rate | type == "number" and . >= 0 and . <= 1)
' "$metrics_file" >/dev/null || { echo "Malformed or too-short observation window." >&2; exit 2; }

reasons="$(jq -r '
  [
    if .error_rate > 0.02 then "error_rate>2%" else empty end,
    if .p95_latency_ms > 500 then "p95_latency>500ms" else empty end,
    if .reconciliation_mismatches > 0 then "data_reconciliation_mismatch" else empty end,
    if .stream_delay_seconds > 5 then "stream_delay>5s" else empty end,
    if .workflow_terminal_rate < 0.99 then "workflow_terminal_rate<99%" else empty end
  ] | join(",")
' "$metrics_file")"

if [[ -n "$reasons" ]]; then
  echo "ROLLBACK $reasons"
  exit 10
fi
echo "CONTINUE all cutover abort thresholds are within bounds"
