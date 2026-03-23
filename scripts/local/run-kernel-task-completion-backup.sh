#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOLS_ROOT="${TOOLS_ROOT:-${HOME}/Dev/tools/codex-kernel-guard}"
STATE_ROOT="${STATE_ROOT:-${HOME}/Dev/kernel-orchestration-tools/state}"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
GHA_REPO="${GHA_REPO:-cursorvers/fugue-orchestrator}"
GHA_WORKFLOW="${GHA_WORKFLOW:-kernel-task-completion-backup.yml}"
GHA_REF="${GHA_REF:-}"
GHA_DISPATCH_MODE="${GHA_DISPATCH_MODE:-auto}"
RECENT_DAYS="${RECENT_DAYS:-7}"
NO_GHA="${NO_GHA:-false}"
DRY_RUN="${DRY_RUN:-false}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 2
fi

EXTERNAL_BACKUP_TOOL_AVAILABLE="false"
if [[ -d "${TOOLS_ROOT}/src/codex_kernel_guard" ]]; then
  EXTERNAL_BACKUP_TOOL_AVAILABLE="true"
fi

mkdir -p "${STATE_ROOT}"

compact_path_for_run() {
  local run_id="${1:-}"
  local compact_dir="${KERNEL_COMPACT_DIR:-$HOME/.config/kernel/compact}"
  printf '%s/%s.json\n' "${compact_dir}" "$(printf '%s' "${run_id}" | tr '/:' '__')"
}

sanitize_token() {
  printf '%s' "${1:-}" | tr -cd 'A-Za-z0-9._-'
}

fallback_record_id() {
  local completed_raw safe_session safe_assistant safe_source
  completed_raw="$(printf '%s' "${completed_at:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}" | tr -cd '0-9TZ')"
  safe_session="$(sanitize_token "${session_id}")"
  safe_assistant="$(sanitize_token "${assistant}")"
  safe_source="$(sanitize_token "${source_name}")"
  printf '%s\n' "${completed_raw}-${safe_assistant}-${safe_source}-${safe_session}"
}

fallback_dispatch_token() {
  python3 - "$1" "$2" "$3" <<'PY'
import hashlib, sys
raw = "|".join(sys.argv[1:])
print(hashlib.sha256(raw.encode()).hexdigest()[:12])
PY
}

fallback_observed_models_json() {
  local run_id="${1:-}"
  local compact_path
  compact_path="$(compact_path_for_run "${run_id}")"
  if [[ -f "${compact_path}" ]]; then
    jq -c '(.active_models // []) | map({provider: .})' "${compact_path}"
  else
    printf '[]\n'
  fi
}

fallback_orchestration_compliance() {
  case "${source_name}" in
    kernel-progress-save|kernel-phase-complete|kernel-run-complete)
      printf '%s\n' "${source_name}"
      ;;
    *)
      printf 'kernel-run-complete\n'
      ;;
  esac
}

fallback_write_record() {
  local record_id dispatch_token mirror_path receipt_path payload_path payload_b64 observed_models_json orchestration_compliance
  local completed_value="${completed_at:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

  record_id="$(fallback_record_id)"
  dispatch_token="$(fallback_dispatch_token "${record_id}" "${summary}" "${completed_value}")"
  mirror_path="backups/task-completion/${record_id}/${dispatch_token}.json"
  receipt_path="backups/task-completion-receipts/${record_id}/${dispatch_token}.json"
  payload_path="${STATE_ROOT}/${record_id}.payload.json"
  observed_models_json="$(fallback_observed_models_json "${session_id}")"
  orchestration_compliance="$(fallback_orchestration_compliance)"

  python3 - "$record_id" "$assistant" "$source_name" "$session_id" "$completed_value" "$summary" "$cwd" "$title" "$GHA_REPO" "$GHA_WORKFLOW" "$dispatch_token" "$mirror_path" "$receipt_path" "$observed_models_json" "$payload_path" "$orchestration_compliance" <<'PY'
import json, sys
record_id, assistant, source_name, session_id, completed_at, summary, cwd, title, gha_repo, gha_workflow, token, mirror_path, receipt_path, observed_models_json, payload_path, orchestration_compliance = sys.argv[1:]
payload = {
    "record_id": record_id,
    "assistant": assistant,
    "source": source_name,
    "session_id": session_id,
    "completed_at": completed_at,
    "summary_text": summary,
    "cwd": cwd,
    "title": title,
    "gha_repo": gha_repo,
    "gha_workflow": gha_workflow,
    "gha_dispatch_token": token,
    "gha_mirror_path": mirror_path,
    "gha_receipt_path": receipt_path,
    "orchestration_compliance": orchestration_compliance,
    "observed_models": json.loads(observed_models_json),
}
with open(payload_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=True, separators=(",", ":"))
PY

  printf '%s\n' "${payload_path}"
}

fallback_append_journal() {
  local payload_path="${1:-}"
  local journal_path="${STATE_ROOT}/task-completion-journal.jsonl"
  [[ -f "${payload_path}" ]] || return 1
  cat "${payload_path}" >> "${journal_path}"
  printf '\n' >> "${journal_path}"
}

