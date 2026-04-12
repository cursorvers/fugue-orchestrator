#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/watchdog-alert-policy.sh"

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

state_with_bucket() {
  local key="$1"
  local value="$2"
  jq -cn --arg key "${key}" --arg value "${value}" '{reason_buckets:{($key):$value}}'
}

echo "=== watchdog-alert-policy.sh unit tests ==="
echo ""

assert_field "connectivity-persisted-delayed-first-run" "should_alert" "true" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json '{}' \
  --now-epoch 11400 \
  --openai-ok false \
  --pending-count 2

assert_field "connectivity-persisted-same-bucket-suppress" "should_alert" "false" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json "$(state_with_bucket "connectivity" "wall:180:1")" \
  --now-epoch 11700 \
  --openai-ok false \
  --pending-count 2

assert_field "connectivity-stateless-boundary-fire" "should_alert" "true" \
  --event-name schedule \
  --persist-state false \
  --previous-state-json '{}' \
  --now-epoch 10800 \
  --openai-ok false \
  --pending-count 2

assert_field "connectivity-stateless-same-bucket-suppress" "should_alert" "false" \
  --event-name schedule \
  --persist-state false \
  --previous-state-json '{}' \
  --now-epoch 11100 \
  --openai-ok false \
  --pending-count 2

assert_field "mainframe-stale-persisted-delayed-crossing" "should_alert" "true" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json '{}' \
  --now-epoch 20000 \
  --openai-ok true \
  --zai-ok true \
  --mainframe-stale true \
  --mainframe-hours 3 \
  --mainframe-minutes 186 \
  --mainframe-pending-count 3

assert_field "mainframe-stale-persisted-same-bucket-suppress" "should_alert" "false" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json "$(state_with_bucket "mainframe-stale" "stale:180:360:0")" \
  --now-epoch 20300 \
  --openai-ok true \
  --zai-ok true \
  --mainframe-stale true \
  --mainframe-hours 3 \
  --mainframe-minutes 191 \
  --mainframe-pending-count 3

assert_field "mainframe-stale-persisted-repeat-fire" "should_alert" "false" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json "$(state_with_bucket "mainframe-stale" "stale:180:360:0")" \
  --now-epoch 40000 \
  --openai-ok true \
  --zai-ok true \
  --mainframe-stale true \
  --mainframe-hours 9 \
  --mainframe-minutes 541 \
  --mainframe-pending-count 3

assert_field "router-stale-persisted-same-bucket-suppress" "should_alert" "false" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json "$(state_with_bucket "router-stale" "stale:180:360:0")" \
  --now-epoch 20300 \
  --openai-ok true \
  --zai-ok true \
  --router-stale true \
  --router-hours 3 \
  --router-minutes 191 \
  --pending-count 3

assert_field "router-stale-persisted-repeat-fire" "should_alert" "false" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json "$(state_with_bucket "router-stale" "stale:180:360:0")" \
  --now-epoch 40000 \
  --openai-ok true \
  --zai-ok true \
  --router-stale true \
  --router-hours 9 \
  --router-minutes 541 \
  --pending-count 3

assert_field "missing-mainframe-persisted-delayed-6h-bucket" "should_alert" "true" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json '{}' \
  --now-epoch 22200 \
  --openai-ok true \
  --zai-ok true \
  --mainframe-stale true \
  --mainframe-hours 9999 \
  --mainframe-minutes 999999 \
  --mainframe-pending-count 3

assert_field "missing-mainframe-persisted-same-bucket-suppress" "should_alert" "false" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json "$(state_with_bucket "mainframe-stale" "wall:360:1")" \
  --now-epoch 21900 \
  --openai-ok true \
  --zai-ok true \
  --mainframe-stale true \
  --mainframe-hours 9999 \
  --mainframe-minutes 999999 \
  --mainframe-pending-count 3

assert_field "missing-mainframe-persisted-next-bucket-fire" "should_alert" "false" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json "$(state_with_bucket "mainframe-stale" "wall:360:1")" \
  --now-epoch 43800 \
  --openai-ok true \
  --zai-ok true \
  --mainframe-stale true \
  --mainframe-hours 9999 \
  --mainframe-minutes 999999 \
  --mainframe-pending-count 3

assert_field "multi-reason-state-keeps-independent-buckets" "state_update_required" "true" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json "$(jq -cn '{reason_buckets:{"connectivity":"wall:180:1"}}')" \
  --now-epoch 11700 \
  --openai-ok false \
  --router-stale true \
  --router-hours 3 \
  --router-minutes 191 \
  --pending-count 3

assert_field "multi-reason-state-carries-both-reasons" "due_reasons_csv" "connectivity,router-stale" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json '{}' \
  --now-epoch 11400 \
  --openai-ok false \
  --router-stale true \
  --router-hours 3 \
  --router-minutes 191 \
  --pending-count 3

assert_field "inactive-reasons-are-pruned-for-recovery" "state_update_required" "true" \
  --event-name schedule \
  --persist-state true \
  --previous-state-json "$(jq -cn '{reason_buckets:{"mainframe-stale":"active","connectivity":"active"}}')" \
  --now-epoch 11400 \
  --openai-ok true \
  --zai-ok true \
  --pending-count 0

assert_field "workflow-dispatch-without-force-suppressed" "should_alert" "false" \
  --event-name workflow_dispatch \
  --persist-state true \
  --previous-state-json '{}' \
  --now-epoch 11400 \
  --openai-ok false \
  --pending-count 2

assert_field "workflow-dispatch-force-alert" "should_alert" "true" \
  --event-name workflow_dispatch \
  --persist-state true \
  --previous-state-json '{}' \
  --now-epoch 11400 \
  --force-line-alert true

assert_field "workflow-dispatch-force-reason" "due_reasons_csv" "manual-force-line" \
  --event-name workflow_dispatch \
  --persist-state true \
  --previous-state-json '{}' \
  --now-epoch 11400 \
  --force-line-alert true

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
