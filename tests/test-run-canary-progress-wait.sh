#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANARY_SCRIPT="${ROOT_DIR}/scripts/harness/run-canary.sh"

mkdir -p "/Users/masayuki/Dev/tmp"
TMP_DIR="$(mktemp -d "/Users/masayuki/Dev/tmp/run-canary-progress.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_GH="${TMP_DIR}/gh"
COMMENT_LOG="${TMP_DIR}/comment.log"
STATE_DIR="${TMP_DIR}/state"
mkdir -p "${STATE_DIR}"

cat > "${FAKE_GH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${FAKE_GH_STATE_DIR:?}"
comment_log="${FAKE_GH_COMMENT_LOG:?}"

bump_counter() {
  local name="$1"
  local file="${state_dir}/${name}.count"
  local count=0
  if [[ -f "${file}" ]]; then
    count="$(cat "${file}")"
  fi
  count="$((count + 1))"
  printf '%s' "${count}" > "${file}"
  printf '%s\n' "${count}"
}

if [[ "${1:-}" == "issue" && "${2:-}" == "create" ]]; then
  printf '%s\n' "https://github.com/test/fugue-orchestrator/issues/900"
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  run_status_count="0"
  if [[ -f "${state_dir}/run_status.count" ]]; then
    run_status_count="$(cat "${state_dir}/run_status.count")"
  fi
  if (( run_status_count < 2 )); then
    echo "issue comment attempted before workflow run reached terminal state" >&2
    exit 97
  fi
  body=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --body)
        body="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  printf '%s\n' "${body}" >> "${comment_log}"
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "edit" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "close" ]]; then
  exit 0
fi

if [[ "${1:-}" == "issue" && "${2:-}" == "view" ]]; then
  if printf '%s\n' "$*" | grep -Fq -- '--json labels'; then
    printf '%s\n' "processing"
    exit 0
  fi
  if printf '%s\n' "$*" | grep -Fq -- '--json state'; then
    printf '%s\n' "OPEN"
    exit 0
  fi
  printf '%s\n' '{"number":900,"title":"canary","body":"body","url":"https://github.com/test/fugue-orchestrator/issues/900","labels":[{"name":"processing"}]}'
  exit 0
fi

if [[ "${1:-}" == "workflow" && "${2:-}" == "run" ]]; then
  exit 0
fi

if [[ "${1:-}" == "api" ]]; then
  endpoint="${2:-}"
  case "${endpoint}" in
    repos/test/fugue-orchestrator/actions/workflows/fugue-tutti-caller.yml/runs\?event=workflow_dispatch*)
      call="$(bump_counter workflow_runs)"
      if [[ "${call}" == "1" ]]; then
        printf '%s\n' '{"workflow_runs":[{"id":100,"status":"completed","conclusion":"success","display_title":"issue #111 dispatch stale-run"}]}'
      else
        printf '%s\n' '{"workflow_runs":[{"id":300,"status":"queued","conclusion":null,"display_title":"issue #999 dispatch foreign-run"},{"id":200,"status":"in_progress","conclusion":null,"display_title":"issue #900 dispatch canary-test-nonce-900"},{"id":100,"status":"completed","conclusion":"success","display_title":"issue #111 dispatch stale-run"}]}'
      fi
      exit 0
      ;;
    repos/test/fugue-orchestrator/issues/900/comments\?per_page=100)
      call="$(bump_counter issue_comments)"
      if [[ "${call}" == "1" ]]; then
        cat <<'JSON'
[{"body":"Orchestration profile resolved: `codex-full`. handoff_target=`kernel`. provider_source(main=`label`, assist=`label`). task_size_tier=`small`. risk_tier=`low` (score=`0`, reasons=`none`). preflight_cycles=`2`, implementation_dialogue_rounds=`2`, multi_agent_mode_override=`standard`, mode_lock=`true`, lessons_required=`false`, context_budget=`6->12`, assist_auto=`explicit-or-default`."}]
JSON
      else
        cat <<'JSON'
[{"body":"## Tutti Integrated Review\n\n- main orchestrator requested: codex\n- main orchestrator resolved: codex\n- assist orchestrator requested: claude\n- assist orchestrator resolved: claude\n- handoff target: kernel\n- task size tier: small\n- multi-agent mode: standard\n- multi-agent mode source: input-override\n- glm subagent mode: symphony\n- glm subagent mode source: repo-default\n- ci execution engine: subscription\n- subscription offline policy: continuity\n- run-agents runner: ubuntu-latest\n- run-agents runner labels: [\"ubuntu-latest\"]\n- execution profile: api-continuity (`subscription-no-self-hosted-online-continuity-policy`)\n- lanes configured: 9"}]
JSON
      fi
      exit 0
      ;;
    repos/test/fugue-orchestrator/actions/runs/200)
      call="$(bump_counter run_status)"
      if [[ "${call}" == "1" ]]; then
        printf '%s\n' '{"status":"in_progress","conclusion":null}'
      else
        printf '%s\n' '{"status":"completed","conclusion":"success"}'
      fi
      exit 0
      ;;
    *)
      printf '%s\n' '{}'
      exit 0
      ;;
  esac
