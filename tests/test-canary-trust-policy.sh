#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="${SCRIPT_DIR}/scripts/lib/canary-trust-policy.sh"

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
  output="$(bash "${POLICY}" "$@")" || {
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

echo "=== canary-trust-policy.sh unit tests ==="
echo ""

assert_field "non-canary-none" "trusted" "false" \
  --permission none \
  --vote-command false \
  --canary-dispatch-owned false \
  --issue-title "normal task" \
  --issue-body "plain issue body" \
  --issue-author "someone"

assert_field "vote-bypass" "permission" "vote-bypass" \
  --permission none \
  --vote-command true \
  --canary-dispatch-owned false \
  --issue-title "vote task" \
  --issue-body "plain issue body" \
  --issue-author "someone"

assert_field "canary-bypass" "permission" "canary-bypass" \
  --permission none \
  --vote-command false \
  --canary-dispatch-owned true \
  --issue-title "[canary-lite] regular claude-main request 20260308231024" \
  --issue-body $'## Canary\nAutomated orchestration canary.\n' \
  --issue-author "github-actions"

assert_field "canary-bypass-app-github-actions" "permission" "canary-bypass" \
  --permission none \
  --vote-command false \
  --canary-dispatch-owned true \
  --issue-title "[canary-lite] regular claude-main request 20260308231024" \
  --issue-body $'## Canary\nAutomated orchestration canary.\n' \
  --issue-author "app/github-actions"

assert_field "canary-spoof-rejected" "trusted" "false" \
  --permission none \
  --vote-command false \
  --canary-dispatch-owned true \
  --issue-title "[canary-lite] regular claude-main request 20260308231024" \
  --issue-body $'## Canary\nAutomated orchestration canary.\n' \
  --issue-author "masayuki"

assert_field "collaborator-permission" "trusted" "true" \
  --permission write \
  --vote-command false \
  --canary-dispatch-owned false \
  --issue-title "normal task" \
  --issue-body "plain issue body" \
  --issue-author "masayuki"

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
