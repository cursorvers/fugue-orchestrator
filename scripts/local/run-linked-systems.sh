#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-cursorvers/fugue-orchestrator}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
MODE="${MODE:-smoke}" # smoke|execute
MAX_PARALLEL="${MAX_PARALLEL:-3}"
SYSTEMS="${SYSTEMS:-all}" # all|id1,id2
OUT_DIR="${OUT_DIR:-.fugue/local-run}"
POST_ISSUE_COMMENT="${POST_ISSUE_COMMENT:-true}"
MANIFEST_PATH="${MANIFEST_PATH:-config/integrations/local-systems.json}"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/run-linked-systems.sh --issue <number> [options]

Options:
  --issue <n>              GitHub issue number (required)
  --repo <owner/repo>      Repository containing issue (default: cursorvers/fugue-orchestrator)
  --mode <smoke|execute>   Execution mode (default: smoke)
  --systems <all|csv>      Run all enabled systems or selected IDs (default: all)
  --max-parallel <n>       Parallel adapter limit (default: 3)
  --out-dir <path>         Output directory (default: .fugue/local-run)
  --comment                Post summary comment to issue
  -h, --help               Show help
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
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --systems)
      SYSTEMS="${2:-}"
      shift 2
      ;;
    --max-parallel)
      MAX_PARALLEL="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
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
  exit 2
fi
if [[ "${MODE}" != "smoke" && "${MODE}" != "execute" ]]; then
  echo "Error: --mode must be smoke|execute." >&2
  exit 2
fi
if ! [[ "${MAX_PARALLEL}" =~ ^[0-9]+$ ]] || (( MAX_PARALLEL < 1 )); then
  echo "Error: --max-parallel must be a positive integer." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 2
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh is required." >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest_file="${ROOT_DIR}/${MANIFEST_PATH}"
[[ -f "${manifest_file}" ]] || { echo "Error: manifest not found: ${manifest_file}" >&2; exit 2; }