fi

echo "unsupported fake gh invocation: $*" >&2
exit 1
EOF
chmod +x "${FAKE_GH}"

output_file="${TMP_DIR}/run.out"
if ! env \
  PATH="${TMP_DIR}:/usr/bin:/bin:/usr/sbin:/sbin" \
  GH_TOKEN="test-token" \
  GITHUB_REPOSITORY="test/fugue-orchestrator" \
  CANARY_MODE_INPUT="lite" \
  CANARY_PLAN_ONLY="false" \
  CLAUDE_RATE_LIMIT_STATE="ok" \
  CLAUDE_ROLE_POLICY="flex" \
  CLAUDE_DEGRADED_ASSIST_POLICY="claude" \
  CLAUDE_MAIN_ASSIST_POLICY="claude" \
  CI_EXECUTION_ENGINE="subscription" \
  SUBSCRIPTION_OFFLINE_POLICY="continuity" \
  CANARY_OFFLINE_POLICY_OVERRIDE="continuity" \
  EMERGENCY_CONTINUITY_MODE="false" \
  SUBSCRIPTION_RUNNER_LABEL="fugue-subscription" \
  EMERGENCY_ASSIST_POLICY="codex" \
  API_STRICT_MODE="false" \
  HAS_ANTHROPIC_API_KEY="false" \
  HAS_COPILOT_CLI="true" \
  HAS_OPENAI_API_KEY="true" \
  DEFAULT_MAIN_ORCHESTRATOR_PROVIDER="codex" \
  EXECUTION_PROVIDER_DEFAULT="" \
  CANARY_ALTERNATE_PROVIDER="claude" \
  CANARY_PRIMARY_HANDOFF_TARGET="kernel" \
  CANARY_VERIFY_ROLLBACK="false" \
  LEGACY_MAIN_ORCHESTRATOR_PROVIDER="claude" \
  LEGACY_ASSIST_ORCHESTRATOR_PROVIDER="claude" \
  LEGACY_FORCE_CLAUDE="true" \
  CANARY_LABEL_WAIT_ATTEMPTS="1" \
  CANARY_LABEL_WAIT_SLEEP_SEC="1" \
  CANARY_WAIT_FAST_ATTEMPTS="1" \
  CANARY_WAIT_FAST_SLEEP_SEC="1" \
  CANARY_WAIT_SLOW_ATTEMPTS="0" \
  CANARY_WAIT_SLOW_SLEEP_SEC="1" \
  CANARY_WAIT_RUN_ATTEMPTS="2" \
  CANARY_WAIT_RUN_SLEEP_SEC="1" \
  CANARY_WAIT_POST_RUN_ATTEMPTS="2" \
  CANARY_WAIT_POST_RUN_SLEEP_SEC="1" \
  CANARY_DISPATCH_DETECT_ATTEMPTS="2" \
  CANARY_DISPATCH_DETECT_SLEEP_SEC="1" \
  CANARY_DISPATCH_NONCE="canary-test-nonce" \
  CANARY_WORKFLOW_REF="kernel/test-canary" \
  FAKE_GH_STATE_DIR="${STATE_DIR}" \
  FAKE_GH_COMMENT_LOG="${COMMENT_LOG}" \
  bash "${CANARY_SCRIPT}" >"${output_file}" 2>"${TMP_DIR}/run.stderr"; then
  echo "FAIL: run-canary should succeed when workflow_dispatch is still in progress and integrated review arrives during grace window" >&2
  cat "${TMP_DIR}/run.stderr" >&2
  exit 1
fi

grep -Fq 'Canary passed (lite):' "${output_file}" || {
  echo "FAIL: expected canary success output" >&2
  cat "${output_file}" >&2
  exit 1
}

grep -Fq 'mapped to workflow_dispatch run 200' "${TMP_DIR}/run.stderr" || {
  echo "FAIL: expected canary stderr to record dispatch run mapping" >&2
  cat "${TMP_DIR}/run.stderr" >&2
  exit 1
}

grep -Fq 'waiting on workflow run 200' "${TMP_DIR}/run.stderr" || {
  echo "FAIL: expected canary stderr to enter workflow-run grace phase" >&2
  cat "${TMP_DIR}/run.stderr" >&2
  exit 1
}

if [[ "$(cat "${STATE_DIR}/run_status.count")" != "2" ]]; then
  echo "FAIL: expected canary to re-check workflow run state until terminal completion before commenting" >&2
  cat "${TMP_DIR}/run.stderr" >&2
  exit 1
fi

if grep -q '`' "${COMMENT_LOG}"; then
  echo "FAIL: canary comments must not contain backticks that trigger shell expansion in old workflows" >&2
  cat "${COMMENT_LOG}" >&2
  exit 1
fi

grep -Fq 'Canary pass (regular): expected main=codex, assist=claude, profile=api-continuity, runner=ubuntu-latest, handoff=kernel' "${COMMENT_LOG}" || {
  echo "FAIL: expected plain-text pass comment in issue comment log" >&2
  cat "${COMMENT_LOG}" >&2
  exit 1
}

echo "PASS [run-canary-progress-wait]"
