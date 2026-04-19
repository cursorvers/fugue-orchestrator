#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HANDOFF_SCRIPT="${ROOT_DIR}/scripts/harness/route-task-handoff.sh"
CTX_SCRIPT="${ROOT_DIR}/scripts/harness/resolve-orchestration-context.sh"
TMP_ROOT="/Users/masayuki/Dev/tmp"
if [[ ! -d "${TMP_ROOT}" ]]; then
  TMP_ROOT="${TMPDIR:-/tmp}"
fi
mkdir -p "${TMP_ROOT}"
TMP_DIR="$(mktemp -d "${TMP_ROOT%/}/vote-handoff-sim.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"; rm -f "${ROOT_DIR}/handoff-comment.md"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"
FAKE_GH_LOG="${TMP_DIR}/gh.log"
FAKE_ISSUE_JSON="${TMP_DIR}/issue.json"

cat > "${FAKE_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_GH_LOG}"

if [[ "${1:-}" == "api" && "${2:-}" == "repos/cursorvers/fugue-orchestrator/issues/1" ]]; then
  cat "${FAKE_ISSUE_JSON}"
  exit 0
fi

exit 0
EOF
chmod +x "${FAKE_BIN}/gh"

passed=0
failed=0
total=0

assert_field() {
  local file="$1"
  local field="$2"
  local expected="$3"
  local actual

  actual="$(grep -E "^${field}=" "${file}" | head -n1 | cut -d= -f2- || true)"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL: ${field}=${actual} (expected ${expected})"
    return 1
  fi
}