if [[ "${OUT_DIR}" != /* ]]; then
  OUT_DIR="${ROOT_DIR}/${OUT_DIR}"
fi

issue_json="$(gh issue view "${ISSUE_NUMBER}" --repo "${REPO}" --json number,title,body,url)"
ISSUE_TITLE="$(echo "${issue_json}" | jq -r '.title // ""')"
ISSUE_BODY="$(echo "${issue_json}" | jq -r '.body // ""')"
ISSUE_URL="$(echo "${issue_json}" | jq -r '.url // ""')"

run_id="$(date +%Y%m%d-%H%M%S)-$$"
RUN_DIR="${OUT_DIR}/linked-issue-${ISSUE_NUMBER}-${run_id}"
SYSTEM_DIR="${RUN_DIR}/systems"
mkdir -p "${SYSTEM_DIR}"

selector='[ .systems[] | select(.enabled == true) ]'
if [[ "${SYSTEMS}" != "all" ]]; then
  IFS=',' read -r -a requested <<< "${SYSTEMS}"
  requested_json="$(printf '%s\n' "${requested[@]}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | sed '/^$/d' | jq -R . | jq -s .)"
  requested_count="$(echo "${requested_json}" | jq 'length')"
  if (( requested_count == 0 )); then
    echo "Error: --systems provided but no valid IDs were parsed." >&2
    exit 2
  fi
  selector='[ .systems[] | select(.enabled == true and (.id as $id | $requested | index($id))) ]'
fi

selected_json="$(jq -c --argjson requested "${requested_json:-[]}" "${selector}" "${manifest_file}")"
selected_count="$(echo "${selected_json}" | jq 'length')"
if [[ "${SYSTEMS}" != "all" ]]; then
  selected_ids_json="$(echo "${selected_json}" | jq -c '[ .[].id ]')"
  missing_ids_json="$(jq -cn --argjson req "${requested_json}" --argjson selected "${selected_ids_json}" '[ $req[] | select(($selected | index(.)) | not) ]')"
  missing_count="$(echo "${missing_ids_json}" | jq 'length')"
  if (( missing_count > 0 )); then
    echo "Error: unknown or disabled system IDs: $(echo "${missing_ids_json}" | jq -r 'join(", ")')" >&2
    exit 2
  fi
fi
if (( selected_count == 0 )); then
  echo "No linked systems selected."
  exit 0
fi

systems_jsonl="${RUN_DIR}/systems.jsonl"
echo "${selected_json}" | jq -c '.[]' > "${systems_jsonl}"

run_one() {
  local item="$1"
  local id name adapter adapter_path sys_dir out_log err_log result_file
  id="$(echo "${item}" | jq -r '.id')"
  name="$(echo "${item}" | jq -r '.name')"
  adapter="$(echo "${item}" | jq -r '.adapter')"
  adapter_path="${ROOT_DIR}/${adapter}"
  sys_dir="${SYSTEM_DIR}/${id}"
  out_log="${sys_dir}/stdout.log"
  err_log="${sys_dir}/stderr.log"
  result_file="${sys_dir}/result.json"
  mkdir -p "${sys_dir}"

  if [[ ! -x "${adapter_path}" ]]; then
    jq -n \
      --arg id "${id}" \
      --arg name "${name}" \
      --arg adapter "${adapter}" \
      '{
        id:$id,
        name:$name,
        adapter:$adapter,
        status:"error",
        message:"adapter missing or not executable",
        exit_code:127
      }' > "${result_file}"
    return 0
  fi

  set +e
  (
    cd "${ROOT_DIR}"
    FUGUE_ISSUE_NUMBER="${ISSUE_NUMBER}" \
    FUGUE_ISSUE_TITLE="${ISSUE_TITLE}" \
    FUGUE_ISSUE_BODY="${ISSUE_BODY}" \
    FUGUE_ISSUE_URL="${ISSUE_URL}" \
    FUGUE_RUN_DIR="${RUN_DIR}" \
    bash "${adapter_path}" --mode "${MODE}" --run-dir "${sys_dir}"
  ) >"${out_log}" 2>"${err_log}"
  rc=$?
  set -e

  status="ok"
  if (( rc != 0 )); then
    status="error"
  fi
  jq -n \
    --arg id "${id}" \
    --arg name "${name}" \
    --arg adapter "${adapter}" \
    --arg status "${status}" \
    --arg out_log "${out_log}" \
    --arg err_log "${err_log}" \
    --arg mode "${MODE}" \
    --argjson exit_code "${rc}" \
    '{
      id:$id,
      name:$name,
      adapter:$adapter,
      mode:$mode,
      status:$status,
      exit_code:$exit_code,
      stdout_log:$out_log,
      stderr_log:$err_log
    }' > "${result_file}"
}

export -f run_one
export ROOT_DIR SYSTEM_DIR ISSUE_NUMBER ISSUE_TITLE ISSUE_BODY ISSUE_URL RUN_DIR MODE

while IFS= read -r row; do
  run_one "${row}" </dev/null &
  while (( $(jobs -rp | wc -l | tr -d ' ') >= MAX_PARALLEL )); do
    sleep 0.2
  done
done < "${systems_jsonl}"

job_failures=0
for pid in $(jobs -rp); do
  if ! wait "${pid}"; then
    job_failures=$((job_failures + 1))
  fi
done

results_json="${RUN_DIR}/results.json"
jq -s '.' "${SYSTEM_DIR}"/*/result.json > "${results_json}"

ok_count="$(jq '[.[] | select(.status == "ok")] | length' "${results_json}")"
error_count="$(jq '[.[] | select(.status == "error")] | length' "${results_json}")"
overall_status="ok"
if (( error_count > 0 || job_failures > 0 )); then
  overall_status="error"
fi

summary_md="${RUN_DIR}/summary.md"
cat > "${summary_md}" <<EOF
## Linked Systems (${MODE})

- issue: #${ISSUE_NUMBER} (${ISSUE_URL})
- selected systems: ${selected_count}
- success: ${ok_count}
- error: ${error_count}
- status: ${overall_status}
- run dir: ${RUN_DIR}
EOF

integrated_json="${RUN_DIR}/integrated.json"
jq -n \
  --arg issue_number "${ISSUE_NUMBER}" \
  --arg issue_url "${ISSUE_URL}" \
  --arg mode "${MODE}" \
  --arg run_dir "${RUN_DIR}" \
  --arg status "${overall_status}" \
  --argjson selected "${selected_count}" \
  --argjson success "${ok_count}" \
  --argjson error "${error_count}" \
  '{
    issue_number:($issue_number|tonumber),
    issue_url:$issue_url,
    mode:$mode,
    run_dir:$run_dir,
    status:$status,
    selected:$selected,
    success:$success,
    error:$error
  }' > "${integrated_json}"

if [[ "${POST_ISSUE_COMMENT}" == "true" ]]; then
  gh issue comment "${ISSUE_NUMBER}" --repo "${REPO}" --body-file "${summary_md}" >/dev/null
fi

# Dispatch results back to consumer repo if configured.
if [[ -n "${CONSUMER_REPO:-}" && -n "${TARGET_REPO_PAT:-}" ]]; then
  dispatch_payload="$(jq -n \
    --arg event_type "fugue-linked-result" \
    --arg issue "${CONSUMER_ISSUE:-}" \
    --arg status "${overall_status}" \
    --argjson success "${ok_count}" \
    --argjson error "${error_count}" \
    --arg mode "${MODE}" \
    --arg source_issue "${ISSUE_NUMBER}" \
    '{
      event_type: $event_type,
      client_payload: {
        issue: $issue,
        status: $status,
        success_count: $success,
        error_count: $error,
        mode: $mode,
        source_issue: $source_issue
      }
    }')"
  if curl -sS -o /dev/null -w "%{http_code}" \
    -X POST "https://api.github.com/repos/${CONSUMER_REPO}/dispatches" \
    -H "Authorization: token ${TARGET_REPO_PAT}" \
    -H "Accept: application/vnd.github+json" \
    -d "${dispatch_payload}" | grep -q "^2"; then
    echo "Dispatched result to ${CONSUMER_REPO}."
  else
    echo "Warning: failed to dispatch result to ${CONSUMER_REPO}." >&2
  fi
fi

echo "Linked systems completed."
echo "Run directory: ${RUN_DIR}"
cat "${summary_md}"
