#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
SCRIPT="${SCRIPT_DIR}/scripts/harness/resolve-orchestration-context.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fake_gh="${tmp_dir}/gh"
fake_patch_log="${tmp_dir}/gh-patch.log"
fake_curl="${tmp_dir}/curl"
fake_curl_log="${tmp_dir}/curl.log"
cat > "${fake_gh}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "api" ]]; then
  endpoint="${2:-}"
  if [[ "${3:-}" == "--method" && "${4:-}" == "PATCH" ]]; then
    printf 'PATCH %s\n' "$*" >> "${FAKE_GH_PATCH_LOG:?}"
    exit 0
  fi
  case "${endpoint}" in
    repos/cursorvers/fugue-orchestrator/issues/123)
      cat <<'JSON'
{"title":"会議前に agenda と linked docs を確認したい","body":"未読メールも triage したい\n\n## Execution Mode\nreview","url":"https://github.com/cursorvers/fugue-orchestrator/issues/123","labels":[{"name":"fugue-task"},{"name":"tutti"}]}
JSON
      exit 0
      ;;
    repos/cursorvers/fugue-orchestrator/issues/124)
      cat <<'JSON'
{"title":"通常のレビュー","body":"テストを実行して結果をまとめる","url":"https://github.com/cursorvers/fugue-orchestrator/issues/124","labels":[{"name":"fugue-task"},{"name":"tutti"}]}
JSON
      exit 0
      ;;
    repos/cursorvers/fugue-orchestrator/issues/125)
      cat <<'JSON'
{"title":"外出先から会社紹介スライドを作って","body":"note記事の原稿ではなく、営業向け deck を作りたい","url":"https://github.com/cursorvers/fugue-orchestrator/issues/125","labels":[{"name":"fugue-task"},{"name":"tutti"}]}
JSON
      exit 0
      ;;
    repos/cursorvers/fugue-orchestrator/issues/126)
      cat <<'JSON'
{"title":"review mode should win","body":"既存の実装ラベルは無視したい\n\n## Execution Mode\nreview","url":"https://github.com/cursorvers/fugue-orchestrator/issues/126","labels":[{"name":"fugue-task"},{"name":"tutti"},{"name":"implement"},{"name":"implement-confirmed"}]}
JSON
      exit 0
      ;;
    repos/cursorvers/fugue-orchestrator/issues/127)
      cat <<'JSON'
{"title":"handoff snapshot should survive label lag","body":"通常の実装 issue","url":"https://github.com/cursorvers/fugue-orchestrator/issues/127","labels":[{"name":"fugue-task"},{"name":"tutti"}]}
JSON
      exit 0
      ;;
    repos/cursorvers/fugue-orchestrator/issues/128)
      cat <<'JSON'
{"title":"請求書と支払期日を確認したい","body":"経費精算の状況も見たい","url":"https://github.com/cursorvers/fugue-orchestrator/issues/128","labels":[{"name":"fugue-task"},{"name":"tutti"}]}
JSON
      exit 0
      ;;
    repos/cursorvers/fugue-orchestrator/issues/129)
      cat <<'JSON'
{"title":"freeeで請求書を作成して支払を確定したい","body":"承認が必要なら止めてよい","url":"https://github.com/cursorvers/fugue-orchestrator/issues/129","labels":[{"name":"fugue-task"},{"name":"tutti"}]}
JSON
      exit 0
      ;;
    repos/cursorvers/fugue-orchestrator/issues/130)
      cat <<'JSON'
{"title":"translation should not patch skipped issue","body":"曖昧によろしくお願いします","url":"https://github.com/cursorvers/fugue-orchestrator/issues/130","labels":[{"name":"plain-issue"}]}
JSON
      exit 0
      ;;
    repos/cursorvers/fugue-orchestrator/issues/131)
      cat <<'JSON'
{"title":"NotebookLM で調査結果を mind map にしたい","body":"notebooklm を使って論点を図式化したい","url":"https://github.com/cursorvers/fugue-orchestrator/issues/131","labels":[{"name":"fugue-task"},{"name":"tutti"}]}
JSON
      exit 0
      ;;
    repos/cursorvers/fugue-orchestrator/issues/132)
      cat <<'JSON'
{"title":"NotebookLM で slide draft を作りたい","body":"notebooklm で営業向けスライド下書きと speaker notes の叩き台を作る","url":"https://github.com/cursorvers/fugue-orchestrator/issues/132","labels":[{"name":"fugue-task"},{"name":"tutti"}]}
JSON
      exit 0
      ;;
    repos/cursorvers/fugue-orchestrator/actions/runners?per_page=100)
      cat <<'JSON'
{"runners":[]}
JSON
      exit 0
      ;;
    *)
      echo "{}"
      exit 0
      ;;
  esac
