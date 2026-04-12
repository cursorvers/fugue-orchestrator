#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="${SCRIPT_DIR}/scripts/lib/claude-teams-policy.sh"

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
  output="$("${POLICY}" "$@")" || {
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

echo "=== claude-teams-policy.sh unit tests ==="
echo ""

assert_field "small-task-blocked" "claude_teams_allowed" "false" \
  --task-size-tier small --risk-tier medium --claude-state ok --title "fix typo" --body "simple task"
assert_field "large-task-no-signal" "claude_teams_allowed" "false" \
  --task-size-tier large --risk-tier high --claude-state ok --title "large refactor" --body "refactor only"
assert_field "large-task-signal" "claude_teams_allowed" "true" \
  --task-size-tier large --risk-tier high --claude-state ok --title "cross-repo incident" --body "need cross-layer root cause investigation"
assert_field "degraded-blocked" "claude_teams_allowed" "false" \
  --task-size-tier critical --risk-tier high --claude-state degraded --title "incident" --body "cross-layer root cause investigation"
assert_field "reason-signal" "claude_teams_reason" "large-task-collaboration-signal" \
  --task-size-tier critical --risk-tier high --claude-state ok --title "incident" --body "claude-native skill chain and cross repo debugging"

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
