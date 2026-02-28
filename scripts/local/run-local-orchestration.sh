#!/usr/bin/env bash
set -euo pipefail

# Local orchestration runner (no GitHub Actions runner required).
# - codex/claude lanes: subscription CLI runner
# - glm lanes: API harness runner
# This script intentionally runs everything on the current local machine.

REPO="${REPO:-cursorvers/fugue-orchestrator}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
OUT_DIR="${OUT_DIR:-.fugue/local-run}"
MAIN_PROVIDER="${MAIN_PROVIDER:-codex}"
ASSIST_PROVIDER="${ASSIST_PROVIDER:-claude}"
MULTI_AGENT_MODE="${MULTI_AGENT_MODE:-standard}"
GLM_SUBAGENT_MODE="${GLM_SUBAGENT_MODE:-paired}"
MAX_PARALLEL="${MAX_PARALLEL:-6}"
MIN_CONSENSUS_LANES="${MIN_CONSENSUS_LANES:-${FUGUE_MIN_CONSENSUS_LANES:-6}}"
POST_ISSUE_COMMENT="${POST_ISSUE_COMMENT:-false}"
CODEX_MAIN_MODEL="${CODEX_MAIN_MODEL:-gpt-5-codex}"
CODEX_MULTI_AGENT_MODEL="${CODEX_MULTI_AGENT_MODEL:-gpt-5.3-codex-spark}"
WITH_LINKED_SYSTEMS="${WITH_LINKED_SYSTEMS:-false}"
LINKED_MODE="${LINKED_MODE:-smoke}"
LINKED_SYSTEMS="${LINKED_SYSTEMS:-all}"
LINKED_MAX_PARALLEL="${LINKED_MAX_PARALLEL:-3}"
EXTRA_ISSUE_INSTRUCTION="${EXTRA_ISSUE_INSTRUCTION:-${FUGUE_LOCAL_EXTRA_ISSUE_INSTRUCTION:-}}"
ISSUE_TITLE_INPUT="${ISSUE_TITLE_INPUT:-${FUGUE_LOCAL_ISSUE_TITLE:-}}"
ISSUE_BODY_INPUT="${ISSUE_BODY_INPUT:-${FUGUE_LOCAL_ISSUE_BODY:-}}"
ISSUE_BODY_FILE="${ISSUE_BODY_FILE:-${FUGUE_LOCAL_ISSUE_BODY_FILE:-}}"
ISSUE_URL_INPUT="${ISSUE_URL_INPUT:-${FUGUE_LOCAL_ISSUE_URL:-}}"
ISSUE_LABELS_CSV_INPUT="${ISSUE_LABELS_CSV_INPUT:-${FUGUE_LOCAL_ISSUE_LABELS_CSV:-}}"
FORCE_MANUAL_CONTEXT="${FORCE_MANUAL_CONTEXT:-${FUGUE_LOCAL_FORCE_MANUAL_CONTEXT:-false}}"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/run-local-orchestration.sh --issue <number> [options]

Options:
  --issue <n>            GitHub issue number (required)
  --repo <owner/repo>    Repository containing issue (default: cursorvers/fugue-orchestrator)
  --out-dir <path>       Output directory (default: .fugue/local-run)
  --main <codex|claude>  Main orchestrator (default: codex)
  --assist <claude|codex|none>
                         Assist orchestrator (default: claude)
  --mode <standard|enhanced|max>
                         Multi-agent mode (default: standard)
  --glm-mode <off|paired|symphony>
                         GLM subagent fan-out (default: paired)
  --max-parallel <n>     Max parallel lanes (default: 6)
  --issue-title <text>   Manual issue title override (offline fallback)
  --issue-body <text>    Manual issue body override (offline fallback)
  --issue-body-file <p>  Read manual issue body from file (offline fallback)
  --issue-url <url>      Manual issue URL override
  --labels-csv <csv>     Manual labels CSV override (default: fugue-task)
  --force-manual-context Skip GitHub issue fetch and use manual context directly
  --instruction <text>   Extra instruction appended to issue body for this local vote run
  --with-linked-systems  Execute linked local systems after orchestration
  --linked-mode <smoke|execute>
                         Linked systems mode (default: smoke)
  --linked-systems <all|csv>
                         Linked system IDs (default: all)
  --linked-max-parallel <n>
                         Max parallel linked systems (default: 3)
  --comment              Post integrated summary to the issue
  -h, --help             Show help

