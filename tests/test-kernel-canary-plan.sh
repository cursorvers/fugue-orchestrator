#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANARY_SCRIPT="${ROOT_DIR}/scripts/harness/run-canary.sh"
CANARY_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-orchestrator-canary.yml"
ROUTER_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml"
COMMENT_SCRIPT="${ROOT_DIR}/scripts/harness/generate-tutti-comment.sh"

if [[ ! -x "${CANARY_SCRIPT}" ]]; then
  echo "FAIL: missing executable script ${CANARY_SCRIPT}" >&2
  exit 1
fi

grep -q "DEFAULT_MAIN_ORCHESTRATOR_PROVIDER: .*'codex'" "${CANARY_WORKFLOW}" || {
  echo "FAIL: canary workflow must default main orchestrator to codex" >&2
  exit 1
}
grep -q "CANARY_VERIFY_ROLLBACK" "${CANARY_WORKFLOW}" || {
  echo "FAIL: canary workflow missing rollback verification env" >&2
  exit 1
}
grep -q "LEGACY_MAIN_ORCHESTRATOR_PROVIDER" "${CANARY_WORKFLOW}" || {
  echo "FAIL: canary workflow missing legacy main provider env" >&2
  exit 1
}
grep -q "HANDOFF_TARGET" "${COMMENT_SCRIPT}" || {
  echo "FAIL: integrated comment generator missing handoff target support" >&2
  exit 1
}
grep -q "TASK_SIZE_TIER" "${COMMENT_SCRIPT}" || {
  echo "FAIL: integrated comment generator missing task size tier support" >&2
  exit 1
}
grep -q "HANDOFF_TARGET: .*inputs.handoff_target" "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing handoff target wiring into comment generation" >&2
  exit 1
}
echo "PASS [workflow-wiring]"

plan_output="$(
  CANARY_PLAN_ONLY=true \
  CANARY_PLAN_ONLINE_COUNT=1 \
  GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
  CLAUDE_RATE_LIMIT_STATE="ok" \
  CLAUDE_ROLE_POLICY="flex" \
  CLAUDE_DEGRADED_ASSIST_POLICY="claude" \
  CLAUDE_MAIN_ASSIST_POLICY="codex" \
  CI_EXECUTION_ENGINE="subscription" \
  SUBSCRIPTION_OFFLINE_POLICY="continuity" \
  CANARY_OFFLINE_POLICY_OVERRIDE="continuity" \
  EMERGENCY_CONTINUITY_MODE="false" \
  SUBSCRIPTION_RUNNER_LABEL="fugue-subscription" \
  EMERGENCY_ASSIST_POLICY="none" \
  API_STRICT_MODE="false" \
  HAS_ANTHROPIC_API_KEY="true" \
  HAS_OPENAI_API_KEY="true" \
  DEFAULT_MAIN_ORCHESTRATOR_PROVIDER="codex" \
  EXECUTION_PROVIDER_DEFAULT="" \
  CANARY_ALTERNATE_PROVIDER="claude" \
  CANARY_PRIMARY_HANDOFF_TARGET="kernel" \
  CANARY_VERIFY_ROLLBACK="true" \
  LEGACY_MAIN_ORCHESTRATOR_PROVIDER="claude" \
  LEGACY_ASSIST_ORCHESTRATOR_PROVIDER="claude" \
  LEGACY_FORCE_CLAUDE="true" \
  CANARY_LABEL_WAIT_ATTEMPTS="1" \
  CANARY_LABEL_WAIT_SLEEP_SEC="1" \
  CANARY_WAIT_FAST_ATTEMPTS="1" \
  CANARY_WAIT_FAST_SLEEP_SEC="1" \
  CANARY_WAIT_SLOW_ATTEMPTS="0" \
  CANARY_WAIT_SLOW_SLEEP_SEC="1" \
  bash "${CANARY_SCRIPT}"
)"

case_count="$(printf '%s\n' "${plan_output}" | jq -s 'length')"
if [[ "${case_count}" != "3" ]]; then
  echo "FAIL: expected 3 canary plan cases, got ${case_count}" >&2
  printf '%s\n' "${plan_output}" >&2
  exit 1
fi

regular_main="$(printf '%s\n' "${plan_output}" | jq -r 'select(.case == "regular") | .resolved_main')"
regular_handoff="$(printf '%s\n' "${plan_output}" | jq -r 'select(.case == "regular") | .handoff_target')"
alternate_main="$(printf '%s\n' "${plan_output}" | jq -r 'select(.case == "alternate") | .resolved_main')"
rollback_handoff="$(printf '%s\n' "${plan_output}" | jq -r 'select(.case == "rollback") | .handoff_target')"
rollback_mode_source="$(printf '%s\n' "${plan_output}" | jq -r 'select(.case == "rollback") | .multi_agent_mode_source')"
rollback_task_size="$(printf '%s\n' "${plan_output}" | jq -r 'select(.case == "rollback") | .task_size_tier')"

[[ "${regular_main}" == "codex" ]] || {
  echo "FAIL: regular case should resolve codex main, got ${regular_main}" >&2
  exit 1
}
[[ "${regular_handoff}" == "kernel" ]] || {
  echo "FAIL: regular case should target kernel handoff, got ${regular_handoff}" >&2
  exit 1
}
[[ "${alternate_main}" == "claude" ]] || {
  echo "FAIL: alternate case should resolve claude main, got ${alternate_main}" >&2
  exit 1
}
[[ "${rollback_handoff}" == "fugue-bridge" ]] || {
  echo "FAIL: rollback case should target fugue-bridge, got ${rollback_handoff}" >&2
  exit 1
}
[[ "${rollback_mode_source}" == "legacy-bridge" ]] || {
  echo "FAIL: rollback case should mark legacy-bridge mode source, got ${rollback_mode_source}" >&2
  exit 1
}
[[ "${rollback_task_size}" == "small" ]] || {
  echo "FAIL: rollback case should pin small task size tier, got ${rollback_task_size}" >&2
  exit 1
}
echo "PASS [plan-only-cases]"

echo "=== Results: 2/2 passed, 0 failed ==="