fi

echo "unsupported fake gh invocation" >&2
exit 1
EOF
chmod +x "${fake_gh}"

cat > "${fake_curl}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output_file=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output_file="$2"
      shift 2
      ;;
    http*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "${FAKE_CURL_LOG:-}" && -n "${url}" ]]; then
  printf '%s\n' "${url}" >> "${FAKE_CURL_LOG}"
fi

if [[ "${url}" == "https://api.openai.com/v1/chat/completions" ]]; then
  printf '%s\n' '{"choices":[{"message":{"content":"{\"score\":95,\"should_translate\":true,\"reason\":\"translation-needed\",\"signals\":[\"ambiguous\"]}"}}]}' > "${output_file}"
  printf '200'
  exit 0
fi

if [[ "${url}" == "https://api.anthropic.com/v1/messages" ]]; then
  printf '%s\n' '{"content":[{"type":"text","text":"{\"task_summary\":\"summary\",\"goal\":\"goal\",\"constraints\":[],\"acceptance_criteria\":[],\"risks\":[],\"open_questions\":[],\"execution_mode_hint\":\"review\"}"}]}' > "${output_file}"
  printf '200'
  exit 0
fi

printf '%s\n' '{"error":{"message":"unexpected request"}}' > "${output_file}"
printf '500'
EOF
chmod +x "${fake_curl}"

assert_output() {
  local test_name="$1"
  local issue_number="$2"
  local field="$3"
  local expected="$4"
  shift 4
  local -a extra_env=("$@")
  local out_file="${tmp_dir}/${test_name}.out"
  local -a env_args=(
    "PATH=${tmp_dir}:${PATH}"
    "GITHUB_EVENT_NAME=issues"
    "GITHUB_REPOSITORY=cursorvers/fugue-orchestrator"
    "ISSUE_NUMBER_FROM_ISSUE=${issue_number}"
    "ISSUE_NUMBER_FROM_DISPATCH="
    "GITHUB_OUTPUT=${out_file}"
    "CI_EXECUTION_ENGINE=api"
    "CLAUDE_TRANSLATOR_MODE=off"
    "DEFAULT_MAIN_ORCHESTRATOR_PROVIDER=codex"
    "DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER=claude"
    "CLAUDE_MAIN_ASSIST_POLICY=codex"
    "CLAUDE_DEGRADED_ASSIST_POLICY=claude"
    "CLAUDE_ROLE_POLICY=flex"
    "FAKE_GH_PATCH_LOG=${fake_patch_log}"
    "FAKE_CURL_LOG=${fake_curl_log}"
  )

  total=$((total + 1))
  env_args[5]="GITHUB_OUTPUT=${out_file}"
  if [[ "${#extra_env[@]}" -gt 0 ]]; then
    env_args+=("${extra_env[@]}")
  fi

  if ! env "${env_args[@]}" bash "${SCRIPT}" >/dev/null 2>"${tmp_dir}/${test_name}.stderr"; then
    echo "FAIL [${test_name}]: script exited with error"
    failed=$((failed + 1))
    return
  fi

  local actual
  actual="$(grep -E "^${field}=" "${out_file}" | head -n1 | cut -d= -f2- || true)"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL [${test_name}]: ${field}=${actual}(expected ${expected})"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  fi
}

echo "=== resolve-orchestration-context.sh unit tests ==="
echo ""