dispatch_value() {
  local line="$1"
  local key="$2"
  local -a args=()
  local i=0

  read -r -a args <<< "${line}"
  while (( i < ${#args[@]} )); do
    if [[ "${args[i]}" == "-f" && $((i + 1)) -lt ${#args[@]} ]]; then
      local kv="${args[i + 1]}"
      if [[ "${kv%%=*}" == "${key}" ]]; then
        printf '%s' "${kv#*=}"
        return 0
      fi
      i=$((i + 2))
      continue
    fi
    i=$((i + 1))
  done

  return 1
}

run_case() {
  local name="$1"
  local body="$2"
  local labels_json="$3"
  local vote_instruction="$4"
  local expected_mode="$5"
  local expected_request="$6"
  local expected_confirm="$7"
  local expect_vote_instruction="$8"
  local expected_execution_override="${9:-primary}"
  local handoff_out="${TMP_DIR}/${name}-handoff.out"
  local ctx_out="${TMP_DIR}/${name}-ctx.out"
  local dispatch_line=""
  local requested_execution_mode=""
  local implement_request=""
  local implement_confirmed=""
  local vote_command=""
  local vote_instruction_b64=""
  local allow_processing_rerun=""
  local handoff_target=""
  local execution_mode_override=""

  total=$((total + 1))
  : > "${FAKE_GH_LOG}"
  jq -n \
    --arg title "Task" \
    --arg body "${body}" \
    --argjson labels "${labels_json}" \
    '{title:$title, body:$body, labels:$labels}' > "${FAKE_ISSUE_JSON}"

  if ! (
    cd "${ROOT_DIR}"
    env \
      PATH="${FAKE_BIN}:${PATH}" \
      FAKE_GH_LOG="${FAKE_GH_LOG}" \
      FAKE_ISSUE_JSON="${FAKE_ISSUE_JSON}" \
      GH_TOKEN="test-token" \
      GITHUB_OUTPUT="${handoff_out}" \
      GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
      GITHUB_RUN_ID="201" \
      GITHUB_RUN_ATTEMPT="1" \
      ISSUE_NUMBER="1" \
      ISSUE_TITLE="Task" \
      ISSUE_BODY="${body}" \
      COMMENT_BODY="/vote" \
      IS_VOTE_COMMAND="true" \
      VOTE_INSTRUCTION="${vote_instruction}" \
      TRUST_SUBJECT="masayuki" \
      DEFAULT_MAIN_ORCHESTRATOR_PROVIDER="codex" \
      DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER="claude" \
      CLAUDE_RATE_LIMIT_STATE="ok" \
      CLAUDE_MAIN_ASSIST_POLICY="codex" \
      CLAUDE_ROLE_POLICY="flex" \
      CLAUDE_DEGRADED_ASSIST_POLICY="claude" \
      bash "${HANDOFF_SCRIPT}" >/dev/null 2>"${TMP_DIR}/${name}-handoff.stderr"
  ); then
    echo "FAIL [${name}]: handoff script exited with error"
    failed=$((failed + 1))
    return
  fi

  if ! assert_field "${handoff_out}" "mode" "${expected_mode}"; then
    echo "FAIL [${name}]: handoff mode mismatch"
    failed=$((failed + 1))
    return
  fi

  dispatch_line="$(grep 'workflow run fugue-tutti-caller.yml' "${FAKE_GH_LOG}" | tail -n1 || true)"
  if [[ -z "${dispatch_line}" ]]; then
    echo "FAIL [${name}]: missing workflow dispatch log"
    failed=$((failed + 1))
    return
  fi

  requested_execution_mode="$(dispatch_value "${dispatch_line}" "requested_execution_mode" || true)"
  implement_request="$(dispatch_value "${dispatch_line}" "implement_request" || true)"
  implement_confirmed="$(dispatch_value "${dispatch_line}" "implement_confirmed" || true)"
  vote_command="$(dispatch_value "${dispatch_line}" "vote_command" || true)"
  vote_instruction_b64="$(dispatch_value "${dispatch_line}" "vote_instruction_b64" || true)"
  allow_processing_rerun="$(dispatch_value "${dispatch_line}" "allow_processing_rerun" || true)"
  handoff_target="$(dispatch_value "${dispatch_line}" "handoff_target" || true)"
  execution_mode_override="$(dispatch_value "${dispatch_line}" "execution_mode_override" || true)"

  if [[ "${requested_execution_mode}" != "${expected_mode}" || \
        "${implement_request}" != "${expected_request}" || \
        "${implement_confirmed}" != "${expected_confirm}" || \
        "${vote_command}" != "true" || \
        "${allow_processing_rerun}" != "true" || \
        "${handoff_target}" != "kernel" || \
        "${execution_mode_override}" != "${expected_execution_override}" ]]; then
    echo "FAIL [${name}]: unexpected dispatch snapshot"
    echo "  mode=${requested_execution_mode} request=${implement_request} confirm=${implement_confirmed} vote=${vote_command} rerun=${allow_processing_rerun} handoff=${handoff_target} exec_override=${execution_mode_override}"
    failed=$((failed + 1))
    return
  fi

  if [[ "${expect_vote_instruction}" == "true" && -z "${vote_instruction_b64}" ]]; then
    echo "FAIL [${name}]: expected vote_instruction_b64 in dispatch"
    failed=$((failed + 1))
    return
  fi
  if [[ "${expect_vote_instruction}" != "true" && -n "${vote_instruction_b64}" ]]; then
    echo "FAIL [${name}]: unexpected vote_instruction_b64 in dispatch"
    failed=$((failed + 1))
    return
  fi

  if ! env \
    PATH="${FAKE_BIN}:${PATH}" \
    FAKE_GH_LOG="${FAKE_GH_LOG}" \
    FAKE_ISSUE_JSON="${FAKE_ISSUE_JSON}" \
    GITHUB_EVENT_NAME="workflow_dispatch" \
    GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
    ISSUE_NUMBER_FROM_DISPATCH="1" \
    ISSUE_NUMBER_FROM_ISSUE="" \
    GITHUB_OUTPUT="${ctx_out}" \
    CI_EXECUTION_ENGINE="api" \
    CLAUDE_TRANSLATOR_MODE="off" \
    DEFAULT_MAIN_ORCHESTRATOR_PROVIDER="codex" \
    DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER="claude" \
    CLAUDE_MAIN_ASSIST_POLICY="codex" \
    CLAUDE_DEGRADED_ASSIST_POLICY="claude" \
    CLAUDE_ROLE_POLICY="flex" \
    TRUST_SUBJECT_INPUT="masayuki" \
    ALLOW_PROCESSING_RERUN_INPUT="${allow_processing_rerun}" \
    VOTE_INSTRUCTION_B64_INPUT="${vote_instruction_b64}" \
    REQUESTED_EXECUTION_MODE_INPUT="${requested_execution_mode}" \
    IMPLEMENT_REQUEST_INPUT="${implement_request}" \
    IMPLEMENT_CONFIRMED_INPUT="${implement_confirmed}" \
    VOTE_COMMAND_INPUT="${vote_command}" \
    HANDOFF_TARGET_INPUT="${handoff_target}" \
    bash "${CTX_SCRIPT}" >/dev/null 2>"${TMP_DIR}/${name}-ctx.stderr"; then
    echo "FAIL [${name}]: resolve context exited with error"
    failed=$((failed + 1))
    return
  fi

  if ! assert_field "${ctx_out}" "has_implement_request" "${expected_request}" || \
     ! assert_field "${ctx_out}" "has_implement_confirmed" "${expected_confirm}" || \
     ! assert_field "${ctx_out}" "vote_command" "true" || \
     ! assert_field "${ctx_out}" "allow_processing_rerun" "true"; then
    echo "FAIL [${name}]: resolved context mismatch"
    failed=$((failed + 1))
    return
  fi

  echo "PASS [${name}]"
  passed=$((passed + 1))
}

echo "=== /vote handoff simulation ==="
echo ""

run_case \
  "review-body-stale-labels" \
  $'レビューのみ\n\n## Execution Mode\nreview' \
  '[{"name":"implement"},{"name":"implement-confirmed"}]' \
  "" \
  "review" \
  "false" \
  "false" \
  "false"

run_case \
  "vote-instruction-review" \
  "通常タスク" \
  '[]' \
  "review only" \
  "review" \
  "false" \
  "false" \
  "true"

run_case \
  "default-implement-label-lag" \
  "通常タスク" \
  '[]' \
  "" \
  "implement" \
  "true" \
  "false" \
  "false"

run_case \
  "explicit-confirm-override" \
  $'通常タスク\n\n## Implementation Confirmation\nconfirmed' \
  '[]' \
  "" \
  "implement" \
  "true" \
  "true" \
  "false"

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