Environment:
  OPENAI_API_KEY         Required for Codex API fallback lanes (if used by harness runner)
  ZAI_API_KEY            Required for GLM lanes
  ANTHROPIC_API_KEY      Optional in local CLI mode (Claude CLI is primary path)
  FUGUE_CLAUDE_RATE_LIMIT_STATE
                         ok|degraded|exhausted (default: ok)
  FUGUE_LOCAL_REQUIRE_CLAUDE_ASSIST
                         true|false (default: false; when true + state=ok, claude-opus-assist direct success is mandatory)
  FUGUE_LOCAL_REQUIRE_CLAUDE_ASSIST_ON_COMPLEX
                         true|false (default: true; when true + assist=claude, high-risk or ambiguity-signaled tasks require claude-opus-assist success)
  FUGUE_LOCAL_REQUIRE_BASELINE_TRIO
                         true|false (default: true; require codex+claude+glm successful participation)
  FUGUE_LOCAL_AMBIGUITY_SIGNAL
                         true|false (default: false; explicit local ambiguity signal used by complex-gate)
  FUGUE_DUAL_MAIN_SIGNAL
                         true|false (default: auto; true in max mode, false otherwise)
  FUGUE_MIN_CONSENSUS_LANES
                         integer >= 6 (default: 6; fail-fast when resolved lane count is below this floor)
  FUGUE_LOCAL_EXTRA_ISSUE_INSTRUCTION
                         Optional extra instruction text appended to issue body for this local run
  FUGUE_LOCAL_ISSUE_TITLE / FUGUE_LOCAL_ISSUE_BODY / FUGUE_LOCAL_ISSUE_BODY_FILE
                         Manual issue context overrides for GitHub API fallback
  FUGUE_LOCAL_ISSUE_URL / FUGUE_LOCAL_ISSUE_LABELS_CSV
                         Optional manual URL/labels overrides
  FUGUE_LOCAL_FORCE_MANUAL_CONTEXT
                         true|false (default: false; when true, skip GitHub issue fetch entirely)
  FUGUE_CLAUDE_SESSION_HANDOFF
                         true|false (default: true; persist claude lane session IDs for resume/handoff)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      ISSUE_NUMBER="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --main)
      MAIN_PROVIDER="${2:-}"
      shift 2
      ;;
    --assist)
      ASSIST_PROVIDER="${2:-}"
      shift 2
      ;;
    --mode)
      MULTI_AGENT_MODE="${2:-}"
      shift 2
      ;;
    --glm-mode)
      GLM_SUBAGENT_MODE="${2:-}"
      shift 2
      ;;
    --max-parallel)
      MAX_PARALLEL="${2:-}"
      shift 2
      ;;
    --issue-title)
      ISSUE_TITLE_INPUT="${2:-}"
      shift 2
      ;;
    --issue-body)
      ISSUE_BODY_INPUT="${2:-}"
      shift 2
      ;;
    --issue-body-file)
      ISSUE_BODY_FILE="${2:-}"
      shift 2
      ;;
    --issue-url)
      ISSUE_URL_INPUT="${2:-}"
      shift 2
      ;;
    --labels-csv)
      ISSUE_LABELS_CSV_INPUT="${2:-}"
      shift 2
      ;;
    --force-manual-context)
      FORCE_MANUAL_CONTEXT="true"
      shift 1
      ;;
    --instruction)
      EXTRA_ISSUE_INSTRUCTION="${2:-}"
      shift 2
      ;;
    --with-linked-systems)
      WITH_LINKED_SYSTEMS="true"
      shift 1
      ;;
    --linked-mode)
      LINKED_MODE="${2:-}"
      shift 2
      ;;
    --linked-systems)
      LINKED_SYSTEMS="${2:-}"
      shift 2
      ;;
    --linked-max-parallel)
      LINKED_MAX_PARALLEL="${2:-}"
      shift 2
      ;;
    --comment)
      POST_ISSUE_COMMENT="true"
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${ISSUE_NUMBER}" ]]; then
  echo "Error: --issue is required." >&2
  usage >&2
  exit 2
fi
if [[ -n "${ISSUE_BODY_FILE}" && -n "${ISSUE_BODY_INPUT}" ]]; then
  echo "Error: use either --issue-body or --issue-body-file, not both." >&2
  exit 2
fi
if [[ -n "${ISSUE_BODY_FILE}" && ! -f "${ISSUE_BODY_FILE}" ]]; then
  echo "Error: --issue-body-file does not exist: ${ISSUE_BODY_FILE}" >&2
  exit 2
fi
force_manual_context="$(echo "${FORCE_MANUAL_CONTEXT}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${force_manual_context}" != "true" ]]; then
  force_manual_context="false"
fi

if [[ "${MAIN_PROVIDER}" != "codex" && "${MAIN_PROVIDER}" != "claude" ]]; then
  echo "Error: --main must be codex or claude." >&2
  exit 2
fi
if [[ "${ASSIST_PROVIDER}" != "claude" && "${ASSIST_PROVIDER}" != "codex" && "${ASSIST_PROVIDER}" != "none" ]]; then
  echo "Error: --assist must be claude|codex|none." >&2
  exit 2
fi
if [[ "${MULTI_AGENT_MODE}" != "standard" && "${MULTI_AGENT_MODE}" != "enhanced" && "${MULTI_AGENT_MODE}" != "max" ]]; then
  echo "Error: --mode must be standard|enhanced|max." >&2
  exit 2
fi
if [[ "${GLM_SUBAGENT_MODE}" != "off" && "${GLM_SUBAGENT_MODE}" != "paired" && "${GLM_SUBAGENT_MODE}" != "symphony" ]]; then
  echo "Error: --glm-mode must be off|paired|symphony." >&2
  exit 2
fi
if ! [[ "${MAX_PARALLEL}" =~ ^[0-9]+$ ]] || (( MAX_PARALLEL < 1 )); then
  echo "Error: --max-parallel must be a positive integer." >&2
  exit 2
fi
if ! [[ "${MIN_CONSENSUS_LANES}" =~ ^[0-9]+$ ]] || (( MIN_CONSENSUS_LANES < 6 )); then
  echo "Error: FUGUE_MIN_CONSENSUS_LANES (or MIN_CONSENSUS_LANES) must be an integer >= 6." >&2
  exit 2
fi
if [[ "${LINKED_MODE}" != "smoke" && "${LINKED_MODE}" != "execute" ]]; then
  echo "Error: --linked-mode must be smoke|execute." >&2
  exit 2
