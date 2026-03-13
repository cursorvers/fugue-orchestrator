#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/harness/route-task-handoff.sh"
TMP_ROOT="${TMPDIR:-/tmp}"
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

assert_case() {
  local name="$1"
  local body="$2"
  local vote_instruction="$3"
  local expected_mode="$4"
  local expected_request="$5"
  local expected_confirm="$6"
  local expect_implement_label="$7"
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
    "-f allow_processing_rerun=true" \
    "-f cost_provider_priority=codex,claude,glm,copilot,gemini,xai" \
    "-f cost_copilot_policy=low-cost-fallback-only" \
    "-f cost_metered_policy=overflow-or-tie-break-only" \
    "-f metered_reason=none" \
    "-f fallback_used=false" \
    "-f missing_lane=none" \
    "-f fallback_provider=none"
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

  echo "PASS [${name}]"
  passed=$((passed + 1))
}

echo "=== route-task-handoff.sh unit tests ==="
echo ""

assert_case "vote-default-implement" "通常タスク" "" "implement" "true" "true" "true"
assert_case "review-heading-wins" $'レビューのみでよい\n\n## Execution Mode\nreview' "" "review" "false" "false" "false"
assert_case "vote-instruction-review" "通常タスク" "review only" "review" "false" "false" "false"

assert_content_hints() {
  local out_file="${TMP_DIR}/content-hints.out"
  local workflow_line=""
  local gh_log=""

  total=$((total + 1))
  : > "${FAKE_GH_LOG}"
  jq -Rn '{title:"Task", body:"NotebookLM で調査結果を mind map にしたい", labels:[]}' > "${FAKE_ISSUE_JSON}"

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
      ISSUE_BODY="NotebookLM で調査結果を mind map にしたい" \
      COMMENT_BODY="/vote" \
      IS_VOTE_COMMAND="true" \
      VOTE_INSTRUCTION="" \
      TRUST_SUBJECT="masayuki" \
      DEFAULT_MAIN_ORCHESTRATOR_PROVIDER="codex" \
      DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER="claude" \
      CLAUDE_RATE_LIMIT_STATE="ok" \
      CLAUDE_MAIN_ASSIST_POLICY="codex" \
      CLAUDE_ROLE_POLICY="flex" \
      CLAUDE_DEGRADED_ASSIST_POLICY="claude" \
      bash "${SCRIPT}" >/dev/null 2>"${TMP_DIR}/content-hints.stderr"
  ); then
    echo "FAIL [content-hints]: script exited with error"
    failed=$((failed + 1))
    return
  fi

  workflow_line="$(grep 'workflow run fugue-tutti-caller.yml' "${FAKE_GH_LOG}" | tail -n1 || true)"
  for expected in \
    "-f content_hint_applied=true" \
    "-f content_action_hint=notebooklm-visual-brief" \
    "-f content_skill_hint=notebooklm-visual-brief" \
    "-f content_reason=notebooklm-visual-request"
  do
    if [[ "${workflow_line}" != *"${expected}"* ]]; then
      echo "FAIL [content-hints]: workflow dispatch missing '${expected}'"
      failed=$((failed + 1))
      return
    fi
  done

  gh_log="$(cat "${FAKE_GH_LOG}" || true)"
  for expected in \
    "--add-label content:notebooklm" \
    "--add-label content-action:notebooklm-visual-brief"
  do
    if [[ "${gh_log}" != *"${expected}"* ]]; then
      echo "FAIL [content-hints]: missing label mutation '${expected}'"
      failed=$((failed + 1))
      return
    fi
  done

  echo "PASS [content-hints]"
  passed=$((passed + 1))
}

