#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNNER_SCRIPT="${KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT:-${ROOT_DIR}/scripts/local/run-kernel-task-completion-backup.sh}"
AUTO_RECORD="${KERNEL_AUTO_MILESTONE_RECORDING:-true}"
AUTO_RECORD_PHASES="${KERNEL_AUTO_RECORD_PHASES:-plan,implement,verify}"
AUTO_RECORD_NO_GHA="${KERNEL_AUTO_RECORD_NO_GHA:-false}"
AUTO_RECORD_DRY_RUN="${KERNEL_AUTO_RECORD_DRY_RUN:-false}"
ORCH_DRY_RUN_VALUE="${ORCH_DRY_RUN:-false}"

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

cmd="${1:-}"
case "${cmd}" in
  phase)
    shift || true
    cmd_phase "$@"
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
