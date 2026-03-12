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
{"title":"実装フェーズの不具合修正","body":"Mode: implement\n既存の検証は終わっているので /kernel で実装を進めて","url":"https://github.com/cursorvers/fugue-orchestrator/issues/126","labels":[{"name":"fugue-task"},{"name":"tutti"},{"name":"implement"},{"name":"implement-confirmed"}]}
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

  total=$((total + 1))
  local out_file="${tmp_dir}/${test_name}.out"

  if ! env \
    PATH="${tmp_dir}:${PATH}" \
    GITHUB_EVENT_NAME="issues" \
    GITHUB_REPOSITORY="cursorvers/fugue-orchestrator" \
    ISSUE_NUMBER_FROM_ISSUE="${issue_number}" \
    ISSUE_NUMBER_FROM_DISPATCH="" \
    GITHUB_OUTPUT="${out_file}" \
    CI_EXECUTION_ENGINE="api" \
    CLAUDE_TRANSLATOR_MODE="off" \
    DEFAULT_MAIN_ORCHESTRATOR_PROVIDER="codex" \
    DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER="claude" \
    CLAUDE_MAIN_ASSIST_POLICY="codex" \
    CLAUDE_DEGRADED_ASSIST_POLICY="claude" \
    CLAUDE_ROLE_POLICY="flex" \
    bash "${SCRIPT}" >/dev/null 2>"${tmp_dir}/${test_name}.stderr"; then
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
assert_output "content-action-hint" "125" "content_action_hint" "slide-deck"
assert_output "content-skill-hint" "125" "content_skill_hint" "slide"
assert_output "implement-execution-mode" "126" "execution_mode_effective" "implement"
assert_output "implement-phase" "126" "implementation_phase" "true"
assert_output "implement-claude-teams" "126" "claude_teams_allowed" "true"
assert_output "implement-claude-cap" "126" "claude_teams_member_cap" "2"

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
