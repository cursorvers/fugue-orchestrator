#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
SESSION_NAME_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-session-name.sh"
THREAD_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-codex-thread.sh"
RUNTIME_LAUNCH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-launch.sh"
TMUX_BIN="${TMUX_BIN:-tmux}"

usage() {
  cat <<'EOF'
Usage:
  kernel-session-adopt.sh adopt <session:window> [purpose]
EOF
}

require_tmux() {
  command -v "${TMUX_BIN}" >/dev/null 2>&1 || {
    echo "tmux is required" >&2
    exit 1
  }
}

current_project() {
  if [[ -n "${KERNEL_PROJECT:-}" ]]; then
    printf '%s\n' "${KERNEL_PROJECT}"
    return 0
  fi
  basename "${PWD}"
}

slug_session_name() {
  local project="${1:-}" purpose="${2:-}" short_id="${3:-}"
  KERNEL_PROJECT="${project}" KERNEL_PURPOSE="${purpose}" KERNEL_SESSION_SHORT_ID="${short_id}" \
    bash "${SESSION_NAME_SCRIPT}" slug
}

label_thread_title() {
  local project="${1:-}" purpose="${2:-}" short_id="${3:-}"
  KERNEL_PROJECT="${project}" KERNEL_PURPOSE="${purpose}" KERNEL_SESSION_SHORT_ID="${short_id}" \
    bash "${SESSION_NAME_SCRIPT}" label
}

choose_session_name() {
  local project="${1:-}" purpose="${2:-}" candidate short_id
  candidate="$(slug_session_name "${project}" "${purpose}")"
  if ! "${TMUX_BIN}" has-session -t "=${candidate}" 2>/dev/null; then
    printf '%s\n' "${candidate}"
    return 0
  fi
  short_id="$(date '+%H%M%S')"
  printf '%s\n' "$(slug_session_name "${project}" "${purpose}" "${short_id}")"
}

mint_run_id() {
  local project="${1:-}" purpose="${2:-}" host ts
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown-host')"
  ts="$(date '+%Y%m%dT%H%M%S')"
  printf 'adopt:%s:%s:%s:%s:%s\n' "${host}" "${project}" "${purpose}" "${ts}" "$$"
}

ensure_windows() {
  local session_name="${1:-}"
  "${TMUX_BIN}" rename-window -t "=${session_name}:1" main >/dev/null 2>&1 || true
  "${TMUX_BIN}" list-windows -t "=${session_name}" -F '#W' | grep -Fxq logs || "${TMUX_BIN}" new-window -t "=${session_name}" -n logs >/dev/null
  "${TMUX_BIN}" list-windows -t "=${session_name}" -F '#W' | grep -Fxq review || "${TMUX_BIN}" new-window -t "=${session_name}" -n review >/dev/null
  "${TMUX_BIN}" list-windows -t "=${session_name}" -F '#W' | grep -Fxq ops || "${TMUX_BIN}" new-window -t "=${session_name}" -n ops >/dev/null
}

launch_runtime_thread() {
  local run_id="${1:-}" session_name="${2:-}" runtime="${3:-kernel}" project="${4:-kernel-workspace}" purpose="${5:-unspecified}"
  local launch_command
  [[ -n "${run_id}" && -n "${session_name}" ]] || return 0
  [[ "${KERNEL_ADOPT_LAUNCH_CODEX_THREAD:-true}" == "true" ]] || return 0
  [[ -f "${RUNTIME_LAUNCH_SCRIPT}" ]] || return 0
  launch_command="$(bash "${RUNTIME_LAUNCH_SCRIPT}" command resume "${runtime}" "${run_id}" "${project}" "${purpose}" "${session_name}")"
  "${TMUX_BIN}" send-keys -t "=${session_name}:main" "${launch_command}" C-m
}

cmd_adopt() {
  local source="${1:-}" explicit_purpose="${2:-}"
  local source_session source_window project purpose target_session run_id codex_thread_title summary
  [[ -n "${source}" && "${source}" == *:* ]] || {
    echo "source must be session:window" >&2
    exit 2
  }
  require_tmux

  source_session="${source%%:*}"
  source_window="${source#*:}"
  project="$(current_project)"
  purpose="${explicit_purpose:-${source_window}}"
  target_session="$(choose_session_name "${project}" "${purpose}")"
  run_id="$(mint_run_id "${project}" "${purpose}")"
  codex_thread_title="$(label_thread_title "${project}" "${purpose}")"
  summary="Adopted from ${source_session}:${source_window}"

  "${TMUX_BIN}" new-session -d -s "${target_session}" -n bootstrap >/dev/null
  "${TMUX_BIN}" move-window -k -s "=${source_session}:${source_window}" -t "=${target_session}:1" >/dev/null
  ensure_windows "${target_session}"

  KERNEL_RUN_ID="${run_id}" \
  KERNEL_PROJECT="${project}" \
  KERNEL_PURPOSE="${purpose}" \
  KERNEL_PHASE="${KERNEL_ADOPT_PHASE:-implement}" \
  KERNEL_MODE="${KERNEL_ADOPT_MODE:-healthy}" \
  KERNEL_RUNTIME="${KERNEL_ADOPT_RUNTIME:-kernel}" \
  KERNEL_OWNER="${KERNEL_OWNER:-local-operator}" \
  KERNEL_TMUX_SESSION="${target_session}" \
  KERNEL_NEXT_ACTIONS="${KERNEL_NEXT_ACTIONS:-continue adopted session}" \
  KERNEL_SUMMARY="${summary}" \
  KERNEL_DECISIONS="adopt ${source_session}:${source_window}" \
  KERNEL_BLOCKING_REASON="" \
  bash "${COMPACT_SCRIPT}" update manual_snapshot >/dev/null

  launch_runtime_thread "${run_id}" "${target_session}" "${KERNEL_ADOPT_RUNTIME:-kernel}" "${project}" "${purpose}"

  printf 'kernel session adopted:\n'
  printf '  - run id: %s\n' "${run_id}"
  printf '  - project: %s\n' "${project}"
  printf '  - purpose: %s\n' "${purpose}"
  printf '  - source: %s:%s\n' "${source_session}" "${source_window}"
  printf '  - tmux session: %s\n' "${target_session}"
  printf '  - runtime: %s\n' "${KERNEL_ADOPT_RUNTIME:-kernel}"
  printf '  - codex thread: %s\n' "${codex_thread_title}"
}

cmd="${1:-help}"
case "${cmd}" in
  adopt)
    shift || true
    cmd_adopt "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown subcommand: ${cmd}" >&2
    usage >&2
    exit 2
    ;;
esac
