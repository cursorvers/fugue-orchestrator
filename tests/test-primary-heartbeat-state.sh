#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/resolve-primary-heartbeat-state.sh"

passed=0
failed=0
total=0

assert_field() {
  local test_name="$1"
  local field_name="$2"
  local expected_value="$3"
  shift 3

  total=$((total + 1))
  local output
  output="$("${SCRIPT}" "$@" --format env)" || {
    echo "FAIL [${test_name}]: script exited with error"
    failed=$((failed + 1))
    return
  }

  eval "${output}"
  local actual="${!field_name}"
  if [[ "${actual}" != "${expected_value}" ]]; then
    echo "FAIL [${test_name}]: ${field_name}=${actual}(expected ${expected_value})"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  fi
}

ts_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

ts_minutes_ago() {
  local minutes="$1"
  if date -u -d "${minutes} minutes ago" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -d "${minutes} minutes ago" +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -v-"${minutes}"M +%Y-%m-%dT%H:%M:%SZ
  fi
}

ts_minutes_ahead() {
  local minutes="$1"
  if date -u -d "${minutes} minutes" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -d "${minutes} minutes" +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -v+"${minutes}"M +%Y-%m-%dT%H:%M:%SZ
  fi
}

fresh_ts="$(ts_now)"
late_ts="$(ts_minutes_ago 12)"
missing_ts="$(ts_minutes_ago 40)"
future_ts="$(ts_minutes_ahead 10)"

echo "=== resolve-primary-heartbeat-state.sh unit tests ==="
echo ""

assert_field "full-mode-ignores-heartbeat" "failover_state" "healthy" \
  --gha-execution-mode full \
  --heartbeat-at "${missing_ts}" \
  --runner-online-count 0

assert_field "record-only-fresh" "failover_state" "healthy" \
  --gha-execution-mode record-only \
  --current-state healthy \
  --heartbeat-at "${fresh_ts}" \
  --runner-online-count 1

assert_field "record-only-fresh-after-offline" "failover_state" "recovered" \
  --gha-execution-mode record-only \
  --current-state offline \
  --heartbeat-at "${fresh_ts}" \
  --runner-online-count 1

assert_field "late-heartbeat-degraded" "failover_state" "degraded" \
  --gha-execution-mode record-only \
  --heartbeat-at "${late_ts}" \
  --runner-online-count 0

assert_field "runner-online-no-heartbeat-degraded" "failover_state" "degraded" \
  --gha-execution-mode record-only \
  --heartbeat-at "" \
  --runner-online-count 1

assert_field "missing-heartbeat-offline-with-work" "failover_state" "offline" \
  --gha-execution-mode record-only \
  --heartbeat-at "${missing_ts}" \
  --runner-online-count 0 \
  --pending-count 2

assert_field "missing-heartbeat-backup-safe" "backup_router_execution_mode" "backup-safe" \
  --gha-execution-mode record-only \
  --heartbeat-at "${missing_ts}" \
  --runner-online-count 0 \
  --pending-count 1

assert_field "missing-heartbeat-no-work-degraded" "failover_state" "degraded" \
  --gha-execution-mode record-only \
  --heartbeat-at "${missing_ts}" \
  --runner-online-count 0 \
  --pending-count 0 \
  --mainframe-pending-count 0 \
  --router-stale false \
  --mainframe-stale false

assert_field "future-heartbeat-invalid" "heartbeat_status" "invalid" \
  --gha-execution-mode record-only \
  --heartbeat-at "${future_ts}" \
  --runner-online-count 0 \
  --heartbeat-future-skew-seconds 60

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