assert_output "workspace-hint-applied" "123" "workspace_hint_applied" "true"
assert_output "workspace-action-hint" "123" "workspace_action_hint" "meeting-prep,gmail-triage"
assert_output "workspace-domain-hint" "123" "workspace_domain_hint" "calendar,drive,docs,gmail"
assert_output "workspace-phase-hint" "123" "workspace_suggested_phases" "preflight-enrich"
assert_output "workspace-readonly-actions" "123" "workspace_readonly_actions" "meeting-prep,gmail-triage"
assert_output "workspace-none" "124" "workspace_hint_applied" "false"
assert_output "freee-hint-applied" "128" "freee_hint_applied" "true"
assert_output "freee-action-hint" "128" "freee_action_hint" "company-profile,invoice-status,expense-claim-status,payment-due-summary"
assert_output "freee-domain-hint" "128" "freee_domain_hint" "company,invoice,expense-claim,payment"
assert_output "freee-phase-hint" "128" "freee_suggested_phases" "preflight-enrich,recovery-rehydrate"
assert_output "freee-readonly-actions" "128" "freee_readonly_actions" "company-profile,invoice-status,expense-claim-status,payment-due-summary"
assert_output "freee-write-approval-actions" "129" "freee_approval_required_actions" "invoice-create-handoff,payment-confirmation-handoff"
assert_output "content-hint-applied" "125" "content_hint_applied" "true"
assert_output "content-action-hint" "125" "content_action_hint" "slide-deck"
assert_output "content-skill-hint" "125" "content_skill_hint" "slide"
assert_output "notebooklm-visual-hint-applied" "131" "content_hint_applied" "true"
assert_output "notebooklm-visual-action-hint" "131" "content_action_hint" "notebooklm-visual-brief"
assert_output "notebooklm-visual-skill-hint" "131" "content_skill_hint" "notebooklm-visual-brief"
assert_output "notebooklm-visual-reason" "131" "content_reason" "notebooklm-visual-request"
assert_output "notebooklm-slide-prep-hint-applied" "132" "content_hint_applied" "true"
assert_output "notebooklm-slide-prep-action-hint" "132" "content_action_hint" "notebooklm-slide-prep"
assert_output "notebooklm-slide-prep-skill-hint" "132" "content_skill_hint" "notebooklm-slide-prep"
assert_output "notebooklm-slide-prep-reason" "132" "content_reason" "notebooklm-slide-prep-request"
assert_output "workflow-dispatch-content-snapshot-action" "124" "content_action_hint" "notebooklm-visual-brief" \
  "GITHUB_EVENT_NAME=workflow_dispatch" \
  "ISSUE_NUMBER_FROM_ISSUE=" \
  "ISSUE_NUMBER_FROM_DISPATCH=124" \
  "CONTENT_HINT_APPLIED_INPUT=true" \
  "CONTENT_ACTION_HINT_INPUT=notebooklm-visual-brief" \
  "CONTENT_SKILL_HINT_INPUT=notebooklm-visual-brief" \
  "CONTENT_REASON_INPUT=notebooklm-visual-request"
assert_output "workflow-dispatch-content-snapshot-skill" "124" "content_skill_hint" "notebooklm-visual-brief" \
  "GITHUB_EVENT_NAME=workflow_dispatch" \
  "ISSUE_NUMBER_FROM_ISSUE=" \
  "ISSUE_NUMBER_FROM_DISPATCH=124" \
  "CONTENT_HINT_APPLIED_INPUT=true" \
  "CONTENT_ACTION_HINT_INPUT=notebooklm-visual-brief" \
  "CONTENT_SKILL_HINT_INPUT=notebooklm-visual-brief" \
  "CONTENT_REASON_INPUT=notebooklm-visual-request"
assert_output "workflow-dispatch-content-snapshot-reason" "124" "content_reason" "notebooklm-visual-request" \
  "GITHUB_EVENT_NAME=workflow_dispatch" \
  "ISSUE_NUMBER_FROM_ISSUE=" \
  "ISSUE_NUMBER_FROM_DISPATCH=124" \
  "CONTENT_HINT_APPLIED_INPUT=true" \
  "CONTENT_ACTION_HINT_INPUT=notebooklm-visual-brief" \
  "CONTENT_SKILL_HINT_INPUT=notebooklm-visual-brief" \
  "CONTENT_REASON_INPUT=notebooklm-visual-request"
assert_output "review-heading-clears-implement" "126" "has_implement_request" "false"
assert_output "review-heading-clears-confirm" "126" "has_implement_confirmed" "false"
assert_output "handoff-mode-override" "127" "has_implement_request" "true" \
  "REQUESTED_EXECUTION_MODE_INPUT=implement" \
  "IMPLEMENT_REQUEST_INPUT=true"
assert_output "handoff-confirm-override" "127" "has_implement_confirmed" "true" \
  "REQUESTED_EXECUTION_MODE_INPUT=implement" \
  "IMPLEMENT_REQUEST_INPUT=true" \
  "IMPLEMENT_CONFIRMED_INPUT=true"
assert_output "vote-command-output" "127" "vote_command" "true" \
  "VOTE_COMMAND_INPUT=true"
assert_output "vote-intake-source-derived" "127" "intake_source" "github-vote-comment" \
  "VOTE_COMMAND_INPUT=true"
assert_output "vote-command-preflight-cycles" "127" "preflight_cycles" "3" \
  "VOTE_COMMAND_INPUT=true"
assert_output "workflow-dispatch-intake-source" "127" "intake_source" "workflow-dispatch" \
  "GITHUB_EVENT_NAME=workflow_dispatch" \
  "ISSUE_NUMBER_FROM_ISSUE=" \
  "ISSUE_NUMBER_FROM_DISPATCH=127"
assert_output "explicit-intake-source" "127" "intake_source" "railway-public-edge" \
  "INTAKE_SOURCE_INPUT=railway-public-edge"