assert_content_slide_prep_hints() {
  local out_file="${TMP_DIR}/content-slide-prep.out"
  local workflow_line=""
  local gh_log=""

  total=$((total + 1))
  : > "${FAKE_GH_LOG}"
  jq -Rn '{title:"Task", body:"NotebookLM で slide draft を作りたい", labels:[]}' > "${FAKE_ISSUE_JSON}"

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
      ISSUE_BODY="NotebookLM で slide draft を作りたい" \
      COMMENT_BODY="/vote" \
      IS_VOTE_COMMAND="true" \
      VOTE_INSTRUCTION="" \
      TRUST_SUBJECT="masayuki" \
      DEFAULT_MAIN_ORCHESTRATOR_PROVIDER="codex" \
      DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER="claude" \
      CLAUDE_RATE_LIMIT_STATE="ok" \
      CLAUDE_MAIN_ASSIST_POLICY="codex" \
      CLAUDE_ROLE_POLICY="flex" \
      CLAUDE_DEGRADED_ASSIST_POLICY="claude" \
      bash "${SCRIPT}" >/dev/null 2>"${TMP_DIR}/content-slide-prep.stderr"
  ); then
    echo "FAIL [content-slide-prep-hints]: script exited with error"
    failed=$((failed + 1))
    return
  fi

  workflow_line="$(grep 'workflow run fugue-tutti-caller.yml' "${FAKE_GH_LOG}" | tail -n1 || true)"
  for expected in \
    "-f content_hint_applied=true" \
    "-f content_action_hint=notebooklm-slide-prep" \
    "-f content_skill_hint=notebooklm-slide-prep" \
    "-f content_reason=notebooklm-slide-prep-request"
  do
    if [[ "${workflow_line}" != *"${expected}"* ]]; then
      echo "FAIL [content-slide-prep-hints]: workflow dispatch missing '${expected}'"
      failed=$((failed + 1))
      return
    fi
  done

  gh_log="$(cat "${FAKE_GH_LOG}" || true)"
  for expected in \
    "--add-label content:notebooklm" \
    "--add-label content-action:notebooklm-slide-prep"
  do
    if [[ "${gh_log}" != *"${expected}"* ]]; then
      echo "FAIL [content-slide-prep-hints]: missing label mutation '${expected}'"
      failed=$((failed + 1))
      return
    fi
  done

  echo "PASS [content-slide-prep-hints]"
  passed=$((passed + 1))
}

assert_snapshot_override() {
  local out_file="${TMP_DIR}/snapshot-override.out"
  local workflow_line=""

  total=$((total + 1))
  : > "${FAKE_GH_LOG}"
  jq -Rn '{title:"Task", body:"通常タスク", labels:[]}' > "${FAKE_ISSUE_JSON}"

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
      ISSUE_BODY="通常タスク" \
      COMMENT_BODY="/vote" \
      IS_VOTE_COMMAND="true" \
      VOTE_INSTRUCTION="" \
      TRUST_SUBJECT="masayuki" \
      DEFAULT_MAIN_ORCHESTRATOR_PROVIDER="codex" \
      DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER="claude" \
      CLAUDE_RATE_LIMIT_STATE="ok" \
      CLAUDE_MAIN_ASSIST_POLICY="codex" \
      CLAUDE_ROLE_POLICY="flex" \
      CLAUDE_DEGRADED_ASSIST_POLICY="claude" \
      METERED_REASON="overflow" \
      FALLBACK_USED="true" \
      MISSING_LANE="glm" \
      FALLBACK_PROVIDER="gemini" \
      FALLBACK_REASON="glm lane failed" \
      bash "${SCRIPT}" >/dev/null 2>"${TMP_DIR}/snapshot-override.stderr"
  ); then
    echo "FAIL [snapshot-override]: script exited with error"
    failed=$((failed + 1))
    return
  fi

  workflow_line="$(grep 'workflow run fugue-tutti-caller.yml' "${FAKE_GH_LOG}" | tail -n1 || true)"
  for expected in \
    "-f metered_reason=overflow" \
    "-f fallback_used=true" \
    "-f missing_lane=glm" \
    "-f fallback_provider=gemini" \
    "-f fallback_reason=glm lane failed"
  do
    if [[ "${workflow_line}" != *"${expected}"* ]]; then
      echo "FAIL [snapshot-override]: workflow dispatch missing '${expected}'"
      failed=$((failed + 1))
      return
    fi
  done

  echo "PASS [snapshot-override]"
  passed=$((passed + 1))
}

assert_snapshot_override
assert_content_hints
assert_content_slide_prep_hints

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
