#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/harness/route-task-handoff.sh"
TMP_ROOT="/Users/masayuki/Dev/tmp"
if [[ ! -d "${TMP_ROOT}" ]]; then
  TMP_ROOT="${TMPDIR:-/tmp}"
fi
mkdir -p "${TMP_ROOT}"
TMP_DIR="$(mktemp -d "${TMP_ROOT%/}/route-task-handoff.XXXXXX")"
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

assert_content_label_case() {
  local name="$1"
  local body="$2"
  local expected_label="$3"
  local out_file="${TMP_DIR}/${name}.out"

  total=$((total + 1))
  : > "${FAKE_GH_LOG}"
  jq -Rn --arg body "${body}" '{title:"Task", body:$body, labels:[]}' > "${FAKE_ISSUE_JSON}"

  if ! (
    cd "${ROOT_DIR}"
    env \
      PATH="${FAKE_BIN}:${PATH}" \
      FAKE_GH_LOG="${FAKE_GH_LOG}" \
      FAKE_ISSUE_JSON="${FAKE_ISSUE_JSON}" \
      GH_TOKEN="test-token" \
      GITHUB_OUTPUT="${out_file}" \
      GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
      GITHUB_RUN_ID="101" \
      GITHUB_RUN_ATTEMPT="1" \
      ISSUE_NUMBER="1" \
      ISSUE_TITLE="Task" \
      ISSUE_BODY="${body}" \
      COMMENT_BODY="/vote" \
      IS_VOTE_COMMAND="true" \
      VOTE_INSTRUCTION="" \
      EXECUTION_MODE_OVERRIDE_INPUT="auto" \
      TRUST_SUBJECT="masayuki" \
      DEFAULT_MAIN_ORCHESTRATOR_PROVIDER="codex" \
      DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER="claude" \
      CLAUDE_RATE_LIMIT_STATE="ok" \
      CLAUDE_MAIN_ASSIST_POLICY="codex" \
      CLAUDE_ROLE_POLICY="flex" \
      CLAUDE_DEGRADED_ASSIST_POLICY="claude" \
      bash "${SCRIPT}" >/dev/null 2>"${TMP_DIR}/${name}.stderr"
  ); then
    echo "FAIL [${name}]: script exited with error"
    failed=$((failed + 1))
    return
  fi

  if ! grep -Eq -- "--add-label ${expected_label}([[:space:]]|$)" "${FAKE_GH_LOG}"; then
    echo "FAIL [${name}]: missing ${expected_label}"
    failed=$((failed + 1))
    return
  fi

  echo "PASS [${name}]"
  passed=$((passed + 1))
}

