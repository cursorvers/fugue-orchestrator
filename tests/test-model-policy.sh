#!/usr/bin/env bash
set -euo pipefail

# test-model-policy.sh — Unit test for model normalization policy.
#
# Tests model name validation, adjustment detection, and format outputs.
#
# Usage: bash tests/test-model-policy.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
POLICY="${SCRIPT_DIR}/scripts/lib/model-policy.sh"

passed=0
failed=0
total=0

assert_model() {
  local test_name="$1"
  shift
  local expected_field="$1" expected_value="$2"
  shift 2

  total=$((total + 1))
  local output
  output="$("${POLICY}" "$@" 2>/dev/null)" || {
    echo "FAIL [${test_name}]: script exited with error"
    failed=$((failed + 1))
    return
  }

  eval "${output}"
  local actual="${!expected_field}"

  if [[ "${actual}" != "${expected_value}" ]]; then
    echo "FAIL [${test_name}]: ${expected_field}=${actual}(expected ${expected_value})"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  fi
}

assert_json() {
  local test_name="$1"
  local jq_filter="$2"
  local expected="$3"
  shift 3

  total=$((total + 1))
  local output
  output="$("${POLICY}" --format json "$@" 2>/dev/null)" || {
    echo "FAIL [${test_name}]: script exited with error"
    failed=$((failed + 1))
    return
  }

  local actual
  actual="$(echo "${output}" | jq -r "${jq_filter}" 2>/dev/null)" || {
    echo "FAIL [${test_name}]: jq parse error"
    failed=$((failed + 1))
    return
  }

  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL [${test_name}]: ${jq_filter}=${actual}(expected ${expected})"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  fi
}

echo "=== model-policy.sh unit tests ==="
echo ""

# --- Group 1: Default values (no args) ---
assert_model "default-codex-main" \
  "codex_main_model" "gpt-5-codex"

assert_model "default-codex-multi" \
  "codex_multi_agent_model" "gpt-5.3-codex-spark"

assert_model "default-claude" \
  "claude_model" "claude-sonnet-4-6"

assert_model "default-glm" \
  "glm_model" "glm-5.0"

assert_model "default-gemini" \
  "gemini_model" "gemini-3.1-pro"

assert_model "default-xai" \
  "xai_model" "grok-4"

assert_model "default-not-adjusted" \
  "model_policy_adjusted" "false"

# --- Group 2: Valid model names pass through ---
assert_model "codex-spark-valid" \
  "codex_multi_agent_model" "gpt-5.3-codex-spark" \
  --codex-multi-agent-model "gpt-5.3-codex-spark"

assert_model "codex-spark-5.1" \
  "codex_multi_agent_model" "gpt-5.1-codex-spark" \
  --codex-multi-agent-model "gpt-5.1-codex-spark"

assert_model "claude-sonnet-valid" \
  "claude_model" "claude-sonnet-4-6" \
  --claude-model "claude-sonnet-4-6"

assert_model "glm-4.5-valid" \
  "glm_model" "glm-4.5" \
  --glm-model "glm-4.5"

assert_model "glm-5.0-valid" \
  "glm_model" "glm-5.0" \
  --glm-model "glm-5.0"

assert_model "gemini-flash-valid" \
  "gemini_model" "gemini-3-flash" \
  --gemini-model "gemini-3-flash"

assert_model "xai-grok4-variant" \
  "xai_model" "grok-4-mini" \
  --xai-model "grok-4-mini"

# --- Group 3: Invalid models get normalized ---
assert_model "invalid-codex-main" \
  "codex_main_model" "gpt-5-codex" \
  --codex-main-model "gpt-4-turbo"

assert_model "invalid-claude" \
  "claude_model" "claude-sonnet-4-6" \
  --claude-model "claude-opus-4-6"

assert_model "invalid-glm" \
  "glm_model" "glm-5.0" \
  --glm-model "glm-3-turbo"

assert_model "invalid-gemini" \
  "gemini_model" "gemini-3.1-pro" \
  --gemini-model "gemini-2.5-pro"

assert_model "invalid-xai" \
  "xai_model" "grok-4" \
  --xai-model "grok-3"

# --- Group 4: Adjustment detection ---
assert_model "adjusted-true" \
  "model_policy_adjusted" "true" \
  --codex-main-model "gpt-4" --claude-model "claude-opus-4-6"

assert_model "adjusted-false-all-valid" \
  "model_policy_adjusted" "false" \
  --codex-multi-agent-model "gpt-5.3-codex-spark" --glm-model "glm-5.0"

# --- Group 5: JSON format ---
assert_json "json-codex-main" \
  ".codex_main_model" "gpt-5-codex"

assert_json "json-adjusted-false" \
  ".adjusted" "false"

assert_json "json-adjusted-true" \
  ".adjusted" "true" \
  --claude-model "claude-3-opus"

assert_json "json-adjustments" \
  ".adjustments" "" \
  --codex-multi-agent-model "gpt-5.3-codex-spark"

# --- Group 6: Edge cases ---
assert_model "empty-codex-main" \
  "codex_main_model" "gpt-5-codex" \
  --codex-main-model ""

assert_model "whitespace-model" \
  "claude_model" "claude-sonnet-4-6" \
  --claude-model "  claude-sonnet-4-6  "

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
exit 0
