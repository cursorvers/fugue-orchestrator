#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/watchdog-reconcile-claim-policy.sh"

assert_case() {
  local name="$1"
  local pending_json="$2"
  local prev_json="$3"
  local expected_dispatch="$4"
  local expected_claim_count="$5"

  local out
  out="$(
    bash "${SCRIPT}" \
      --pending-json "${pending_json}" \
      --previous-state-json "${prev_json}" \
      --persist-state true \
      --now-epoch 200 \
      --ttl-seconds 60 \
      --format json
  )"

  local actual_dispatch
  actual_dispatch="$(printf '%s' "${out}" | jq -c '.dispatch_issue_numbers')"
  if [[ "${actual_dispatch}" != "${expected_dispatch}" ]]; then
    echo "FAIL [${name}]: dispatch=${actual_dispatch} expected=${expected_dispatch}"
    exit 1
  fi

  local claim_count
  claim_count="$(printf '%s' "${out}" | jq '.next_state.claims | length')"
  if [[ "${claim_count}" != "${expected_claim_count}" ]]; then
    echo "FAIL [${name}]: claim_count=${claim_count} expected=${expected_claim_count}"
    exit 1
  fi
  echo "PASS [${name}]"
}

echo "=== watchdog-reconcile-claim-policy.sh unit tests ==="
echo ""

assert_case "dedupes-pending-input" '[101,101,102]' '{}' '[101,102]' '2'
assert_case "suppresses-unexpired-claim" '[101,102]' '{"claims":{"101":{"issue_number":101,"claimed_at":180,"expires_at":240,"source":"watchdog-reconcile","status":"claimed"}}}' '[102]' '2'
assert_case "reclaims-stale-claim" '[101]' '{"claims":{"101":{"issue_number":101,"claimed_at":100,"expires_at":150,"source":"watchdog-reconcile","status":"claimed"}}}' '[101]' '1'
assert_case "releases-non-pending-claims" '[102]' '{"claims":{"101":{"issue_number":101,"claimed_at":180,"expires_at":240,"source":"watchdog-reconcile","status":"claimed"}}}' '[102]' '1'
assert_case "releases-all-claims-when-pending-empty" '[]' '{"claims":{"101":{"issue_number":101,"claimed_at":180,"expires_at":240,"source":"watchdog-reconcile","status":"claimed"}}}' '[]' '0'

echo ""
echo "=== Results: 5/5 passed, 0 failed ==="
