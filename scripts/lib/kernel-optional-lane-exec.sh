#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUDGET_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-budget.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
PICKER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-specialist-picker.sh"
NOTE_PREFIX="${KERNEL_OPTIONAL_LANE_NOTE_PREFIX:-exec}"
COPILOT_AUTOPILOT_ALLOWED="${KERNEL_COPILOT_AUTOPILOT_ALLOWED:-false}"

repo_slug() {
  if [[ -n "${KERNEL_REPO_SLUG:-}" ]]; then
    printf '%s\n' "${KERNEL_REPO_SLUG}"
    return 0
  fi
  basename "${ROOT_DIR}"
}

resolve_run_id() {
  local repo host session_name
  repo="$(repo_slug)"
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  if [[ -n "${KERNEL_OPTIONAL_LANE_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_OPTIONAL_LANE_RUN_ID}"
    return 0
  fi
  if [[ -n "${KERNEL_GLM_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_GLM_RUN_ID}"
    return 0
  fi
  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    session_name="$(tmux display-message -p '#S' 2>/dev/null || true)"
    if [[ -n "${session_name}" ]]; then
      printf '%s:%s\n' "${repo}" "${session_name}"
      return 0
    fi
  fi
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown-host')"
  printf 'adhoc:%s:%s:%s\n' "${host}" "${repo}" "${PPID:-$$}"
}

RUN_ID="${KERNEL_RUN_ID:-$(resolve_run_id)}"
export KERNEL_RUN_ID="${RUN_ID}"

usage() {
  cat <<'EOF'
Usage:
  kernel-optional-lane-exec.sh <gemini-cli|cursor-cli|copilot-cli|auto> [args...]
EOF
}

canonical_provider() {
  case "${1:-}" in
    auto|specialist|best) printf 'auto\n' ;;
    gemini|gemini-cli) printf 'gemini-cli\n' ;;
    cursor|cursor-cli) printf 'cursor-cli\n' ;;
    copilot|copilot-cli) printf 'copilot-cli\n' ;;
    *)
      printf 'unknown\n'
      return 1
      ;;
  esac
}

provider_command() {
  case "$1" in
    gemini-cli)
      printf '%s\n' "${KERNEL_GEMINI_BIN:-gemini}"
      ;;
    cursor-cli)
      printf '%s\n' "${KERNEL_CURSOR_BIN:-cursor}"
      ;;
    copilot-cli)
      printf '%s\n' "${KERNEL_COPILOT_BIN:-copilot}"
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_provider_command() {
  local provider="$1"
  local cmd
  cmd="$(provider_command "${provider}")"
  if [[ "${provider}" == "copilot-cli" && "${cmd}" == "copilot" ]] && ! command -v "${cmd}" >/dev/null 2>&1 && command -v gh >/dev/null 2>&1; then
    cmd="gh"
  fi
  command -v "${cmd}" >/dev/null 2>&1 || {
    echo "optional lane command missing: ${cmd}" >&2
    return 127
  }
  printf '%s\n' "${cmd}"
}

ensure_provider_ready() {
  local provider="$1"
  bash "${PICKER_SCRIPT}" ready "${provider}" >/dev/null 2>&1 || {
    echo "optional lane provider not ready: ${provider}" >&2
    return 1
  }
}

maybe_reject_copilot_autopilot() {
  local arg
  [[ "$1" == "copilot-cli" ]] || return 0
  [[ "${COPILOT_AUTOPILOT_ALLOWED}" == "true" ]] && return 0
  shift
  for arg in "$@"; do
    case "${arg}" in
      autopilot|--autopilot|agent|--agent-mode)
        echo "copilot-cli autopilot/agent mode is disabled (KERNEL_COPILOT_AUTOPILOT_ALLOWED=false)." >&2
        return 1
        ;;
    esac
  done
}

invoke_command() {
  local provider="$1"
  shift

  local cmd
  cmd="$(ensure_provider_command "${provider}")"

  case "${provider}" in
    gemini-cli)
      "${cmd}" "$@"
      ;;
    cursor-cli)
      "${cmd}" agent "$@"
      ;;
    copilot-cli)
      if [[ "${cmd}" == "gh" ]]; then
        if (($# > 0)); then
          "${cmd}" copilot -- "$@"
        else
          "${cmd}" copilot
        fi
      else
        "${cmd}" "$@"
      fi
      ;;
  esac
}

main() {
  local provider
  provider="$(canonical_provider "${1:-}")" || {
    usage >&2
    exit 2
  }
  shift || true

  if [[ "${provider}" == "auto" ]]; then
    provider="$(bash "${PICKER_SCRIPT}" pick)"
  fi

  maybe_reject_copilot_autopilot "${provider}" "$@" || exit 1

  local note="${NOTE_PREFIX}:${provider}"
  if [[ $# -gt 0 ]]; then
    note="${note}:$(printf '%s' "$1" | tr ' ' '_' | cut -c1-40)"
  fi

  ensure_provider_command "${provider}" >/dev/null
  ensure_provider_ready "${provider}" || exit 1
  KERNEL_RUN_ID="${RUN_ID}" bash "${BUDGET_SCRIPT}" consume "${provider}" 1 "${note}" >/dev/null

  set +e
  invoke_command "${provider}" "$@"
  local rc=$?
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    KERNEL_RUN_ID="${RUN_ID}" bash "${LEDGER_SCRIPT}" record-provider "${provider}" success "${note}" >/dev/null
  else
    KERNEL_RUN_ID="${RUN_ID}" bash "${BUDGET_SCRIPT}" refund "${provider}" 1 "${note}:failure" >/dev/null
    KERNEL_RUN_ID="${RUN_ID}" bash "${LEDGER_SCRIPT}" record-provider "${provider}" failure "${note}" >/dev/null
  fi

  return "${rc}"
}

main "$@"
