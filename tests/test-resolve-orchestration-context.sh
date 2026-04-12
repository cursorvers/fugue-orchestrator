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
cat > "${fake_gh}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "api" ]]; then
  endpoint="${2:-}"
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
{"title":"[canary-lite] regular claude-main request 20260309061800","body":"## Canary\nAutomated orchestration canary.\n","url":"https://github.com/cursorvers/fugue-orchestrator/issues/128","labels":[{"name":"fugue-task"}]}
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
assert_output "content-hint-applied" "125" "content_hint_applied" "true"
assert_output "content-action-hint" "125" "content_action_hint" "slide-deck,company-deck"
assert_output "content-skill-hint" "125" "content_skill_hint" "slide"
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
assert_output "workflow-dispatch-intake-source" "127" "intake_source" "workflow-dispatch" \
  "GITHUB_EVENT_NAME=workflow_dispatch" \
  "ISSUE_NUMBER_FROM_ISSUE=" \
  "ISSUE_NUMBER_FROM_DISPATCH=127"
assert_output "explicit-intake-source" "127" "intake_source" "railway-public-edge" \
  "INTAKE_SOURCE_INPUT=railway-public-edge"
assert_output "canary-trust-subject-preserved" "128" "trust_subject" "app/github-actions" \
  "GITHUB_EVENT_NAME=workflow_dispatch" \
  "ISSUE_NUMBER_FROM_ISSUE=" \
  "ISSUE_NUMBER_FROM_DISPATCH=128" \
  "CANARY_DISPATCH_RUN_ID_INPUT=22840953864" \
  "TRUST_SUBJECT_INPUT=app/github-actions"

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