fi
if ! [[ "${LINKED_MAX_PARALLEL}" =~ ^[0-9]+$ ]] || (( LINKED_MAX_PARALLEL < 1 )); then
  echo "Error: --linked-max-parallel must be a positive integer." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ "${OUT_DIR}" != /* ]]; then
  OUT_DIR="${ROOT_DIR}/${OUT_DIR}"
fi
SUBSCRIPTION_RUNNER="${ROOT_DIR}/scripts/harness/subscription-agent-runner.sh"
HARNESS_RUNNER="${ROOT_DIR}/scripts/harness/ci-agent-runner.sh"
MATRIX_BUILDER="${ROOT_DIR}/scripts/lib/build-agent-matrix.sh"
MODEL_POLICY="${ROOT_DIR}/scripts/lib/model-policy.sh"
WORKFLOW_RISK_POLICY="${ROOT_DIR}/scripts/lib/workflow-risk-policy.sh"
LINKED_RUNNER="${ROOT_DIR}/scripts/local/run-linked-systems.sh"
if [[ ! -x "${SUBSCRIPTION_RUNNER}" || ! -x "${HARNESS_RUNNER}" || ! -x "${MATRIX_BUILDER}" ]]; then
  echo "Error: required harness runners are missing/executable flags are not set." >&2
  exit 2
fi
if [[ ! -x "${MODEL_POLICY}" ]]; then
  echo "Error: required model policy script is missing or not executable: ${MODEL_POLICY}" >&2
  exit 2
fi
if [[ ! -x "${WORKFLOW_RISK_POLICY}" ]]; then
  echo "Error: required workflow risk policy script is missing or not executable: ${WORKFLOW_RISK_POLICY}" >&2
  exit 2
fi
if [[ "${WITH_LINKED_SYSTEMS}" == "true" && ! -x "${LINKED_RUNNER}" ]]; then
  echo "Error: linked systems runner is missing or not executable: ${LINKED_RUNNER}" >&2
  exit 2
fi

manual_issue_title="$(printf '%s' "${ISSUE_TITLE_INPUT}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
manual_issue_body="${ISSUE_BODY_INPUT}"
if [[ -n "${ISSUE_BODY_FILE}" ]]; then
  manual_issue_body="$(cat "${ISSUE_BODY_FILE}")"
fi
manual_issue_url="$(printf '%s' "${ISSUE_URL_INPUT}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
manual_issue_labels_csv="$(printf '%s' "${ISSUE_LABELS_CSV_INPUT}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -z "${manual_issue_labels_csv}" ]]; then
  manual_issue_labels_csv="fugue-task"
fi
has_manual_context="false"
if [[ -n "${manual_issue_title}" && -n "${manual_issue_body}" ]]; then
  has_manual_context="true"
fi

gh_available="false"
if command -v gh >/dev/null 2>&1; then
  gh_available="true"
fi
if [[ "${POST_ISSUE_COMMENT}" == "true" && "${gh_available}" != "true" ]]; then
  echo "Error: --comment requires gh command." >&2
  exit 2
fi
if [[ "${WITH_LINKED_SYSTEMS}" == "true" && "${gh_available}" != "true" ]]; then
  echo "Error: --with-linked-systems requires gh command." >&2
  exit 2
fi

ISSUE_TITLE=""
ISSUE_BODY=""
ISSUE_URL=""
ISSUE_LABELS_CSV=""
issue_context_source=""
if [[ "${force_manual_context}" == "true" ]]; then
  if [[ "${has_manual_context}" != "true" ]]; then
    echo "Error: --force-manual-context requires --issue-title and --issue-body/--issue-body-file." >&2
    exit 2
  fi
  ISSUE_TITLE="${manual_issue_title}"
  ISSUE_BODY="${manual_issue_body}"
  ISSUE_URL="${manual_issue_url}"
  ISSUE_LABELS_CSV="${manual_issue_labels_csv}"
  issue_context_source="manual-forced"
else
  if [[ "${gh_available}" == "true" ]]; then
    if issue_json="$(gh issue view "${ISSUE_NUMBER}" --repo "${REPO}" --json number,title,body,url,labels 2>/dev/null)"; then
      ISSUE_TITLE="$(echo "${issue_json}" | jq -r '.title // ""')"
      ISSUE_BODY="$(echo "${issue_json}" | jq -r '.body // ""')"
      ISSUE_URL="$(echo "${issue_json}" | jq -r '.url // ""')"
      ISSUE_LABELS_CSV="$(echo "${issue_json}" | jq -r '[.labels[].name // empty] | join(",")')"
      issue_context_source="github"
    elif [[ "${has_manual_context}" == "true" ]]; then
      ISSUE_TITLE="${manual_issue_title}"
      ISSUE_BODY="${manual_issue_body}"
      ISSUE_URL="${manual_issue_url}"
      ISSUE_LABELS_CSV="${manual_issue_labels_csv}"
      issue_context_source="manual-fallback"
      echo "Warning: gh issue fetch failed; using manual context fallback." >&2
    else
      echo "Error: failed to fetch issue via gh and no manual fallback context was provided." >&2
      exit 2
    fi
  elif [[ "${has_manual_context}" == "true" ]]; then
    ISSUE_TITLE="${manual_issue_title}"
    ISSUE_BODY="${manual_issue_body}"
    ISSUE_URL="${manual_issue_url}"
    ISSUE_LABELS_CSV="${manual_issue_labels_csv}"
    issue_context_source="manual-no-gh"
    echo "Warning: gh command not found; using manual context fallback." >&2
  else
    echo "Error: gh is unavailable and no manual context was provided." >&2
    exit 2
  fi
fi
if [[ -z "${ISSUE_LABELS_CSV}" ]]; then
  ISSUE_LABELS_CSV="${manual_issue_labels_csv}"
fi
extra_issue_instruction_trimmed="$(printf '%s' "${EXTRA_ISSUE_INSTRUCTION:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -n "${extra_issue_instruction_trimmed}" ]]; then
  ISSUE_BODY="$(printf '%s\n\n## Vote Instruction\n%s\n' "${ISSUE_BODY}" "${extra_issue_instruction_trimmed}")"
  echo "Applied local vote instruction override to issue context." >&2
fi
echo "Issue context source: ${issue_context_source}" >&2

run_id="$(date +%Y%m%d-%H%M%S)-$$"
RUN_DIR="${OUT_DIR}/issue-${ISSUE_NUMBER}-${run_id}"
LANE_DIR="${RUN_DIR}/lanes"
TMP_DIR="${RUN_DIR}/tmp"
mkdir -p "${LANE_DIR}" "${TMP_DIR}"

strict_main="${FUGUE_STRICT_MAIN_CODEX_MODEL:-false}"
strict_opus="${FUGUE_STRICT_OPUS_ASSIST_DIRECT:-false}"
claude_opus_model="${FUGUE_CLAUDE_OPUS_MODEL:-claude-sonnet-4-6}"
eval "$("${MODEL_POLICY}" \
  --codex-main-model "${CODEX_MAIN_MODEL}" \
  --codex-multi-agent-model "${CODEX_MULTI_AGENT_MODEL}" \
  --claude-model "${claude_opus_model}" \
  --glm-model "${GLM_MODEL:-${FUGUE_GLM_MODEL:-glm-5.0}}" \
  --gemini-model "gemini-3.1-pro" \
  --gemini-fallback-model "gemini-3-flash" \
  --xai-model "grok-4" \
  --format env)"
CODEX_MAIN_MODEL="${codex_main_model}"
CODEX_MULTI_AGENT_MODEL="${codex_multi_agent_model}"
GLM_MODEL="${glm_model}"
claude_opus_model="${claude_model}"
subscription_timeout="${FUGUE_SUBSCRIPTION_CLI_TIMEOUT_SEC:-180}"
claude_assist_policy="${FUGUE_CLAUDE_ASSIST_EXECUTION_POLICY:-hybrid}"
claude_rate_limit_state="$(echo "${FUGUE_CLAUDE_RATE_LIMIT_STATE:-ok}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_rate_limit_state}" != "ok" && "${claude_rate_limit_state}" != "degraded" && "${claude_rate_limit_state}" != "exhausted" ]]; then
  claude_rate_limit_state="ok"
fi
local_require_claude_assist="$(echo "${FUGUE_LOCAL_REQUIRE_CLAUDE_ASSIST:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${local_require_claude_assist}" != "true" ]]; then
  local_require_claude_assist="false"
fi
local_require_claude_assist_on_complex="$(echo "${FUGUE_LOCAL_REQUIRE_CLAUDE_ASSIST_ON_COMPLEX:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${local_require_claude_assist_on_complex}" != "false" ]]; then
  local_require_claude_assist_on_complex="true"
fi
local_require_baseline_trio="$(echo "${FUGUE_LOCAL_REQUIRE_BASELINE_TRIO:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${local_require_baseline_trio}" != "false" ]]; then
  local_require_baseline_trio="true"
fi
local_ambiguity_signal="$(echo "${FUGUE_LOCAL_AMBIGUITY_SIGNAL:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${local_ambiguity_signal}" != "true" ]]; then
  local_ambiguity_signal="false"
fi
eval "$("${WORKFLOW_RISK_POLICY}" \
  --title "${ISSUE_TITLE}" \
  --body "${ISSUE_BODY}" \
  --labels "${ISSUE_LABELS_CSV}" \
  --has-implement "false" \
  --orchestration-profile "codex-full")"
issue_risk_tier="${risk_tier}"
issue_risk_score="${risk_score}"
issue_risk_reasons="${risk_reasons}"
claude_session_handoff="$(echo "${FUGUE_CLAUDE_SESSION_HANDOFF:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_session_handoff}" != "true" ]]; then
  claude_session_handoff="false"
fi
CLAUDE_SESSION_DIR="${RUN_DIR}/claude-sessions"
if [[ "${claude_session_handoff}" == "true" ]]; then
  mkdir -p "${CLAUDE_SESSION_DIR}"
fi

matrix_file="${RUN_DIR}/matrix.json"
dual_main_signal_raw="$(echo "${FUGUE_DUAL_MAIN_SIGNAL:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${dual_main_signal_raw}" == "true" ]]; then
  dual_main_signal="true"
elif [[ "${dual_main_signal_raw}" == "false" ]]; then
  dual_main_signal="false"
elif [[ "${MULTI_AGENT_MODE}" == "max" ]]; then
  dual_main_signal="true"
else
  dual_main_signal="false"
fi
matrix_payload="$("${MATRIX_BUILDER}" \
  --engine "subscription" \
  --main-provider "${MAIN_PROVIDER}" \
  --assist-provider "${ASSIST_PROVIDER}" \
  --multi-agent-mode "${MULTI_AGENT_MODE}" \
  --glm-subagent-mode "${GLM_SUBAGENT_MODE}" \
  --dual-main-signal "${dual_main_signal}" \
  --allow-glm-in-subscription "true" \
  --wants-gemini "false" \
  --wants-xai "false" \
  --codex-main-model "${CODEX_MAIN_MODEL}" \
  --codex-multi-agent-model "${CODEX_MULTI_AGENT_MODEL}" \
  --glm-model "${GLM_MODEL}" \
  --claude-opus-model "${claude_opus_model}" \
  --format "json")"
echo "${matrix_payload}" | jq -c '.matrix' > "${matrix_file}"
lanes_total="$(echo "${matrix_payload}" | jq -r '.lanes')"
if ! [[ "${lanes_total}" =~ ^[0-9]+$ ]]; then
  echo "Error: resolved lane count is not numeric (lanes=${lanes_total})." >&2
  exit 2
fi
if (( lanes_total < MIN_CONSENSUS_LANES )); then
  echo "Error: resolved lane count (${lanes_total}) is below minimum consensus floor (${MIN_CONSENSUS_LANES})." >&2
  exit 2
fi
echo "Running local orchestration: issue=${ISSUE_NUMBER} lanes=${lanes_total} mode=${MULTI_AGENT_MODE} glm_mode=${GLM_SUBAGENT_MODE} dual_main=${dual_main_signal}" >&2

lane_jobs_file="${RUN_DIR}/lane-jobs.jsonl"
jq -c '.include[]' "${matrix_file}" > "${lane_jobs_file}"

run_lane() {
  local lane_json="$1"
  local lane_name provider model role directive lane_work lane_result lane_log lane_err lane_session_id session_file

  lane_name="$(echo "${lane_json}" | jq -r '.name')"
  provider="$(echo "${lane_json}" | jq -r '.provider')"
  model="$(echo "${lane_json}" | jq -r '.model')"
  role="$(echo "${lane_json}" | jq -r '.agent_role')"
  directive="$(echo "${lane_json}" | jq -r '.agent_directive // ""')"
  lane_work="${TMP_DIR}/${lane_name}"
  lane_result="${LANE_DIR}/agent-${lane_name}.json"
  lane_log="${LANE_DIR}/${lane_name}.out.log"
  lane_err="${LANE_DIR}/${lane_name}.err.log"
  mkdir -p "${lane_work}"
  lane_session_id=""
  if [[ "${provider}" == "claude" && "${claude_session_handoff}" == "true" ]]; then
    session_file="${CLAUDE_SESSION_DIR}/${lane_name}.session-id"
    if [[ -f "${session_file}" ]]; then
      lane_session_id="$(head -n 1 "${session_file}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    fi
    if [[ -z "${lane_session_id}" ]]; then
      if command -v uuidgen >/dev/null 2>&1; then
        lane_session_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
      else
        lane_session_id="$(date +%s)-${RANDOM}-${RANDOM}"
      fi
      printf '%s\n' "${lane_session_id}" > "${session_file}"
    fi
  fi

  local api_url
  api_url="subscription-cli"
  local runner="${SUBSCRIPTION_RUNNER}"
  if [[ "${provider}" == "glm" ]]; then
    runner="${HARNESS_RUNNER}"
    api_url="https://api.z.ai/api/coding/paas/v4/chat/completions"
  fi

  set +e
  (
    cd "${lane_work}"
    ISSUE_TITLE="${ISSUE_TITLE}" \
    ISSUE_BODY="${ISSUE_BODY}" \
    PROVIDER="${provider}" \
    MODEL="${model}" \
    AGENT_ROLE="${role}" \
    AGENT_NAME="${lane_name}" \
    AGENT_DIRECTIVE="${directive}" \
    ISSUE_NUMBER="${ISSUE_NUMBER}" \
    CLAUDE_SESSION_ID="${lane_session_id}" \
    API_URL="${api_url}" \
    CODEX_MAIN_MODEL="${CODEX_MAIN_MODEL}" \
    CODEX_MULTI_AGENT_MODEL="${CODEX_MULTI_AGENT_MODEL}" \
    GLM_MODEL="${GLM_MODEL}" \
    OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
    ZAI_API_KEY="${ZAI_API_KEY:-}" \
    GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
    XAI_API_KEY="${XAI_API_KEY:-}" \
    ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
    CLAUDE_ASSIST_EXECUTION_POLICY="${claude_assist_policy}" \
    CLAUDE_OPUS_MODEL="${claude_opus_model}" \
    STRICT_MAIN_CODEX_MODEL="${strict_main}" \
    STRICT_OPUS_ASSIST_DIRECT="${strict_opus}" \
    SUBSCRIPTION_CLI_TIMEOUT_SEC="${subscription_timeout}" \
    CI_EXECUTION_ENGINE="subscription" \
    EXECUTION_PROFILE="local-direct" \
    bash "${runner}" >"${lane_log}" 2>"${lane_err}"
  )
  rc=$?
  set -e

  if (( rc == 0 )) && [[ -f "${lane_work}/agent-${lane_name}.json" ]]; then
    cp "${lane_work}/agent-${lane_name}.json" "${lane_result}"
  else
    jq -n \
      --arg name "${lane_name}" \
      --arg provider "${provider}" \
      --arg model "${model}" \
      --arg role "${role}" \
      --arg rc "${rc}" \
      '{
        name:$name,
        provider:$provider,
        model:$model,
        agent_role:$role,
        http_code:"runner-error",
        skipped:true,
        risk:"MEDIUM",
        approve:false,
        findings:["Lane failed before producing JSON artifact", ("exit_code=" + $rc)],
        recommendation:"Inspect lane logs and retry locally",
        rationale:"Runner did not output agent JSON",
        execution_engine:"local-direct"
      }' > "${lane_result}"
  fi
}

export -f run_lane
export ISSUE_TITLE ISSUE_BODY ISSUE_NUMBER TMP_DIR LANE_DIR SUBSCRIPTION_RUNNER HARNESS_RUNNER
export OPENAI_API_KEY ZAI_API_KEY GEMINI_API_KEY XAI_API_KEY ANTHROPIC_API_KEY
export claude_assist_policy claude_opus_model strict_main strict_opus subscription_timeout
export claude_session_handoff CLAUDE_SESSION_DIR

lane_failures=0
while IFS= read -r lane; do
  run_lane "${lane}" </dev/null &
  while (( $(jobs -rp | wc -l | tr -d ' ') >= MAX_PARALLEL )); do
    sleep 0.2
  done
done < <(jq -c '.include[]' "${matrix_file}")

for pid in $(jobs -rp); do
  if ! wait "${pid}"; then
    lane_failures=$((lane_failures + 1))
  fi
done
if (( lane_failures > 0 )); then
  echo "Warning: ${lane_failures} lane(s) exited non-zero; synthesized fallback artifacts may be present." >&2
fi

all_results="${RUN_DIR}/all-results.json"
jq -s '.' "${LANE_DIR}"/agent-*.json > "${all_results}"
claude_sessions_file="${RUN_DIR}/claude-sessions.json"
jq '
  [ .[]
    | select((.provider // "" | ascii_downcase) == "claude")
    | select((.session_id // "") != "")
    | {name, model, session_id}
  ]
' "${all_results}" > "${claude_sessions_file}"
claude_session_count="$(jq 'length' "${claude_sessions_file}")"
claude_resume_hint="N/A"
if [[ "${claude_session_count}" -gt 0 ]]; then
  first_session_id="$(jq -r '.[0].session_id' "${claude_sessions_file}")"
  claude_resume_hint="claude --resume ${first_session_id}"
fi

integrated_json="${RUN_DIR}/integrated.json"
high_risk_count="$(jq '[.[] | select(.skipped != true and (.risk|ascii_upcase) == "HIGH")] | length' "${all_results}")"
high_risk="false"
if [[ "${high_risk_count}" -gt 0 ]]; then
  high_risk="true"
fi
approve_count="$(jq '[.[] | select(.skipped != true and .approve == true)] | length' "${all_results}")"
total_count="$(jq '[.[] | select(.skipped != true)] | length' "${all_results}")"
if [[ "${total_count}" -eq 0 ]]; then
  threshold=1
else
  threshold=$(( (total_count * 2 + 2) / 3 ))
fi
weighted_total_score="$(jq -r '
  [ .[] | select(.skipped != true) |
    (if (.agent_role|test("security-analyst";"i")) then 1.4
     elif (.agent_role|test("code-reviewer";"i")) then 1.2
     elif (.agent_role|test("architect";"i")) then 1.1
     elif (.agent_role|test("reliability-engineer|invariants-checker";"i")) then 1.1
     elif (.agent_role|test("general-reviewer|plan-reviewer|general-critic";"i")) then 1.0
     elif (.agent_role|test("refactor-advisor";"i")) then 0.9
     elif (.agent_role|test("math-reasoning|orchestration-assistant|main-orchestrator|ui-reviewer";"i")) then 0.8
     elif (.agent_role|test("realtime-info";"i")) then 0.7
     else 1.0 end)
  ] | add // 0
' "${all_results}")"
weighted_approve_score="$(jq -r '
  [ .[] | select(.skipped != true and .approve == true) |
    (if (.agent_role|test("security-analyst";"i")) then 1.4
     elif (.agent_role|test("code-reviewer";"i")) then 1.2
     elif (.agent_role|test("architect";"i")) then 1.1
     elif (.agent_role|test("reliability-engineer|invariants-checker";"i")) then 1.1
     elif (.agent_role|test("general-reviewer|plan-reviewer|general-critic";"i")) then 1.0
     elif (.agent_role|test("refactor-advisor";"i")) then 0.9
     elif (.agent_role|test("math-reasoning|orchestration-assistant|main-orchestrator|ui-reviewer";"i")) then 0.8
     elif (.agent_role|test("realtime-info";"i")) then 0.7
     else 1.0 end)
  ] | add // 0
' "${all_results}")"
weighted_threshold="$(awk -v total="${weighted_total_score}" 'BEGIN { printf "%.3f", (2*total)/3 }')"
weighted_vote_passed="$(awk -v approve="${weighted_approve_score}" -v threshold="${weighted_threshold}" 'BEGIN { if (approve + 1e-9 >= threshold) print "true"; else print "false" }')"
ok_to_execute="false"
if [[ "${total_count}" -eq 0 ]]; then
  weighted_vote_passed="false"
fi

required_claude_assist_gate="not-required"
required_claude_assist_reason="assist-not-required"
complex_claude_sub_required="false"
complex_claude_sub_reason="complex-not-required"
if [[ "${local_require_claude_assist_on_complex}" == "true" ]]; then
  if [[ "${ASSIST_PROVIDER}" != "claude" ]]; then
    complex_claude_sub_reason="complex-policy-assist-${ASSIST_PROVIDER}"
  elif [[ "${issue_risk_tier}" == "high" ]]; then
    complex_claude_sub_required="true"
    complex_claude_sub_reason="risk-high(score=${issue_risk_score},reasons=${issue_risk_reasons})"
  elif [[ "${local_ambiguity_signal}" == "true" ]]; then
    complex_claude_sub_required="true"
    complex_claude_sub_reason="ambiguity-signal"
  fi
else
  complex_claude_sub_reason="complex-policy-disabled"
fi
gate_required="false"
gate_requirement_kind="none"
if [[ "${complex_claude_sub_required}" == "true" ]]; then
  gate_required="true"
  gate_requirement_kind="complex"
fi
if [[ "${ASSIST_PROVIDER}" == "claude" && "${local_require_claude_assist}" == "true" ]]; then
  gate_required="true"
  if [[ "${gate_requirement_kind}" == "complex" ]]; then
    gate_requirement_kind="complex+direct"
  else
    gate_requirement_kind="direct"
  fi
fi
if [[ "${gate_required}" == "true" ]]; then
  required_claude_assist_gate="pass"
  required_claude_assist_reason="${gate_requirement_kind}-ok"
  if [[ "${ASSIST_PROVIDER}" != "claude" ]]; then
    required_claude_assist_gate="fail"
    required_claude_assist_reason="${gate_requirement_kind}-assist-${ASSIST_PROVIDER}"
  elif [[ "${claude_rate_limit_state}" != "ok" ]]; then
    required_claude_assist_gate="fail"
    required_claude_assist_reason="${gate_requirement_kind}-claude-rate-limit-${claude_rate_limit_state}"
  elif jq -e \
    --arg opus "${claude_opus_model}" \
    '[ .[] | select(.name == "claude-opus-assist" and .skipped != true and (.provider|ascii_downcase) == "claude" and (.model|ascii_downcase) == ($opus|ascii_downcase) and ((.http_code|tostring|startswith("cli:")) or (.http_code|tostring) == "200")) ] | length > 0' \
    "${all_results}" >/dev/null 2>&1; then
    required_claude_assist_gate="pass"
    required_claude_assist_reason="${gate_requirement_kind}-claude-opus-assist-success"
  else
    required_claude_assist_gate="fail"
    required_claude_assist_reason="${gate_requirement_kind}-claude-opus-assist-missing-or-failed"
  fi
else
  if [[ "${complex_claude_sub_required}" != "true" && "${local_require_claude_assist_on_complex}" == "true" ]]; then
    required_claude_assist_reason="${complex_claude_sub_reason}"
  elif [[ "${local_require_claude_assist}" != "true" ]]; then
    required_claude_assist_reason="direct-policy-disabled"
  else
    required_claude_assist_reason="policy-disabled"
  fi
fi
if [[ "${required_claude_assist_gate}" == "fail" ]]; then
  weighted_vote_passed="false"
fi

baseline_trio_gate="not-required"
baseline_trio_reason="policy-disabled"
codex_baseline_success="$(jq '[
  .[] | select(
    .skipped != true
    and ((.provider // "" | ascii_downcase) == "codex")
    and (
      ((.http_code // "" | tostring) == "200")
      or
      ((.http_code // "" | tostring | startswith("cli:0")))
    )
  )
] | length' "${all_results}")"
claude_baseline_success="$(jq '[
  .[] | select(
    .skipped != true
    and ((.provider // "" | ascii_downcase) == "claude")
    and (
      ((.http_code // "" | tostring) == "200")
      or
      ((.http_code // "" | tostring | startswith("cli:0")))
    )
  )
] | length' "${all_results}")"
glm_baseline_success="$(jq '[
  .[] | select(
    .skipped != true
    and ((.provider // "" | ascii_downcase) == "glm")
    and ((.name // "") | test("^glm-.*-subagent$") | not)
    and (
      ((.http_code // "" | tostring) == "200")
      or
      ((.http_code // "" | tostring | startswith("cli:0")))
    )
  )
] | length' "${all_results}")"
if [[ "${local_require_baseline_trio}" == "true" ]]; then
  baseline_trio_gate="pass"
  baseline_missing=()
  if [[ "${codex_baseline_success}" -eq 0 ]]; then
    baseline_missing+=("codex")
  fi
  if [[ "${claude_baseline_success}" -eq 0 ]]; then
    baseline_missing+=("claude")
  fi
  if [[ "${glm_baseline_success}" -eq 0 ]]; then
    baseline_missing+=("glm")
  fi
  if (( ${#baseline_missing[@]} > 0 )); then
    baseline_trio_gate="fail"
    baseline_trio_reason="missing-$(IFS=,; echo "${baseline_missing[*]}")"
    high_risk="true"
    high_risk_count="$((high_risk_count + 1))"
    weighted_vote_passed="false"
  else
    baseline_trio_reason="codex+claude+glm-ok"
  fi
fi

if [[ "${weighted_vote_passed}" == "true" && "${high_risk}" != "true" ]]; then
  ok_to_execute="true"
fi

linked_status="not-run"
linked_run_dir=""
linked_note="disabled"
if [[ "${WITH_LINKED_SYSTEMS}" == "true" ]]; then
  linked_note="requested"
  if [[ "${LINKED_MODE}" == "execute" && "${ok_to_execute}" != "true" ]]; then
    linked_status="skipped-not-approved"
    linked_note="execute-mode-blocked-by-orchestration-gate"
  else
    linked_out_dir="${RUN_DIR}/linked-systems"
    mkdir -p "${linked_out_dir}"
    set +e
    bash "${LINKED_RUNNER}" \
      --issue "${ISSUE_NUMBER}" \
      --repo "${REPO}" \
      --mode "${LINKED_MODE}" \
      --systems "${LINKED_SYSTEMS}" \
      --max-parallel "${LINKED_MAX_PARALLEL}" \
      --out-dir "${linked_out_dir}" \
      > "${RUN_DIR}/linked-systems.out.log" 2> "${RUN_DIR}/linked-systems.err.log"
    linked_rc=$?
    set -e
    linked_run_dir="$(ls -dt "${linked_out_dir}"/linked-issue-"${ISSUE_NUMBER}"-* 2>/dev/null | head -n1 || true)"
    if (( linked_rc == 0 )); then
      linked_status="ok"
      linked_note="linked-systems-completed"
    else
      linked_status="error"
      linked_note="linked-systems-failed-see-logs"
    fi
  fi
fi

jq -n \
  --arg issue_number "${ISSUE_NUMBER}" \
  --arg issue_url "${ISSUE_URL}" \
  --arg run_dir "${RUN_DIR}" \
  --arg main "${MAIN_PROVIDER}" \
  --arg assist "${ASSIST_PROVIDER}" \
  --arg mode "${MULTI_AGENT_MODE}" \
  --arg glm_mode "${GLM_SUBAGENT_MODE}" \
  --argjson lanes "${lanes_total}" \
  --argjson min_consensus_lanes "${MIN_CONSENSUS_LANES}" \
  --argjson approve_count "${approve_count}" \
  --argjson total_count "${total_count}" \
  --argjson threshold "${threshold}" \
  --arg weighted_approve "${weighted_approve_score}" \
  --arg weighted_total "${weighted_total_score}" \
  --arg weighted_threshold "${weighted_threshold}" \
  --arg weighted_vote "${weighted_vote_passed}" \
  --arg high_risk "${high_risk}" \
  --argjson high_risk_count "${high_risk_count}" \
  --arg ok_to_execute "${ok_to_execute}" \
  --arg linked_mode "${LINKED_MODE}" \
  --arg linked_systems "${LINKED_SYSTEMS}" \
  --arg linked_status "${linked_status}" \
  --arg linked_run_dir "${linked_run_dir}" \
  --arg linked_note "${linked_note}" \
  --arg issue_risk_tier "${issue_risk_tier}" \
  --arg issue_risk_score "${issue_risk_score}" \
  --arg issue_risk_reasons "${issue_risk_reasons}" \
  --arg local_ambiguity_signal "${local_ambiguity_signal}" \
  --arg complex_claude_sub_required "${complex_claude_sub_required}" \
  --arg complex_claude_sub_reason "${complex_claude_sub_reason}" \
  --arg claude_sub_gate_required "${gate_required}" \
  --arg claude_sub_gate_requirement_kind "${gate_requirement_kind}" \
  --arg required_claude_assist_gate "${required_claude_assist_gate}" \
  --arg required_claude_assist_reason "${required_claude_assist_reason}" \
  --arg baseline_trio_gate "${baseline_trio_gate}" \
  --arg baseline_trio_reason "${baseline_trio_reason}" \
  --argjson codex_baseline_success "${codex_baseline_success}" \
  --argjson claude_baseline_success "${claude_baseline_success}" \
  --argjson glm_baseline_success "${glm_baseline_success}" \
  --argjson claude_session_count "${claude_session_count}" \
  --arg claude_sessions_file "${claude_sessions_file}" \
  --arg claude_resume_hint "${claude_resume_hint}" \
  '{
    issue_number:($issue_number|tonumber),
    issue_url:$issue_url,
    run_dir:$run_dir,
    main_orchestrator:$main,
    assist_orchestrator:$assist,
    multi_agent_mode:$mode,
    glm_subagent_mode:$glm_mode,
    lanes_configured:$lanes,
    minimum_consensus_lanes:$min_consensus_lanes,
    approve_count:$approve_count,
    total_count:$total_count,
    threshold:$threshold,
    weighted_approve_score:($weighted_approve|tonumber),
    weighted_total_score:($weighted_total|tonumber),
    weighted_threshold:($weighted_threshold|tonumber),
    weighted_vote_passed:($weighted_vote=="true"),
    high_risk:($high_risk=="true"),
    high_risk_count:$high_risk_count,
    ok_to_execute:($ok_to_execute=="true"),
    linked_systems_mode:$linked_mode,
    linked_systems_selection:$linked_systems,
    linked_systems_status:$linked_status,
    linked_systems_run_dir:$linked_run_dir,
    linked_systems_note:$linked_note,
    issue_risk_tier:$issue_risk_tier,
    issue_risk_score:($issue_risk_score|tonumber? // 0),
    issue_risk_reasons:$issue_risk_reasons,
    local_ambiguity_signal:($local_ambiguity_signal=="true"),
    complex_claude_sub_required:($complex_claude_sub_required=="true"),
    complex_claude_sub_reason:$complex_claude_sub_reason,
    claude_sub_gate_required:($claude_sub_gate_required=="true"),
    claude_sub_gate_requirement_kind:$claude_sub_gate_requirement_kind,
    required_claude_assist_gate:$required_claude_assist_gate,
    required_claude_assist_reason:$required_claude_assist_reason,
    baseline_trio_gate:$baseline_trio_gate,
    baseline_trio_reason:$baseline_trio_reason,
    codex_baseline_success:$codex_baseline_success,
    claude_baseline_success:$claude_baseline_success,
    glm_baseline_success:$glm_baseline_success,
    claude_session_count:$claude_session_count,
    claude_sessions_file:$claude_sessions_file,
    claude_resume_hint:$claude_resume_hint
  }' > "${integrated_json}"

summary_md="${RUN_DIR}/summary.md"
cat > "${summary_md}" <<EOF
## Local Tutti Integrated Review

- issue: #${ISSUE_NUMBER} (${ISSUE_URL})
- issue context source: ${issue_context_source}
- main orchestrator: ${MAIN_PROVIDER}
- assist orchestrator: ${ASSIST_PROVIDER}
- multi-agent mode: ${MULTI_AGENT_MODE}
- glm subagent mode: ${GLM_SUBAGENT_MODE}
- lanes configured: ${lanes_total}
- minimum consensus lanes: ${MIN_CONSENSUS_LANES}
- approvals: ${approve_count}/${total_count} (threshold ${threshold})
- weighted approvals: ${weighted_approve_score}/${weighted_total_score} (threshold ${weighted_threshold})
- weighted vote passed: ${weighted_vote_passed}
- high-risk findings: ${high_risk_count}
- issue risk tier: ${issue_risk_tier} (score=${issue_risk_score}, reasons=${issue_risk_reasons})
- local ambiguity signal: ${local_ambiguity_signal}
- complex claude-sub requirement: ${complex_claude_sub_required} (${complex_claude_sub_reason})
- claude sub gate required: ${gate_required} (${gate_requirement_kind})
- linked systems mode: ${LINKED_MODE} (selection ${LINKED_SYSTEMS})
- linked systems status: ${linked_status} (${linked_note})
- linked systems run dir: ${linked_run_dir}
- required claude assist gate: ${required_claude_assist_gate} (${required_claude_assist_reason})
- baseline trio gate (codex+claude+glm): ${baseline_trio_gate} (${baseline_trio_reason}; codex=${codex_baseline_success}, claude=${claude_baseline_success}, glm=${glm_baseline_success})
- claude session handoff: ${claude_session_handoff} (sessions ${claude_session_count})
- claude sessions file: ${claude_sessions_file}
- claude resume hint: ${claude_resume_hint}
- ok_to_execute: ${ok_to_execute}
- run dir: ${RUN_DIR}
EOF

if [[ "${POST_ISSUE_COMMENT}" == "true" ]]; then
  gh issue comment "${ISSUE_NUMBER}" --repo "${REPO}" --body-file "${summary_md}" >/dev/null
fi

echo "Local orchestration completed."
echo "Run directory: ${RUN_DIR}"
cat "${summary_md}"
