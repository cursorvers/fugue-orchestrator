#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/watchdog-alert-delivery-policy.sh"

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
  output="$(bash "${SCRIPT}" "$@" --format env)" || {
    echo "FAIL [${test_name}]: script exited with error"
    failed=$((failed + 1))
    return
  }

  eval "${output}"
  local actual="${!field_name-}"
  if [[ "${actual}" != "${expected_value}" ]]; then
    echo "FAIL [${test_name}]: ${field_name}=${actual} (expected ${expected_value})"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  fi
}

echo "=== watchdog-alert-delivery-policy.sh unit tests ==="
echo ""

assert_field "discord-success-allows-persist" "persist_allowed" "true" \
  --discord-sent true \
  --discord-attempted true

assert_field "line-push-ok-allows-persist" "persist_allowed" "true" \
  --line-attempted true \
  --line-sent true \
  --line-status ok \
  --line-transport push

assert_field "line-webhook-accepted-upstream-persists" "persist_allowed" "true" \
  --line-sent true \
  --line-status ok \
  --line-transport webhook \
  --line-delivery-state accepted-upstream

assert_field "line-webhook-delivered-allows-persist" "persist_allowed" "true" \
  --line-attempted true \
  --line-sent true \
  --line-status ok \
  --line-transport webhook \
  --line-delivery-state delivered

assert_field "attempted-failed-line-does-not-persist" "persist_allowed" "false" \
  --line-attempted true \
  --line-sent false \
  --line-status error \
  --line-transport push

assert_field "line-failure-does-not-persist" "persist_allowed" "false" \
  --line-attempted false \
  --line-sent false \
  --line-status error \
  --line-transport push

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