fallback_dispatch_gha() {
  local payload_path="${1:-}"
  local record_id payload_b64
  record_id="$(jq -r '.record_id' "${payload_path}")"
  payload_b64="$(base64 < "${payload_path}" | tr -d '\n')"
  gh api "repos/${GHA_REPO}/dispatches" \
    --method POST \
    -f event_type="kernel-task-completion-backup" \
    -f client_payload[record_id]="${record_id}" \
    -f client_payload[payload_b64]="${payload_b64}" \
    >/dev/null
}

acquire_lock() {
  local wait_seconds="${1:-0}"
  local waited=0
  while ! mkdir "${lock_dir}" 2>/dev/null; do
    if (( waited >= wait_seconds )); then
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  trap 'rmdir "${lock_dir}" >/dev/null 2>&1 || true' EXIT
}

mode="scan"
assistant=""
source_name=""
session_id=""
summary=""
cwd="${REPO_ROOT}"
title=""
completed_at=""
lock_dir="${STATE_ROOT}/task-completion-backup.lock"

usage() {
  cat <<'EOF'
Usage:
  scripts/local/run-kernel-task-completion-backup.sh [options]

Options:
  --assistant <name>     Record an explicit completion event instead of scanning Codex sessions
  --source <name>        Explicit event source label
  --session-id <id>      Explicit session identifier
  --summary <text>       Explicit completion summary
  --cwd <path>           Working directory metadata for explicit records
  --title <text>         Title metadata for explicit records
  --completed-at <iso>   Completion timestamp override
  --no-gha               Skip GitHub Actions dispatch
  --dry-run              Mark dispatch success without calling GitHub
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --assistant)
      mode="record"
      assistant="${2:-}"
      shift 2
      ;;
    --source)
      source_name="${2:-}"
      shift 2
      ;;
    --session-id)
      session_id="${2:-}"
      shift 2
      ;;
    --summary)
      summary="${2:-}"
      shift 2
      ;;
    --cwd)
      cwd="${2:-}"
      shift 2
      ;;
    --title)
      title="${2:-}"
      shift 2
      ;;
    --completed-at)
      completed_at="${2:-}"
      shift 2
      ;;
    --no-gha)
      NO_GHA="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
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

if [[ "${EXTERNAL_BACKUP_TOOL_AVAILABLE}" == "true" ]]; then
  common_args=(
    "--index-db" "${STATE_ROOT}/task-completion-backup.sqlite3"
    "--journal-path" "${STATE_ROOT}/task-completion-journal.jsonl"
    "--gha-repo" "${GHA_REPO}"
    "--gha-workflow" "${GHA_WORKFLOW}"
  )

  if [[ -n "${GHA_REF}" ]]; then
    common_args+=(--gha-ref "${GHA_REF}")
  fi
  common_args+=(--gha-dispatch-mode "${GHA_DISPATCH_MODE}")
  if [[ "${NO_GHA}" == "true" ]]; then
    common_args+=(--no-gha)
  fi
  if [[ "${DRY_RUN}" == "true" ]]; then
    common_args+=(--dry-run)
  fi

  export PYTHONPATH="${TOOLS_ROOT}/src${PYTHONPATH:+:${PYTHONPATH}}"
fi

if [[ "${mode}" == "record" ]]; then
  acquire_lock 20 || {
    echo "task completion backup lock busy; explicit record skipped" >&2
    exit 0
  }
  if [[ -z "${assistant}" || -z "${source_name}" || -z "${session_id}" || -z "${summary}" ]]; then
    echo "explicit record mode requires --assistant, --source, --session-id, and --summary" >&2
    exit 2
  fi
  if [[ "${EXTERNAL_BACKUP_TOOL_AVAILABLE}" == "true" ]]; then
    record_args=(
      --assistant "${assistant}"
      --source "${source_name}"
      --session-id "${session_id}"
      --summary "${summary}"
      --cwd "${cwd}"
      --title "${title}"
    )
    if [[ -n "${completed_at}" ]]; then
      record_args+=(--completed-at "${completed_at}")
    fi
    python3 -m codex_kernel_guard.cli backup-record \
      "${record_args[@]}" \
      "${common_args[@]}"
    exit $?
  fi

  payload_path="$(fallback_write_record)"
  fallback_append_journal "${payload_path}"
  if [[ "${NO_GHA}" == "true" ]]; then
    exit 0
  fi
  if [[ "${DRY_RUN}" == "true" ]]; then
    exit 0
  fi
  fallback_dispatch_gha "${payload_path}"
  exit 0
fi

if [[ "${EXTERNAL_BACKUP_TOOL_AVAILABLE}" != "true" ]]; then
  exit 0
fi

acquire_lock 0 || exit 0
python3 -m codex_kernel_guard.cli backup-scan \
  --codex-home "${CODEX_HOME}" \
  --recent-days "${RECENT_DAYS}" \
  "${common_args[@]}"
exit $?
