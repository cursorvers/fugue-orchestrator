#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="${ROOT_DIR}/scripts/lib/build-agent-matrix.sh"

passed=0
failed=0
total=0

run_test() {
  local test_name="$1"
  shift
  total=$((total + 1))
  if "$@"; then
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  else
    echo "FAIL [${test_name}]"
    failed=$((failed + 1))
  fi
}

matrix_json() {
  "${BUILDER}" "$@" --format json
}

test_subscription_baseline_defaults() {
  local output
  output="$(matrix_json \
    --engine subscription \
    --main-provider codex \
    --assist-provider claude \
    --multi-agent-mode enhanced \
    --allow-glm-in-subscription true)"

  echo "${output}" | jq -e '
    (.workflow_matrix | keys) == ["include"] and
    .use_glm_baseline == true and
    ([.matrix.include[] | select(.provider == "codex" and .name != "codex-main-orchestrator") | .model] | all(. == "gpt-5-codex")) and
    ([.matrix.include[] | select(.provider == "glm") | .model] | all(. == "glm-5")) and
    ([.matrix.include[] | select(.provider == "gemini" or .provider == "xai")] | length) == 0 and
    (.workflow_matrix.include == .matrix.include)
  ' >/dev/null
}

test_explicit_spark_override_is_preserved() {
  local output
  output="$(matrix_json \
    --engine subscription \
    --main-provider codex \
    --assist-provider claude \
    --multi-agent-mode standard \
    --allow-glm-in-subscription true \
    --codex-multi-agent-model gpt-5.3-codex-spark)"

  echo "${output}" | jq -e '
    [.matrix.include[] | select(.provider == "codex" and .name != "codex-main-orchestrator") | .model] | all(. == "gpt-5.3-codex-spark")
  ' >/dev/null
}

test_optional_metered_lanes_are_opt_in() {
  local output
  output="$(matrix_json \
    --engine api \
    --main-provider codex \
    --assist-provider claude \
    --multi-agent-mode standard \
    --allow-glm-in-subscription true \
    --metered-reason overflow \
    --wants-gemini true \
    --wants-xai true)"

  echo "${output}" | jq -e '
    ([.matrix.include[] | select(.provider == "gemini")] | length) == 1 and
    ([.matrix.include[] | select(.provider == "xai")] | length) == 1 and
    (.matrix.metered_reason == "overflow")
  ' >/dev/null
}

test_metered_lanes_require_reason() {
  local output
  output="$(matrix_json \
    --engine api \
    --main-provider codex \
    --assist-provider claude \
    --multi-agent-mode standard \
    --allow-glm-in-subscription true \
    --wants-gemini true \
    --wants-xai true)"

  echo "${output}" | jq -e '
    ([.matrix.include[] | select(.provider == "gemini" or .provider == "xai")] | length) == 0 and
    (.metered_reason == "none")
  ' >/dev/null
}

test_claude_teams_invocation_count_is_preserved() {
  local output
  output="$(matrix_json \
    --engine subscription \
    --main-provider codex \
    --assist-provider claude \
    --multi-agent-mode standard \
    --enable-claude-teams true \
    --claude-teams-max-invocations 3)"

  echo "${output}" | jq -e '
    ([.matrix.include[] | select(.name == "claude-teams-executor")] | length) == 1 and
    ([.matrix.include[] | select(.name == "claude-teams-executor") | .agent_directive | test("max_invocations=3") ] | any)
  ' >/dev/null
}

test_invalid_negative_invocation_count_falls_back_to_one() {
  local output
  output="$(matrix_json \
    --engine subscription \
    --main-provider codex \
    --assist-provider claude \
    --multi-agent-mode standard \
    --enable-claude-teams true \
    --claude-teams-max-invocations -9)"

  echo "${output}" | jq -e '
    ([.matrix.include[] | select(.name == "claude-teams-executor")] | length) == 1 and
    ([.matrix.include[] | select(.name == "claude-teams-executor") | .agent_directive | test("max_invocations=1") ] | any)
  ' >/dev/null
}

echo "=== build-agent-matrix.sh unit tests ==="
echo ""

run_test "subscription-baseline-defaults" test_subscription_baseline_defaults
run_test "explicit-spark-override-is-preserved" test_explicit_spark_override_is_preserved
run_test "optional-metered-lanes-are-opt-in" test_optional_metered_lanes_are_opt_in
run_test "metered-lanes-require-reason" test_metered_lanes_require_reason
run_test "claude-teams-invocation-count-is-preserved" test_claude_teams_invocation_count_is_preserved
run_test "invalid-negative-invocation-count-falls-back-to-one" test_invalid_negative_invocation_count_falls_back_to_one

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
