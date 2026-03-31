#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FOUR_PANE_LAUNCH_SCRIPT="${KERNEL_4PANE_LAUNCH_SCRIPT:-${ROOT_DIR}/scripts/local/kernel-4pane-launch.sh}"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
PROMPT_LAUNCH_BIN="${KERNEL_CODEX_PROMPT_LAUNCH_BIN:-$HOME/bin/codex-prompt-launch}"
STALE_HOURS="${KERNEL_STALE_HOURS:-24}"

usage() {
  cat <<'EOF'
Usage:
  kernel-entrypoint.sh [kernel-args...]
EOF
}

in_repo_context() {
  local current_root=""
  current_root="$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "${current_root}" && "${current_root}" == "${ROOT_DIR}" ]]
}

auto_4pane_enabled() {
  local value="${KERNEL_AUTO_4PANE:-true}"
  [[ "${value}" != "0" && "${value}" != "false" && "${value}" != "no" ]]
}

needs_prompt_passthrough() {
  [[ $# -gt 0 ]] || return 1
  case "${1:-}" in
    -h|--help|help)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

inside_managed_tmux() {
  [[ -n "${TMUX:-}" || -n "${KERNEL_TMUX_SESSION:-}" ]]
}

active_4pane_run_id() {
  local active_file
  active_file="$(bash "${STATE_PATH_SCRIPT}" 4pane-active-file 2>/dev/null || true)"
  [[ -n "${active_file}" && -f "${active_file}" ]] || return 1
  local run_id compact_path updated_at tmux_session workspace_receipt_path
  run_id="$(jq -r '.run_id // empty' "${active_file}")"
  [[ -n "${run_id}" ]] || return 1
  compact_path="$(compact_dir)/$(printf '%s' "${run_id}" | tr '/:' '__').json"
  [[ -f "${compact_path}" ]] || return 1
  updated_at="$(jq -r '.updated_at // empty' "${compact_path}")"
  tmux_session="$(jq -r '.tmux_session // empty' "${compact_path}")"
  workspace_receipt_path="$(jq -r '.workspace_receipt_path // empty' "${compact_path}")"
  run_is_stale "${updated_at}" "${tmux_session}" "${workspace_receipt_path}" && return 1
  printf '%s\n' "${run_id}"
}

compact_dir() {
  printf '%s\n' "${KERNEL_COMPACT_DIR:-$(bash "${STATE_PATH_SCRIPT}" compact-dir 2>/dev/null || true)}"
}

tmux_session_exists() {
  local session_name="${1:-}"
  [[ -n "${session_name}" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  tmux has-session -t "=${session_name}" 2>/dev/null
}

timestamp_to_epoch() {
  local ts="${1:-}"
  [[ -n "${ts}" ]] || return 1
  python3 - "${ts}" <<'PY'
import datetime, sys
try:
    dt = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")
except Exception:
    raise SystemExit(1)
print(int(dt.replace(tzinfo=datetime.timezone.utc).timestamp()))
PY
}

stale_threshold_seconds() {
  printf '%s\n' "$((STALE_HOURS * 3600))"
}

run_is_stale() {
  local updated_at="${1:-}" session_name="${2:-}" workspace_receipt_path="${3:-}"
  local updated_epoch now threshold
  updated_epoch="$(timestamp_to_epoch "${updated_at}" 2>/dev/null || true)"
  [[ -n "${updated_epoch}" ]] || return 0
  now="$(date -u '+%s')"
  threshold="$(stale_threshold_seconds)"
  if (( now - updated_epoch > threshold )); then
    return 0
  fi
  # A receipt alone is not enough to treat a 4-pane run as resumable; the tmux session must still exist.
  tmux_session_exists "${session_name}" || return 0
  if [[ -n "${workspace_receipt_path}" && -f "${workspace_receipt_path}" ]]; then
    return 1
  fi
  return 1
}

latest_active_run_id() {
  local dir file run_id tmux_session updated_at workspace_receipt_path newest_ts="" newest_run=""
  dir="$(compact_dir)"
  [[ -n "${dir}" && -d "${dir}" ]] || return 1
  for file in "${dir}"/*.json; do
    [[ -f "${file}" ]] || continue
    run_id="$(jq -r '.run_id // ""' "${file}")"
    tmux_session="$(jq -r '.tmux_session // ""' "${file}")"
    updated_at="$(jq -r '.updated_at // ""' "${file}")"
    workspace_receipt_path="$(jq -r '.workspace_receipt_path // ""' "${file}")"
    [[ -n "${run_id}" && -n "${updated_at}" ]] || continue
    run_is_stale "${updated_at}" "${tmux_session}" "${workspace_receipt_path}" && continue
    if [[ -z "${newest_ts}" || "${updated_at}" > "${newest_ts}" ]]; then
      newest_ts="${updated_at}"
      newest_run="${run_id}"
    fi
  done
  [[ -n "${newest_run}" ]] || return 1
  printf '%s\n' "${newest_run}"
}

exec_prompt_launch() {
  exec "${PROMPT_LAUNCH_BIN}" kernel "$@"
}

exec_4pane_launch() {
  exec bash "${FOUR_PANE_LAUNCH_SCRIPT}" "$@"
}

legacy_purpose_arg() {
  [[ $# -gt 0 ]] || return 1
  [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]
}

derive_purpose_from_text() {
  local text="${1:-}"
  local derived=""
  derived="$(
    TEXT="${text}" python3 - <<'PY'
import os, re

text = os.environ.get("TEXT", "")
tokens = re.findall(r"[A-Za-z0-9]+", text.lower())
tokens = [t for t in tokens if t]
if tokens:
    print("-".join(tokens[:2])[:48])
else:
    print("task")
PY
  )"
  [[ -n "${derived}" ]] || derived="task"
  printf '%s\n' "${derived}"
}

exec_4pane_from_natural_language() {
  local full_text purpose
  full_text="$*"
  purpose="$(derive_purpose_from_text "${full_text}")"
  exec_4pane_launch --purpose "${purpose}" "${full_text}"
}

main() {
  [[ -x "${PROMPT_LAUNCH_BIN}" ]] || {
    echo "prompt launcher not found: ${PROMPT_LAUNCH_BIN}" >&2
    exit 1
  }

  if ! in_repo_context || ! auto_4pane_enabled || inside_managed_tmux || needs_prompt_passthrough "$@"; then
    exec_prompt_launch "$@"
  fi

  if [[ $# -eq 0 ]]; then
    local run_id
    run_id="$(active_4pane_run_id || true)"
    [[ -n "${run_id}" ]] || run_id="$(latest_active_run_id || true)"
    if [[ -n "${run_id}" ]]; then
      exec_4pane_launch --run "${run_id}"
    fi
    exec_4pane_launch --purpose "${KERNEL_4PANE_DEFAULT_PURPOSE:-interactive}"
  fi

  if ! legacy_purpose_arg "$@"; then
    exec_4pane_from_natural_language "$@"
  fi

  local purpose="$1"
  shift || true
  exec_4pane_launch --purpose "${purpose}" "$@"
}

main "$@"