test_translation_does_not_patch_skipped_issue() {
  total=$((total + 1))
  : > "${fake_patch_log}"
  : > "${fake_curl_log}"
  local out_file="${tmp_dir}/translation-skip.out"
  if ! env \
    "PATH=${tmp_dir}:${PATH}" \
    "GITHUB_EVENT_NAME=issues" \
    "GITHUB_REPOSITORY=cursorvers/fugue-orchestrator" \
    "ISSUE_NUMBER_FROM_ISSUE=130" \
    "ISSUE_NUMBER_FROM_DISPATCH=" \
    "GITHUB_OUTPUT=${out_file}" \
    "CI_EXECUTION_ENGINE=api" \
    "CLAUDE_TRANSLATOR_MODE=always" \
    "DEFAULT_MAIN_ORCHESTRATOR_PROVIDER=codex" \
    "DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER=claude" \
    "CLAUDE_MAIN_ASSIST_POLICY=codex" \
    "CLAUDE_DEGRADED_ASSIST_POLICY=claude" \
    "CLAUDE_ROLE_POLICY=flex" \
    "OPENAI_API_KEY=dummy" \
    "ANTHROPIC_API_KEY=dummy" \
    "FAKE_GH_PATCH_LOG=${fake_patch_log}" \
    "FAKE_CURL_LOG=${fake_curl_log}" \
    bash "${SCRIPT}" >/dev/null 2>"${tmp_dir}/translation-skip.stderr"; then
    echo "FAIL [translation-skip-no-patch]: script exited with error"
    failed=$((failed + 1))
    return
  fi
  local should_run
  should_run="$(grep -E '^should_run=' "${out_file}" | head -n1 | cut -d= -f2- || true)"
  if [[ "${should_run}" != "false" ]]; then
    echo "FAIL [translation-skip-no-patch]: should_run=${should_run}(expected false)"
    failed=$((failed + 1))
    return
  fi
  if [[ -s "${fake_patch_log}" ]]; then
    echo "FAIL [translation-skip-no-patch]: unexpected PATCH on skipped issue"
    failed=$((failed + 1))
    return
  fi
  if [[ -s "${fake_curl_log}" ]]; then
    echo "FAIL [translation-skip-no-patch]: unexpected translation API call on skipped issue"
    failed=$((failed + 1))
    return
  fi
  echo "PASS [translation-skip-no-patch]"
  passed=$((passed + 1))
}

test_translation_does_not_patch_skipped_issue

test_translation_does_not_call_llm_when_subscription_hold_offline() {
  total=$((total + 1))
  : > "${fake_patch_log}"
  : > "${fake_curl_log}"
  local out_file="${tmp_dir}/translation-subscription-hold.out"
  if ! env \
    "PATH=${tmp_dir}:${PATH}" \
    "GITHUB_EVENT_NAME=issues" \
    "GITHUB_REPOSITORY=cursorvers/fugue-orchestrator" \
    "ISSUE_NUMBER_FROM_ISSUE=123" \
    "ISSUE_NUMBER_FROM_DISPATCH=" \
    "GITHUB_OUTPUT=${out_file}" \
    "CI_EXECUTION_ENGINE=subscription" \
    "SUBSCRIPTION_OFFLINE_POLICY=hold" \
    "SUBSCRIPTION_RUNNER_LABEL=fugue-subscription" \
    "CLAUDE_TRANSLATOR_MODE=always" \
    "DEFAULT_MAIN_ORCHESTRATOR_PROVIDER=codex" \
    "DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER=claude" \
    "CLAUDE_MAIN_ASSIST_POLICY=codex" \
    "CLAUDE_DEGRADED_ASSIST_POLICY=claude" \
    "CLAUDE_ROLE_POLICY=flex" \
    "OPENAI_API_KEY=dummy" \
    "ANTHROPIC_API_KEY=dummy" \
    "FAKE_GH_PATCH_LOG=${fake_patch_log}" \
    "FAKE_CURL_LOG=${fake_curl_log}" \
    bash "${SCRIPT}" >/dev/null 2>"${tmp_dir}/translation-subscription-hold.stderr"; then
    echo "FAIL [translation-subscription-hold-no-llm]: script exited with error"
    failed=$((failed + 1))
    return
  fi
  local should_run
  should_run="$(grep -E '^should_run=' "${out_file}" | head -n1 | cut -d= -f2- || true)"
  if [[ "${should_run}" != "false" ]]; then
    echo "FAIL [translation-subscription-hold-no-llm]: should_run=${should_run}(expected false)"
    failed=$((failed + 1))
    return
  fi
  if [[ -s "${fake_patch_log}" || -s "${fake_curl_log}" ]]; then
    echo "FAIL [translation-subscription-hold-no-llm]: unexpected external calls during hold/offline skip"
    failed=$((failed + 1))
    return
  fi
  echo "PASS [translation-subscription-hold-no-llm]"
  passed=$((passed + 1))
}

test_translation_does_not_call_llm_when_subscription_hold_offline

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
