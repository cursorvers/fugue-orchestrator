#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOLS_ROOT="${TOOLS_ROOT:-/Users/masayuki/Dev/tools/codex-kernel-guard}"
STATE_ROOT="${STATE_ROOT:-/Users/masayuki/Dev/kernel-orchestration-tools/state}"
CODEX_HOME="${CODEX_HOME:-/Users/masayuki/.codex}"
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

if [[ ! -d "${TOOLS_ROOT}/src/codex_kernel_guard" ]]; then
  echo "codex-kernel-guard source not found: ${TOOLS_ROOT}" >&2
  exit 2
fi

mkdir -p "${STATE_ROOT}"

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

if [[ "${mode}" == "record" ]]; then
  acquire_lock 20 || {
    echo "task completion backup lock busy; explicit record skipped" >&2
    exit 0
  }
  if [[ -z "${assistant}" || -z "${source_name}" || -z "${session_id}" || -z "${summary}" ]]; then
    echo "explicit record mode requires --assistant, --source, --session-id, and --summary" >&2
    exit 2
  fi
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

acquire_lock 0 || exit 0
python3 -m codex_kernel_guard.cli backup-scan \
  --codex-home "${CODEX_HOME}" \
  --recent-days "${RECENT_DAYS}" \
  "${common_args[@]}"
exit $?
