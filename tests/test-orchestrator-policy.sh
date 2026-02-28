#!/usr/bin/env bash
set -euo pipefail

# test-orchestrator-policy.sh — Exhaustive unit test for orchestrator-policy.sh
#
# Tests all key state transitions in the provider fallback state machine.
# Each test case defines inputs and expected outputs, then runs the policy
# script and compares results.
#
# Usage: bash tests/test-orchestrator-policy.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="${SCRIPT_DIR}/scripts/lib/orchestrator-policy.sh"

passed=0
failed=0
total=0

assert_policy() {
  local test_name="$1"
  shift
  local expected_main="$1" expected_assist="$2" expected_main_fb="$3" expected_pressure="$4"
  shift 4

  total=$((total + 1))
  local output
  output="$("${POLICY}" "$@" --format env)" || {
    echo "FAIL [${test_name}]: script exited with error"
    failed=$((failed + 1))
    return
  }

  eval "${output}"

  local errors=""
  if [[ "${resolved_main}" != "${expected_main}" ]]; then
    errors+=" main=${resolved_main}(expected ${expected_main})"
  fi
  if [[ "${resolved_assist}" != "${expected_assist}" ]]; then
    errors+=" assist=${resolved_assist}(expected ${expected_assist})"
  fi
  if [[ "${main_fallback_applied}" != "${expected_main_fb}" ]]; then
    errors+=" main_fb=${main_fallback_applied}(expected ${expected_main_fb})"
  fi
  if [[ "${pressure_guard_applied}" != "${expected_pressure}" ]]; then
    errors+=" pressure=${pressure_guard_applied}(expected ${expected_pressure})"
  fi

  if [[ -n "${errors}" ]]; then
    echo "FAIL [${test_name}]:${errors}"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  fi
}

assert_reason() {
  local test_name="$1"
  local field_name="$2"
  local expected_value="$3"
  shift 3

  total=$((total + 1))
  local output
  output="$("${POLICY}" "$@" --format env)" || {
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

echo "=== orchestrator-policy.sh unit tests ==="
echo ""

# --- Group 1: codex main, claude state=ok ---
assert_policy "codex+claude/ok" \
  "codex" "claude" "false" "false" \
  --main codex --assist claude --claude-state ok

assert_policy "codex+codex/ok" \
  "codex" "codex" "false" "false" \
  --main codex --assist codex --claude-state ok

assert_policy "codex+none/ok" \
  "codex" "none" "false" "false" \
  --main codex --assist none --claude-state ok

# --- Group 2: claude main, claude state=ok ---
# Pressure guard: main=claude + assist=claude → assist=codex
assert_policy "claude+claude/ok (pressure)" \
  "claude" "codex" "false" "true" \
  --main claude --assist claude --claude-state ok

assert_policy "claude+codex/ok" \
  "claude" "codex" "false" "false" \
  --main claude --assist codex --claude-state ok

# main=claude + assist=none → invariant forces assist=codex
assert_policy "claude+none/ok (invariant)" \
  "claude" "codex" "false" "true" \
  --main claude --assist none --claude-state ok

# --- Group 3: claude main, claude state=degraded ---
# Main falls back to codex
assert_policy "claude+claude/degraded (main fb)" \
  "codex" "claude" "true" "false" \
  --main claude --assist claude --claude-state degraded

assert_policy "claude+codex/degraded (main fb)" \
  "codex" "codex" "true" "false" \
  --main claude --assist codex --claude-state degraded

assert_policy "claude+none/degraded (main fb)" \
  "codex" "none" "true" "false" \
  --main claude --assist none --claude-state degraded

# --- Group 4: claude main, claude state=exhausted ---
# Main falls back to codex, assist=claude → none
assert_policy "claude+claude/exhausted" \
  "codex" "none" "true" "false" \
  --main claude --assist claude --claude-state exhausted

assert_policy "claude+codex/exhausted" \
  "codex" "codex" "true" "false" \
  --main claude --assist codex --claude-state exhausted

# --- Group 5: codex main, degraded state ---
assert_policy "codex+claude/degraded (assist fb)" \
  "codex" "claude" "false" "false" \
  --main codex --assist claude --claude-state degraded --degraded-assist-policy claude

assert_policy "codex+claude/degraded->codex" \
  "codex" "codex" "false" "false" \
  --main codex --assist claude --claude-state degraded --degraded-assist-policy codex

assert_policy "codex+claude/degraded->none" \
  "codex" "none" "false" "false" \
  --main codex --assist claude --claude-state degraded --degraded-assist-policy none

# --- Group 6: codex main, exhausted state ---
assert_policy "codex+claude/exhausted" \
  "codex" "none" "false" "false" \
  --main codex --assist claude --claude-state exhausted

# --- Group 7: force-claude overrides ---
assert_policy "claude+claude/degraded+force" \
  "claude" "claude" "false" "false" \
  --main claude --assist claude --claude-state degraded --force-claude true

assert_policy "claude+claude/exhausted+force" \
  "claude" "claude" "false" "false" \
  --main claude --assist claude --claude-state exhausted --force-claude true

# --- Group 8: role policy sub-only ---
assert_policy "claude+codex/ok+sub-only" \
  "codex" "codex" "true" "false" \
  --main claude --assist codex --claude-state ok --claude-role-policy sub-only

assert_policy "claude+codex/ok+sub-only+force" \
  "claude" "codex" "false" "false" \
  --main claude --assist codex --claude-state ok --claude-role-policy sub-only --force-claude true

# --- Group 9: assist-policy=none ---
assert_policy "claude+claude/ok+policy-none" \
  "claude" "codex" "false" "true" \
  --main claude --assist claude --claude-state ok --assist-policy none

# --- Group 10: defaults ---
assert_policy "empty defaults to codex+claude" \
  "codex" "claude" "false" "false" \
  --main "" --assist "" --claude-state ok

assert_policy "custom defaults" \
  "claude" "codex" "false" "false" \
  --main "" --assist "" --default-main claude --default-assist codex --claude-state ok

# --- Group 11: pressure_guard_reason audit trail ---
assert_reason "reason: pressure only" \
  "pressure_guard_reason" "main-claude-assist-claude->codex" \
  --main claude --assist claude --claude-state ok --assist-policy codex

assert_reason "reason: invariant only (assist=none)" \
  "pressure_guard_reason" "main-claude-requires-assist-codex" \
  --main claude --assist none --claude-state ok

assert_reason "reason: pressure+invariant (policy=none)" \
  "pressure_guard_reason" "main-claude-assist-claude->none;invariant-override->codex" \
  --main claude --assist claude --claude-state ok --assist-policy none

# --- Group 12: edge cases ---
assert_policy "invalid main normalizes" \
  "codex" "claude" "false" "false" \
  --main "INVALID" --assist claude --claude-state ok

assert_policy "uppercase normalizes" \
  "claude" "codex" "false" "false" \
  --main "CLAUDE" --assist "CODEX" --claude-state ok

assert_policy "whitespace normalizes" \
  "codex" "claude" "false" "false" \
  --main "  codex  " --assist "  claude  " --claude-state ok

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
exit 0
