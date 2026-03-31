#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
SESSION_NAME_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-session-name.sh"
SURFACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-4pane-surface.sh"
TMUX_BIN="${TMUX_BIN:-tmux}"
MAIN_PANE_WIDTH="${KERNEL_4PANE_MAIN_PANE_WIDTH:-52}"
CODEX_BIN="${CODEX_BIN:-}"

usage() {
  cat <<'EOF'
Usage:
  kernel-4pane-launch.sh --purpose <purpose> [focus...]
  kernel-4pane-launch.sh --run <run_id>
EOF
}

default_run_id() {
  local purpose="${1:-launch}"
  local project host ts
  project="$(basename "${ROOT_DIR}")"
  purpose="$(printf '%s' "${purpose}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown-host')"
  ts="$(date '+%Y%m%dT%H%M%S')"
  printf 'launch:%s:%s:%s:%s:%s\n' "${host}" "${project}" "${purpose:-launch}" "${ts}" "$$"
}

tmux_has_session() {
  "${TMUX_BIN}" has-session -t "=${1:?session}" 2>/dev/null
}

session_slug() {
  local project="${1:-}" purpose="${2:-}"
  KERNEL_PROJECT="${project}" KERNEL_PURPOSE="${purpose}" bash "${SESSION_NAME_SCRIPT}" slug
}

choose_session_name() {
  local project="${1:-}" purpose="${2:-}" candidate suffix
  candidate="$(session_slug "${project}" "${purpose}")"
  if ! tmux_has_session "${candidate}"; then
    printf '%s\n' "${candidate}"
    return 0
  fi
  suffix="$(date '+%H%M%S')"
  KERNEL_PROJECT="${project}" KERNEL_PURPOSE="${purpose}" KERNEL_SESSION_SHORT_ID="${suffix}" bash "${SESSION_NAME_SCRIPT}" slug
}

shell_join_quoted() {
  local arg out=""
  for arg in "$@"; do
    [[ -n "${out}" ]] && out+=" "
    out+="$(printf '%q' "${arg}")"
  done
  printf '%s' "${out}"
}

