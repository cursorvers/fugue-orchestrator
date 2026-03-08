#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANARY_SCRIPT="${ROOT_DIR}/scripts/harness/run-canary.sh"
CANARY_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-orchestrator-canary.yml"
ROUTER_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml"
TASK_ROUTER_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-task-router.yml"
CALLER_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-caller.yml"
RESOLVE_CONTEXT_SCRIPT="${ROOT_DIR}/scripts/harness/resolve-orchestration-context.sh"
COMMENT_SCRIPT="${ROOT_DIR}/scripts/harness/generate-tutti-comment.sh"
HEARTBEAT_SCRIPT="${ROOT_DIR}/scripts/lib/resolve-primary-heartbeat-state.sh"

if [[ ! -x "${CANARY_SCRIPT}" ]]; then
  echo "FAIL: missing executable script ${CANARY_SCRIPT}" >&2
  exit 1
fi

if [[ ! -x "${HEARTBEAT_SCRIPT}" ]]; then
  echo "FAIL: missing executable script ${HEARTBEAT_SCRIPT}" >&2
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
head -n 8 "${CALLER_WORKFLOW}" | grep -q 'types: \[labeled\]' || {
  echo "FAIL: fugue-caller should start issue flow only from labeled issues" >&2
  exit 1
}
if head -n 8 "${CALLER_WORKFLOW}" | grep -q 'opened'; then
  echo "FAIL: fugue-caller should not auto-start from opened issues" >&2
  exit 1
fi
grep -Fq "trigger_label_name: \${{ github.event.inputs.trigger_label_name || github.event.label.name || '' }}" "${CALLER_WORKFLOW}" || {
  echo "FAIL: fugue-caller should pass the triggering label or explicit replay override into task router" >&2
  exit 1
}
grep -Fq "allow_processing_rerun: \${{ github.event.inputs.allow_processing_rerun || 'false' }}" "${CALLER_WORKFLOW}" || {
  echo "FAIL: fugue-caller should pass allow_processing_rerun into task router" >&2
  exit 1
}
grep -Fq "subscription_offline_policy_override: \${{ github.event.inputs.subscription_offline_policy_override || '' }}" "${CALLER_WORKFLOW}" || {
  echo "FAIL: fugue-caller should pass offline policy override into task router" >&2
  exit 1
}
grep -Fq "handoff_target: \${{ github.event.inputs.handoff_target || '' }}" "${CALLER_WORKFLOW}" || {
  echo "FAIL: fugue-caller should pass handoff_target override into task router" >&2
  exit 1
}
grep -Fq "comment_body: \${{ github.event.comment.body || '' }}" "${CALLER_WORKFLOW}" || {
  echo "FAIL: fugue-caller should pass issue_comment body into task router" >&2
  exit 1
}
if sed -n '1,60p' "${TASK_ROUTER_WORKFLOW}" | grep -q '^  issues:'; then
  echo "FAIL: fugue-task-router should no longer expose direct issues triggers" >&2
  exit 1
fi
if sed -n '1,60p' "${TASK_ROUTER_WORKFLOW}" | grep -q '^  issue_comment:'; then
  echo "FAIL: fugue-task-router should no longer expose direct issue_comment triggers" >&2
  exit 1
fi
if sed -n '1,60p' "${TASK_ROUTER_WORKFLOW}" | grep -q '^  workflow_dispatch:'; then
  echo "FAIL: fugue-task-router should not be directly workflow_dispatch invokable" >&2
  exit 1
fi
grep -q 'EXPLICIT_TUTTI_TRIGGER="true"' "${TASK_ROUTER_WORKFLOW}" || {
  echo "FAIL: task router should recognize manual tutti label as an explicit trigger" >&2
  exit 1
}
grep -q 'ALLOW_PROCESSING_RERUN_INPUT' "${TASK_ROUTER_WORKFLOW}" || {
  echo "FAIL: task router should accept allow_processing_rerun from caller" >&2
  exit 1
}
if grep -q 'github\.event\.inputs' "${TASK_ROUTER_WORKFLOW}"; then
  echo "FAIL: task router should rely on workflow_call inputs, not direct workflow_dispatch payloads" >&2
  exit 1
fi
if sed -n '1,40p' "${CANARY_WORKFLOW%orchestrator-canary.yml}tutti-caller.yml" | grep -q '^  issues:'; then
  echo "FAIL: fugue-tutti-caller should be explicit-dispatch only" >&2
  exit 1
fi
grep -q 'HAS_FUGUE}" != "true" && "${IS_VOTE_COMMAND}" != "true"' "${TASK_ROUTER_WORKFLOW}" || {
  echo "FAIL: task router should allow /vote to bypass missing fugue-task label" >&2
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
grep -q 'if \[\[ "\${canary_dispatch_owned}" == "true" \]\]; then' "${ROUTER_WORKFLOW}" || {
  echo "FAIL: router workflow should trust explicit caller-owned canary dispatch input" >&2
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
