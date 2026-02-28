#!/usr/bin/env bash
set -euo pipefail

# test-workflow-risk-policy.sh — Unit test for workflow risk policy.
#
# Tests risk scoring, tier classification, preflight/dialogue floors,
# correction signals, and context budget guards.
#
# Usage: bash tests/test-workflow-risk-policy.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
POLICY="${SCRIPT_DIR}/scripts/lib/workflow-risk-policy.sh"

passed=0
failed=0
total=0

assert_risk() {
  local test_name="$1"
  shift
  local expected_tier="$1" expected_mode="$2"
  shift 2

  total=$((total + 1))
  local output
  output="$("${POLICY}" "$@" 2>/dev/null)" || {
    echo "FAIL [${test_name}]: script exited with error"
    failed=$((failed + 1))
    return
  }

  eval "${output}"

  local errors=""
  if [[ "${risk_tier}" != "${expected_tier}" ]]; then
    errors+=" tier=${risk_tier}(expected ${expected_tier})"
  fi
  if [[ "${multi_agent_mode_hint}" != "${expected_mode}" ]]; then
    errors+=" mode=${multi_agent_mode_hint}(expected ${expected_mode})"
  fi

  if [[ -n "${errors}" ]]; then
    echo "FAIL [${test_name}]:${errors} (score=${risk_score})"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}] (score=${risk_score})"
    passed=$((passed + 1))
  fi
}

assert_field() {
  local test_name="$1"
  local field_name="$2"
  local expected_value="$3"
  shift 3

  total=$((total + 1))
  local output
  output="$("${POLICY}" "$@" 2>/dev/null)" || {
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

echo "=== workflow-risk-policy.sh unit tests ==="
echo ""

# --- Group 1: Risk tier classification ---
assert_risk "low-simple" \
  "low" "standard" \
  --title "fix typo" --body "small fix" --labels "" --has-implement "false"

assert_risk "medium-workflow" \
  "medium" "enhanced" \
  --title "update workflow" --body "improve the ci pipeline" --labels "" --has-implement "true"

assert_risk "high-migration" \
  "high" "max" \
  --title "database migration" --body "full schema change with breaking change on production" --labels "large-refactor" --has-implement "true"

assert_risk "high-security-keywords" \
  "high" "max" \
  --title "security audit" --body "auth payment vulnerability incident" --labels "" --has-implement "true"

# --- Group 2: Label-based risk ---
assert_risk "large-refactor-label" \
  "high" "max" \
  --title "update" --body "changes" --labels "large-refactor,enhancement" --has-implement "true"

# --- Group 3: Text length risk ---
assert_risk "long-spec-high" \
  "medium" "enhanced" \
  --title "task" --body "$(printf '%0.sa' {1..2000})" --labels "" --has-implement "false"

# --- Group 4: Preflight floors (codex-full) ---
assert_field "preflight-codex-low" "preflight_cycles_floor" "2" \
  --title "fix typo" --body "small" --labels "" --has-implement "false" --orchestration-profile "codex-full"

assert_field "preflight-codex-high" "preflight_cycles_floor" "4" \
  --title "migration" --body "full schema change breaking change incident" --labels "large-refactor" --has-implement "true" --orchestration-profile "codex-full"

# --- Group 5: Preflight floors (claude-light) ---
assert_field "preflight-claude-low" "preflight_cycles_floor" "1" \
  --title "fix typo" --body "small" --labels "" --has-implement "false" --orchestration-profile "claude-light"

assert_field "preflight-claude-high" "preflight_cycles_floor" "3" \
  --title "migration" --body "full schema change breaking change incident" --labels "large-refactor" --has-implement "true" --orchestration-profile "claude-light"

# --- Group 6: Dialogue rounds ---
assert_field "dialogue-codex-low" "implementation_dialogue_rounds_floor" "1" \
  --title "fix" --body "small" --labels "" --has-implement "false" --orchestration-profile "codex-full"

assert_field "dialogue-codex-high" "implementation_dialogue_rounds_floor" "3" \
  --title "migration" --body "breaking change incident security" --labels "large-refactor" --has-implement "true" --orchestration-profile "codex-full"

# --- Group 7: Correction signal ---
assert_field "correction-label" "correction_signal" "true" \
  --title "fix" --body "" --labels "user-corrected" --has-implement "false"

assert_field "correction-postmortem" "correction_signal" "true" \
  --title "postmortem" --body "lessons learned" --labels "" --has-implement "false"

assert_field "no-correction" "correction_signal" "false" \
  --title "add feature" --body "new button" --labels "" --has-implement "false"

# --- Group 8: Lessons required ---
assert_field "lessons-correction" "lessons_required" "true" \
  --title "fix regression" --body "lessons learned from incident" --labels "postmortem" --has-implement "false"

assert_field "no-lessons-high" "lessons_required" "false" \
  --title "migration" --body "schema change" --labels "large-refactor" --has-implement "true"

# --- Group 9: Default profile ---
assert_risk "default-profile" \
  "low" "standard" \
  --title "fix" --body "small"

# --- Group 10: Edge cases ---
assert_risk "empty-input" \
  "low" "standard" \
  --title "" --body "" --labels "" --has-implement "false"

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
exit 0
