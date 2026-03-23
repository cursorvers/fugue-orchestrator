#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNNER_SCRIPT="${KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT:-${ROOT_DIR}/scripts/local/run-kernel-task-completion-backup.sh}"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
AUTO_RECORD="${KERNEL_AUTO_MILESTONE_RECORDING:-true}"
AUTO_RECORD_PHASES="${KERNEL_AUTO_RECORD_PHASES:-plan,implement,verify}"
AUTO_RECORD_NO_GHA="${KERNEL_AUTO_RECORD_NO_GHA:-false}"
AUTO_RECORD_DRY_RUN="${KERNEL_AUTO_RECORD_DRY_RUN:-false}"
ORCH_DRY_RUN_VALUE="${ORCH_DRY_RUN:-false}"
CHECKPOINT_MIN_INTERVAL_SEC="${KERNEL_CHECKPOINT_SAVE_MIN_INTERVAL_SEC:-900}"
CHECKPOINT_SAVE_FORCE="${KERNEL_CHECKPOINT_SAVE_FORCE:-false}"
CHECKPOINT_LOCK_DIR=""

default_run_id() {
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  printf 'unknown-run\n'
}

usage() {
  cat <<'EOF'
Usage:
  kernel-milestone-record.sh phase <phase> [summary]
  kernel-milestone-record.sh checkpoint [summary]
EOF
}

run_id="$(default_run_id)"

should_skip() {
  [[ "${AUTO_RECORD}" == "false" ]] && return 0
  [[ "${ORCH_DRY_RUN_VALUE}" == "1" || "${ORCH_DRY_RUN_VALUE}" == "true" ]] && return 0
  [[ ! -f "${RUNNER_SCRIPT}" ]] && return 0
  return 1
}

phase_enabled() {
  local phase="${1:-}"
  printf '%s\n' "${AUTO_RECORD_PHASES}" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -Fxq "${phase}"
}

checkpoint_skip() {
  [[ "${AUTO_RECORD}" == "false" ]] && return 0
  [[ "${ORCH_DRY_RUN_VALUE}" == "1" || "${ORCH_DRY_RUN_VALUE}" == "true" ]] && return 0
  return 1
}

checkpoint_stamp_path() {
  local state_root safe_run_id
  state_root="${KERNEL_CHECKPOINT_STATE_DIR:-$(bash "${STATE_PATH_SCRIPT}" state-root)}"
  safe_run_id="$(printf '%s' "${run_id}" | tr '/:' '__')"
  mkdir -p "${state_root}/checkpoint-saves"
  printf '%s/checkpoint-saves/%s.last-save\n' "${state_root}" "${safe_run_id}"
}

checkpoint_lock_path() {
  printf '%s.lock\n' "$(checkpoint_stamp_path)"
}

acquire_checkpoint_lock() {
  local lock_dir
  lock_dir="$(checkpoint_lock_path)"
  mkdir -p "$(dirname "${lock_dir}")"
  if ! mkdir "${lock_dir}" 2>/dev/null; then
    echo "checkpoint save skipped: lock busy." >&2
    return 1
  fi
  CHECKPOINT_LOCK_DIR="${lock_dir}"
}

release_checkpoint_lock() {
  if [[ -n "${CHECKPOINT_LOCK_DIR}" ]]; then
    rmdir "${CHECKPOINT_LOCK_DIR}" >/dev/null 2>&1 || true
    CHECKPOINT_LOCK_DIR=""
  fi
}

checkpoint_allowed() {
  local stamp_path now last_saved
  [[ "${CHECKPOINT_SAVE_FORCE}" == "true" ]] && return 0
  [[ "${CHECKPOINT_MIN_INTERVAL_SEC}" == "0" ]] && return 0
  stamp_path="$(checkpoint_stamp_path)"
  [[ -f "${stamp_path}" ]] || return 0
  last_saved="$(tr -d '[:space:]' < "${stamp_path}")"
  [[ "${last_saved}" =~ ^[0-9]+$ ]] || return 0
  now="$(date '+%s')"
  (( now - last_saved >= CHECKPOINT_MIN_INTERVAL_SEC ))
}

write_checkpoint_stamp() {
  local stamp_path
  stamp_path="$(checkpoint_stamp_path)"
  printf '%s\n' "$(date '+%s')" > "${stamp_path}"
}

cmd_phase() {
  local phase="${1:-}"
  local summary="${2:-phase=${phase} completed}"
  local title project purpose
  local -a runner_flags=()

  [[ -n "${phase}" ]] || {
    echo "phase is required" >&2
    exit 2
  }

  should_skip && return 0
  phase_enabled "${phase}" || return 0

  project="${KERNEL_PROJECT:-kernel-workspace}"
  purpose="${KERNEL_PURPOSE:-unspecified}"
  title="${project}:${purpose}:${phase}"

  if [[ "${AUTO_RECORD_NO_GHA}" == "true" ]]; then
    runner_flags+=(--no-gha)
  fi
  if [[ "${AUTO_RECORD_DRY_RUN}" == "true" ]]; then
    runner_flags+=(--dry-run)
  fi

  bash "${RUNNER_SCRIPT}" \
    --assistant codex \
    --source kernel-phase-complete \
    --session-id "${run_id}" \
    --summary "${summary}" \
    --cwd "${ROOT_DIR}" \
    --title "${title}" \
    "${runner_flags[@]+"${runner_flags[@]}"}" \
    >/dev/null 2>&1 || true
}

cmd_checkpoint() {
  local summary="${1:-implementation progress checkpoint}"
  local title project purpose workspace_receipt_path
  local -a runner_flags=()

  checkpoint_skip && return 0
  acquire_checkpoint_lock || return 0
  if ! checkpoint_allowed; then
    echo "checkpoint save skipped: throttled." >&2
    release_checkpoint_lock
    return 0
  fi

  project="${KERNEL_PROJECT:-kernel-workspace}"
  purpose="${KERNEL_PURPOSE:-unspecified}"
  title="${project}:${purpose}:checkpoint"

  workspace_receipt_path="$(KERNEL_RUN_ID="${run_id}" bash "${WORKSPACE_SCRIPT}" write)"
  KERNEL_RUN_ID="${run_id}" \
  KERNEL_PHASE="${KERNEL_PHASE:-implement}" \
  KERNEL_WORKSPACE_RECEIPT_PATH="${workspace_receipt_path}" \
  KERNEL_SUMMARY="${summary}" \
    bash "${COMPACT_SCRIPT}" update manual_snapshot "${summary}" >/dev/null

  if [[ "${AUTO_RECORD_NO_GHA}" == "true" ]]; then
    runner_flags+=(--no-gha)
  fi
  if [[ "${AUTO_RECORD_DRY_RUN}" == "true" ]]; then
    runner_flags+=(--dry-run)
  fi

  if [[ -f "${RUNNER_SCRIPT}" ]]; then
    bash "${RUNNER_SCRIPT}" \
      --assistant codex \
      --source kernel-progress-save \
      --session-id "${run_id}" \
      --summary "${summary}" \
      --cwd "${ROOT_DIR}" \
      --title "${title}" \
      "${runner_flags[@]+"${runner_flags[@]}"}" \
      >/dev/null
  fi

  write_checkpoint_stamp
  release_checkpoint_lock
}

cmd="${1:-}"
case "${cmd}" in
  phase)
    shift || true
    cmd_phase "$@"
    ;;
  checkpoint)
    shift || true
    cmd_checkpoint "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    usage >&2
    exit 2
    ;;
esac