resolve_codex_bin() {
  local preferred="${CODEX_BIN:-}"
  local candidate

  if [[ -n "${preferred}" ]]; then
    candidate="$(type -P "${preferred}" 2>/dev/null || true)"
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
    if [[ -x "${preferred}" ]]; then
      printf '%s\n' "${preferred}"
      return 0
    fi
  fi

  candidate="$(type -P codex 2>/dev/null || true)"
  if [[ -n "${candidate}" && -x "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return 0
  fi

  for candidate in "$HOME/bin/codex" "$HOME/.local/bin/codex" "/usr/local/bin/codex" "/opt/homebrew/bin/codex"; do
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

left_command_for_operator() {
  local _run_id="${1:?run_id}" _purpose="${2:?purpose}" _session_name="${3:?session_name}"
  local codex_bin
  codex_bin="$(resolve_codex_bin)" || {
    echo "codex executable not found. Set CODEX_BIN." >&2
    exit 1
  }
  printf '%q -C %q\n' "${codex_bin}" "${ROOT_DIR}"
}

left_command_for_new() {
  left_command_for_operator "$@"
}

left_command_for_resume() {
  local run_id="${1:?run_id}" session_name="${2:?session_name}" purpose="${3:?purpose}"
  left_command_for_operator "${run_id}" "${purpose}" "${session_name}"
}

compact_json_for_run() {
  local run_id="${1:?run_id}"
  local compact_path
  compact_path="$(KERNEL_RUN_ID="${run_id}" bash "${COMPACT_SCRIPT}" path 2>/dev/null || true)"
  [[ -n "${compact_path}" && -f "${compact_path}" ]] || return 1
  jq -c '.' "${compact_path}"
}

resume_session_name_for_run() {
  local run_id="${1:?run_id}"
  local compact_json
  compact_json="$(compact_json_for_run "${run_id}" 2>/dev/null || true)"
  [[ -n "${compact_json}" ]] || return 1
  jq -r '.tmux_session // empty' <<<"${compact_json}"
}

write_active_file() {
  local run_id="${1:-}" session_name="${2:-}" purpose="${3:-}" launch_mode="${4:-}"
  local path tmp_file
  path="$(bash "${SURFACE_SCRIPT}" active-file)"
  mkdir -p "$(dirname "${path}")"
  tmp_file="$(umask 077 && mktemp "${path}.tmp.XXXXXXXXXX")"
  jq -n \
    --arg version "1" \
    --arg updated_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg run_id "${run_id}" \
    --arg tmux_session "${session_name}" \
    --arg purpose "${purpose}" \
    --arg launch_mode "${launch_mode}" \
    '{
      version: ($version | tonumber),
      updated_at: $updated_at,
      run_id: $run_id,
      tmux_session: $tmux_session,
      purpose: $purpose,
      launch_mode: $launch_mode
    }' >"${tmp_file}"
  mv "${tmp_file}" "${path}"
}

launch_session() {
  local run_id="${1:?run_id}" purpose="${2:?purpose}" left_command="${3:?left_command}" launch_mode="${4:?launch_mode}" requested_session_name="${5:-}"
  local project session_name existing_run_id left_pane right_top right_mid right_bottom
  project="${KERNEL_PROJECT:-$(basename "${ROOT_DIR}")}"
  if [[ -n "${requested_session_name}" ]]; then
    session_name="${requested_session_name}"
  else
    session_name="$(choose_session_name "${project}" "${purpose}")"
  fi

  if tmux_has_session "${session_name}"; then
    existing_run_id="$("${TMUX_BIN}" show-options -t "=${session_name}" -v @kernel_run_id 2>/dev/null || true)"
    if [[ -n "${existing_run_id}" && "${existing_run_id}" != "${run_id}" ]]; then
      printf 'existing tmux session %s belongs to run %s, not %s\n' "${session_name}" "${existing_run_id}" "${run_id}" >&2
      exit 1
    fi
    write_active_file "${run_id}" "${session_name}" "${purpose}" "${launch_mode}"
    KERNEL_RUN_ID="${run_id}" bash "${SURFACE_SCRIPT}" snapshot --write >/dev/null 2>&1 || true
    if [[ "${KERNEL_4PANE_NO_ATTACH:-false}" == "true" ]]; then
      printf 'Kernel ready: %s [%s]\n' "${session_name}" "${run_id}"
      return 0
    fi
    exec "${TMUX_BIN}" attach -t "=${session_name}"
  fi

  "${TMUX_BIN}" new-session -d -s "${session_name}" -n main -c "${ROOT_DIR}"
  left_pane="$("${TMUX_BIN}" display-message -p -t "=${session_name}:main" '#{pane_id}')"
  right_top="$("${TMUX_BIN}" split-window -h -P -F '#{pane_id}' -t "=${session_name}:main" -c "${ROOT_DIR}")"
  right_mid="$("${TMUX_BIN}" split-window -v -P -F '#{pane_id}' -t "${right_top}" -c "${ROOT_DIR}")"
  right_bottom="$("${TMUX_BIN}" split-window -v -P -F '#{pane_id}' -t "${right_mid}" -c "${ROOT_DIR}")"
  # Keep the main thread on the left and stack monitors on the right.
  "${TMUX_BIN}" select-layout -t "=${session_name}:main" main-vertical >/dev/null 2>&1 || true
  "${TMUX_BIN}" resize-pane -t "${left_pane}" -x "${MAIN_PANE_WIDTH}" >/dev/null 2>&1 || true
  "${TMUX_BIN}" set-option -q -t "${session_name}" @kernel_run_id "${run_id}" >/dev/null 2>&1 || true

  "${TMUX_BIN}" send-keys -t "${left_pane}" "${left_command}" C-m
  "${TMUX_BIN}" send-keys -t "${right_top}" "env KERNEL_RUN_ID=${run_id} bash ${ROOT_DIR}/scripts/local/kernel-lanes-monitor.sh" C-m
  "${TMUX_BIN}" send-keys -t "${right_mid}" "env KERNEL_RUN_ID=${run_id} bash ${ROOT_DIR}/scripts/local/kernel-health-monitor.sh" C-m
  "${TMUX_BIN}" send-keys -t "${right_bottom}" "env KERNEL_RUN_ID=${run_id} bash ${ROOT_DIR}/scripts/local/kernel-ship.sh watch" C-m

  write_active_file "${run_id}" "${session_name}" "${purpose}" "${launch_mode}"
  KERNEL_RUN_ID="${run_id}" bash "${SURFACE_SCRIPT}" snapshot --write >/dev/null 2>&1 || true

  if [[ "${KERNEL_4PANE_NO_ATTACH:-false}" == "true" ]]; then
    printf 'Kernel ready: %s [%s]\n' "${session_name}" "${run_id}"
    return 0
  fi
  exec "${TMUX_BIN}" attach -t "=${session_name}"
}

mode=""
purpose=""
run_id=""
focus=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --purpose)
      mode="new"
      purpose="${2:-}"
      [[ -n "${purpose}" ]] || { usage >&2; exit 2; }
      shift 2
      while [[ $# -gt 0 ]]; do
        focus+=("$1")
        shift
      done
      ;;
    --run)
      mode="resume"
      run_id="${2:-}"
      [[ -n "${run_id}" ]] || { usage >&2; exit 2; }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "${mode}" ]] || { usage >&2; exit 2; }
command -v "${TMUX_BIN}" >/dev/null 2>&1 || { echo "tmux is required" >&2; exit 1; }

  if [[ "${mode}" == "new" ]]; then
  run_id="${KERNEL_RUN_ID:-$(default_run_id "${purpose}")}"
  if ((${#focus[@]} > 0)); then
    session_name="$(choose_session_name "${KERNEL_PROJECT:-$(basename "${ROOT_DIR}")}" "${purpose}")"
    launch_session "${run_id}" "${purpose}" "$(left_command_for_new "${run_id}" "${purpose}" "${session_name}" "${focus[@]}")" "new" "${session_name}"
  else
    session_name="$(choose_session_name "${KERNEL_PROJECT:-$(basename "${ROOT_DIR}")}" "${purpose}")"
    launch_session "${run_id}" "${purpose}" "$(left_command_for_new "${run_id}" "${purpose}" "${session_name}")" "new" "${session_name}"
  fi
else
  compact_path="$(KERNEL_RUN_ID="${run_id}" bash "${COMPACT_SCRIPT}" path 2>/dev/null || true)"
  if [[ -n "${compact_path}" && -f "${compact_path}" ]]; then
    purpose="$(jq -r '.purpose // "resume"' "${compact_path}")"
  else
    purpose="resume"
  fi
  session_name="$(resume_session_name_for_run "${run_id}" 2>/dev/null || true)"
  if [[ -z "${session_name}" ]]; then
    session_name="$(choose_session_name "${KERNEL_PROJECT:-$(basename "${ROOT_DIR}")}" "${purpose}")"
  fi
  launch_session "${run_id}" "${purpose}" "$(left_command_for_resume "${run_id}" "${session_name}" "${purpose}")" "resume" "${session_name}"
fi