assert_case() {
  local name="$1"
  local body="$2"
  local vote_instruction="$3"
  local expected_mode="$4"
  local expected_request="$5"
  local expected_confirm="$6"
  local expect_implement_label="$7"
  local execution_mode_override="${8:-auto}"
  local expected_dispatch_override="${9:-${execution_mode_override}}"
  local kernel_run_id_input="${10:-}"
  local out_file="${TMP_DIR}/${name}.out"
  local actual_mode=""
  local workflow_line=""

  total=$((total + 1))
  : > "${FAKE_GH_LOG}"
  jq -Rn --arg body "${body}" '{title:"Task", body:$body, labels:[]}' > "${FAKE_ISSUE_JSON}"

  if ! (
    cd "${ROOT_DIR}"
    env \
      PATH="${FAKE_BIN}:${PATH}" \
      FAKE_GH_LOG="${FAKE_GH_LOG}" \
      FAKE_ISSUE_JSON="${FAKE_ISSUE_JSON}" \
      GH_TOKEN="test-token" \
      GITHUB_OUTPUT="${out_file}" \
      GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
      GITHUB_RUN_ID="101" \
      GITHUB_RUN_ATTEMPT="1" \
      ISSUE_NUMBER="1" \
      ISSUE_TITLE="Task" \
      ISSUE_BODY="${body}" \
      COMMENT_BODY="/vote" \
      IS_VOTE_COMMAND="true" \
      VOTE_INSTRUCTION="${vote_instruction}" \
      KERNEL_RUN_ID_INPUT="${kernel_run_id_input}" \
      EXECUTION_MODE_OVERRIDE_INPUT="${execution_mode_override}" \
      TRUST_SUBJECT="masayuki" \
      DEFAULT_MAIN_ORCHESTRATOR_PROVIDER="codex" \
      DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER="claude" \
      CLAUDE_RATE_LIMIT_STATE="ok" \
      CLAUDE_MAIN_ASSIST_POLICY="codex" \
      CLAUDE_ROLE_POLICY="flex" \
      CLAUDE_DEGRADED_ASSIST_POLICY="claude" \
      bash "${SCRIPT}" >/dev/null 2>"${TMP_DIR}/${name}.stderr"
  ); then
    echo "FAIL [${name}]: script exited with error"
    failed=$((failed + 1))
    return
  fi

  actual_mode="$(grep -E '^mode=' "${out_file}" | head -n1 | cut -d= -f2- || true)"
  if [[ "${actual_mode}" != "${expected_mode}" ]]; then
    echo "FAIL [${name}]: mode=${actual_mode} (expected ${expected_mode})"
    failed=$((failed + 1))
    return
  fi

  workflow_line="$(grep 'workflow run fugue-tutti-caller.yml' "${FAKE_GH_LOG}" | tail -n1 || true)"
  for expected in \
    "-f intake_source=" \
    "-f requested_execution_mode=${expected_mode}" \
    "-f implement_request=${expected_request}" \
    "-f implement_confirmed=${expected_confirm}" \
    "-f vote_command=true" \
    "-f allow_processing_rerun=true"
  do
    if [[ "${workflow_line}" != *"${expected}"* ]]; then
      echo "FAIL [${name}]: workflow dispatch missing '${expected}'"
      failed=$((failed + 1))
      return
    fi
  done

  if [[ "${expect_implement_label}" == "true" ]]; then
    if ! grep -Eq -- '--add-label implement([[:space:]]|$)' "${FAKE_GH_LOG}"; then
      echo "FAIL [${name}]: implement label was not added"
      failed=$((failed + 1))
      return
    fi
    if ! grep -Eq -- '--add-label implement-confirmed([[:space:]]|$)' "${FAKE_GH_LOG}"; then
      echo "FAIL [${name}]: implement-confirmed label was not added"
      failed=$((failed + 1))
      return
    fi
  else
    if grep -Eq -- '--add-label implement([[:space:]]|$)' "${FAKE_GH_LOG}"; then
      echo "FAIL [${name}]: implement label should not be added"
      failed=$((failed + 1))
      return
    fi
    if grep -Eq -- '--add-label implement-confirmed([[:space:]]|$)' "${FAKE_GH_LOG}"; then
      echo "FAIL [${name}]: implement-confirmed label should not be added"
      failed=$((failed + 1))
      return
    fi
  fi

  if [[ "${expected_dispatch_override}" == "auto" ]]; then
    if [[ "${workflow_line}" == *"-f execution_mode_override="* ]]; then
      echo "FAIL [${name}]: workflow dispatch should not include execution_mode_override"
      failed=$((failed + 1))
      return
    fi
  elif [[ "${workflow_line}" != *"-f execution_mode_override=${expected_dispatch_override}"* ]]; then
    echo "FAIL [${name}]: workflow dispatch missing execution_mode_override=${expected_dispatch_override}"
    failed=$((failed + 1))
    return
  fi

  if [[ -n "${kernel_run_id_input}" ]]; then
    if [[ "${workflow_line}" != *"-f kernel_run_id=${kernel_run_id_input}"* ]]; then
      echo "FAIL [${name}]: workflow dispatch missing kernel_run_id=${kernel_run_id_input}"
      failed=$((failed + 1))
      return
    fi
  elif [[ "${workflow_line}" == *"-f kernel_run_id="* ]]; then
    echo "FAIL [${name}]: workflow dispatch should not include kernel_run_id"
    failed=$((failed + 1))
    return
  fi

  if ! grep -Fq 'GitHub-hosted Tutti consensus starts now and continues development from the current issue state.' "${ROOT_DIR}/handoff-comment.md"; then
    echo "FAIL [${name}]: handoff comment missing continuation UX note"
    failed=$((failed + 1))
    return
  fi

  echo "PASS [${name}]"
  passed=$((passed + 1))
}

echo "=== route-task-handoff.sh unit tests ==="
echo ""

assert_case "vote-default-implement" "通常タスク" "" "implement" "true" "true" "true" "auto" "primary"
assert_case "review-heading-wins" $'レビューのみでよい\n\n## Execution Mode\nreview' "" "review" "false" "false" "false" "auto" "primary"
assert_case "vote-instruction-review" "通常タスク" "review only" "review" "false" "false" "false" "auto" "primary"
assert_case "backup-heavy-override-passthrough" "通常タスク" "" "implement" "true" "true" "true" "backup-heavy" "backup-heavy"
assert_case "kernel-run-id-passthrough" "通常タスク" "" "implement" "true" "true" "true" "auto" "primary" "run-kernel-123"
assert_content_label_case "company-deck-content-label" "外出先から会社紹介スライドを作って" "content-action:company-deck"

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
