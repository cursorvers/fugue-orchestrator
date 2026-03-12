#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANARY_SCRIPT="${ROOT_DIR}/scripts/harness/run-canary.sh"
CANARY_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-orchestrator-canary.yml"
ROUTER_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml"
TASK_ROUTER_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-task-router.yml"
RESOLVE_CONTEXT_SCRIPT="${ROOT_DIR}/scripts/harness/resolve-orchestration-context.sh"
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
grep -q "trust_subject:" "${CANARY_WORKFLOW}" || {
  echo "FAIL: canary workflow missing trust_subject workflow_dispatch input" >&2
  exit 1
}
grep -q "LEGACY_MAIN_ORCHESTRATOR_PROVIDER" "${CANARY_WORKFLOW}" || {
  echo "FAIL: canary workflow missing legacy main provider env" >&2
  exit 1
}
grep -q 'CANARY_TRUST_SUBJECT: .*github.event.inputs.trust_subject' "${CANARY_WORKFLOW}" || {
  echo "FAIL: canary workflow should export trust_subject into run-canary env" >&2
  exit 1
}
grep -q 'trust_subject="\${GITHUB_TRIGGERING_ACTOR:-\${GITHUB_ACTOR:-}}"' "${ROOT_DIR}/.github/workflows/fugue-orchestration-gate.yml" || {
  echo "FAIL: orchestration gate should pass triggering actor into canary dispatch" >&2
  exit 1
}
grep -q "gh_var_default" "${CANARY_SCRIPT}" || {
  echo "FAIL: canary script missing GitHub variable hydration helper" >&2
  exit 1
}
grep -q "needs-human|needs-review|processing" "${CANARY_SCRIPT}" || {
  echo "FAIL: canary script should clean transient review labels on pass" >&2
  exit 1
}
if sed -n '/local cmd=(gh issue create/,/local url/p' "${CANARY_SCRIPT}" | grep -q -- '--label "tutti"'; then
  echo "FAIL: canary issue creation should not auto-apply tutti label before workflow_dispatch" >&2
  exit 1
fi
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
grep -q 'echo "task_size_tier=${task_size_tier}"' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow must emit task_size_tier as a job output" >&2
  exit 1
}
grep -q "canary-dispatch-owned" "${TASK_ROUTER_WORKFLOW}" || {
  echo "FAIL: task router should skip canary issues owned by run-canary dispatch" >&2
  exit 1
}

grep -q 'canary_dispatch_owned="true"' "${RESOLVE_CONTEXT_SCRIPT}" || {
  echo "FAIL: resolve context should allow workflow_dispatch canary issues without tutti label" >&2
  exit 1
}
grep -q 'canary_dispatch_owned:' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing canary dispatch ownership input" >&2
  exit 1
}
grep -q 'canary_dispatch_owned: "\${{ needs.ctx.outputs.canary_dispatch_owned }}"' "${CANARY_WORKFLOW%orchestrator-canary.yml}tutti-caller.yml" || {
  echo "FAIL: caller workflow should pass canary dispatch ownership into router" >&2
  exit 1
}
grep -q 'GITHUB_TRIGGERING_ACTOR:-\${GITHUB_ACTOR:-}' "${CANARY_SCRIPT}" || {
  echo "FAIL: canary script should prefer triggering actor for trust subject dispatch" >&2
  exit 1
}
grep -q 'actions/runs/\${GITHUB_RUN_ID}' "${CANARY_SCRIPT}" || {
  echo "FAIL: canary script should resolve triggering actor from run metadata when actor is bot-like" >&2
  exit 1
}
grep -q 'CANARY_DISPATCH_OWNED="\${{ steps.ctx.outputs.canary_dispatch_owned }}"' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow should trust explicit caller-owned canary dispatch input" >&2
  exit 1
}
grep -q 'PERM="canary-bypass"' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow missing canary trust bypass marker" >&2
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
