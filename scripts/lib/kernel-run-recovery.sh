#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
HEALTH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-health.sh"
THREAD_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-codex-thread.sh"
RUNTIME_LAUNCH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-launch.sh"

usage() {
  cat <<'EOF'
Usage:
  kernel-run-recovery.sh status [run_id]
  kernel-run-recovery.sh recover [run_id]
EOF
}

default_run_id() {
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  printf 'unknown-run\n'
}

RUN_ID="$(default_run_id)"

compact_path_for() {
  KERNEL_RUN_ID="${1:-${RUN_ID}}" bash "${COMPACT_SCRIPT}" path
}

compact_json() {
  local run_id="${1:-${RUN_ID}}"
  local path
  path="$(compact_path_for "${run_id}")"
  [[ -f "${path}" ]] || return 1
  jq -c '.' "${path}"
}

tmux_session_exists() {
  local session_name="${1:-}"
  [[ -n "${session_name}" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  tmux has-session -t "=${session_name}" 2>/dev/null
}

tmux_session_option() {
  local session_name="${1:-}"
  local option_name="${2:-}"
  [[ -n "${session_name}" && -n "${option_name}" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  tmux show-options -t "${session_name}" -v "${option_name}" 2>/dev/null || true
}

tmux_window_names() {
  local session_name="${1:-}"
  [[ -n "${session_name}" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  tmux list-windows -t "=${session_name}" -F '#W' 2>/dev/null || return 1
}

tmux_window_exists() {
  local session_name="${1:-}"
  local window_name="${2:-}"
  [[ -n "${session_name}" && -n "${window_name}" ]] || return 1
  tmux_window_names "${session_name}" | grep -Fxq "${window_name}"
}

ensure_session_windows() {
  local session_name="${1:-}"
  [[ -n "${session_name}" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  tmux has-session -t "=${session_name}" 2>/dev/null || return 1

  if ! tmux_window_exists "${session_name}" "main"; then
    tmux rename-window -t "=${session_name}:0" main >/dev/null 2>&1 || true
  fi
  tmux_window_exists "${session_name}" "logs" || tmux new-window -t "=${session_name}" -n logs >/dev/null 2>&1 || true
  tmux_window_exists "${session_name}" "review" || tmux new-window -t "=${session_name}" -n review >/dev/null 2>&1 || true
  tmux_window_exists "${session_name}" "ops" || tmux new-window -t "=${session_name}" -n ops >/dev/null 2>&1 || true
}

phase_entry_for() {
  local phase="${1:-unknown}"
  case "${phase}" in
    requirements|plan|simulate|critique|replan|implement|implementation|verify|verification)
      printf '%s\n' "${phase}"
      ;;
    *)
      printf 'plan\n'
      ;;
  esac
}

resume_strategy_for() {
  local run_id="${1:-${RUN_ID}}"
  if KERNEL_RUN_ID="${run_id}" KERNEL_RUNTIME_HEALTH_MUTATE=false bash "${HEALTH_SCRIPT}" status >/dev/null 2>&1; then
    printf 'continue-phase\n'
  else
    printf 'phase-entry\n'
  fi
}

ensure_session() {
  local run_id="${1:-${RUN_ID}}"
  local session_name="${2:-}"
  local expected_fingerprint="${3:-}"
  local actual_run_id actual_fingerprint
  [[ -n "${session_name}" ]] || {
    echo "tmux_session is required" >&2
    exit 2
  }
  if tmux_session_exists "${session_name}"; then
    ensure_session_windows "${session_name}"
    actual_run_id="$(tmux_session_option "${session_name}" "@kernel_run_id")"
    actual_fingerprint="$(tmux_session_option "${session_name}" "@kernel_session_fingerprint")"
    if [[ -n "${actual_run_id}" && "${actual_run_id}" != "${run_id}" ]]; then
      echo "existing tmux session ${session_name} belongs to run ${actual_run_id}, not ${run_id}" >&2
      exit 2
    fi
    if [[ -n "${expected_fingerprint}" && -n "${actual_fingerprint}" && "${actual_fingerprint}" != "${expected_fingerprint}" ]]; then
      echo "existing tmux session ${session_name} fingerprint mismatch for run ${run_id}" >&2
      exit 2
    fi
    if [[ -z "${actual_run_id}" || -z "${actual_fingerprint}" ]]; then
      printf 'needs-init\n'
      return 0
    fi
    printf 'existing\n'
    return 0
  fi

  tmux new-session -d -s "${session_name}" -n main
  tmux new-window -t "=${session_name}" -n logs
  tmux new-window -t "=${session_name}" -n review
  tmux new-window -t "=${session_name}" -n ops
  printf 'created\n'
}

launch_runtime_thread() {
  local run_id="${1:-${RUN_ID}}"
  local session_name="${2:-}"
  local runtime="${3:-kernel}"
  local project="${4:-kernel-workspace}"
  local purpose="${5:-unspecified}"
  local launch_command
  [[ "${KERNEL_RECOVERY_LAUNCH_CODEX_THREAD:-true}" == "true" ]] || return 0
  [[ -n "${session_name}" ]] || return 0
  command -v tmux >/dev/null 2>&1 || return 0
  [[ -f "${RUNTIME_LAUNCH_SCRIPT}" ]] || return 0
  launch_command="$(bash "${RUNTIME_LAUNCH_SCRIPT}" command resume "${runtime}" "${run_id}" "${project}" "${purpose}" "${session_name}")"
  if [[ "${runtime}" == "fugue" ]]; then
    local safe_run_id="${run_id//"'"/"'\\''"}"
    tmux send-keys -t "=${session_name}:main" "printf '%s\n' 'Resume FUGUE orchestration for Kernel run ${safe_run_id}.'" C-m
  fi
  tmux send-keys -t "=${session_name}:main" "${launch_command}" C-m
}

refresh_compact_artifact() {
  local run_id="${1:-${RUN_ID}}"
  local json
  json="$(compact_json "${run_id}")" || return 1

  local next_actions decisions summary runtime project purpose phase mode tmux_session owner blocking_reason
  {
    IFS= read -r next_actions
    IFS= read -r decisions
    IFS= read -r runtime
    IFS= read -r project
    IFS= read -r purpose
    IFS= read -r phase
    IFS= read -r mode
    IFS= read -r tmux_session
    IFS= read -r owner
    IFS= read -r blocking_reason
  } < <(jq -r '
      ((.next_action // []) | if type == "array" then join("|") elif type == "string" then . else "" end),
      ((.decisions // []) | join("|")),
      (.runtime // "kernel"),
      (.project // ""),
      (.purpose // ""),
      (.current_phase // "unknown"),
      (.mode // "unknown"),
      (.tmux_session // ""),
      (.owner // "local-operator"),
      (.blocking_reason // "")
    ' <<<"${json}"
  )
  summary="$(jq -r '(.summary // []) | join("\n")' <<<"${json}")"

  KERNEL_RUN_ID="${run_id}" \
  KERNEL_PROJECT="${project}" \
  KERNEL_PURPOSE="${purpose}" \
  KERNEL_PHASE="${phase}" \
  KERNEL_MODE="${mode}" \
  KERNEL_RUNTIME="${runtime}" \
  KERNEL_TMUX_SESSION="${tmux_session}" \
  KERNEL_OWNER="${owner}" \
  KERNEL_BLOCKING_REASON="${blocking_reason}" \
  KERNEL_NEXT_ACTIONS="${next_actions}" \
  KERNEL_DECISIONS="${decisions}" \
  KERNEL_SUMMARY="${summary}" \
  KERNEL_COMPACT_PRESERVE_SUMMARY=true \
  KERNEL_COMPACT_PRESERVE_LAST_EVENT=true \
  KERNEL_COMPACT_PRESERVE_PHASE_ARTIFACTS=true \
    bash "${COMPACT_SCRIPT}" update recovered_session >/dev/null
}

cmd_status() {
  local run_id="${1:-${RUN_ID}}"
  local json strategy
  json="$(compact_json "${run_id}")" || {
    echo "compact artifact missing for run: ${run_id}" >&2
    exit 1
  }

  strategy="$(resume_strategy_for "${run_id}")"

  local current_phase tmux_session codex_thread_title mode runtime session_fingerprint next_action active_models updated_at phase_artifacts phase_artifact_focus
  {
    IFS= read -r current_phase
    IFS= read -r tmux_session
    IFS= read -r codex_thread_title
    IFS= read -r mode
    IFS= read -r runtime
    IFS= read -r session_fingerprint
    IFS= read -r next_action
    IFS= read -r active_models
    IFS= read -r updated_at
    IFS= read -r phase_artifacts
    IFS= read -r phase_artifact_focus
  } < <(jq -r '
      (.current_phase // "unknown"),
      (.tmux_session // ""),
      (.codex_thread_title // (.project + ":" + .purpose)),
      (.mode // "unknown"),
      (.runtime // "kernel"),
      (.session_fingerprint // ""),
      ((.next_action // "") | if type == "array" then (.[0] // "") elif type == "string" then . else "" end),
      ((.active_models // []) | join(",")),
      (.updated_at // ""),
      (if ((.phase_artifacts // {}) | length) == 0 then "none" else ((.phase_artifacts // {}) | to_entries | map("\(.key)=\(.value)") | join(" | ")) end),
      (
        (.phase_artifacts // {}) as $artifacts
        | (if .current_phase == "plan" then "plan_report_path"
           elif .current_phase == "critique" then "critic_report_path"
           elif (.current_phase == "implement" or .current_phase == "implementation") then "implementation_report_path"
           else "none"
           end) as $focus_key
        | if $focus_key == "none" then "none" else ($focus_key + "=" + ($artifacts[$focus_key] // "none")) end
      )
    ' <<<"${json}"
  )

  local resume_phase="${current_phase}"
  if [[ "${strategy}" == "phase-entry" ]]; then
    resume_phase="$(phase_entry_for "${current_phase}")"
  fi

  printf 'kernel run recovery:\n'
  printf '  - run id: %s\n' "${run_id}"
  printf '  - tmux session: %s\n' "${tmux_session}"
  printf '  - codex thread: %s\n' "${codex_thread_title}"
  printf '  - strategy: %s\n' "${strategy}"
  printf '  - current phase: %s\n' "${current_phase}"
  printf '  - resume phase: %s\n' "${resume_phase}"
  printf '  - mode: %s\n' "${mode}"
  printf '  - runtime: %s\n' "${runtime}"
  printf '  - session fingerprint: %s\n' "${session_fingerprint}"
  printf '  - next action: %s\n' "${next_action}"
  printf '  - active models: %s\n' "${active_models}"
  printf '  - phase artifacts: %s\n' "${phase_artifacts}"
  printf '  - phase artifact focus: %s\n' "${phase_artifact_focus}"
  printf '  - updated at: %s\n' "${updated_at}"
}

cmd_recover() {
  local run_id="${1:-${RUN_ID}}"
  local json tmux_session session_state session_fingerprint runtime project purpose
  json="$(compact_json "${run_id}")" || {
    echo "compact artifact missing for run: ${run_id}" >&2
    exit 1
  }
  {
    IFS= read -r tmux_session
    IFS= read -r session_fingerprint
    IFS= read -r runtime
    IFS= read -r project
    IFS= read -r purpose
  } < <(jq -r '
      (.tmux_session // ""),
      (.session_fingerprint // ""),
      (.runtime // "kernel"),
      (.project // ""),
      (.purpose // "")
    ' <<<"${json}"
  )
  session_state="$(ensure_session "${run_id}" "${tmux_session}" "${session_fingerprint}")"
  if [[ "${session_state}" == "created" || "${session_state}" == "needs-init" ]]; then
    launch_runtime_thread "${run_id}" "${tmux_session}" "${runtime}" "${project}" "${purpose}"
  fi
  refresh_compact_artifact "${run_id}"
  cmd_status "${run_id}"
}

cmd="${1:-status}"
case "${cmd}" in
  status)
    shift || true
    cmd_status "$@"
    ;;
  recover)
    shift || true
    cmd_recover "$@"
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
