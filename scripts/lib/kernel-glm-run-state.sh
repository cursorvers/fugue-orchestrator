#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
STATE_FILE="${KERNEL_GLM_RUN_STATE_FILE:-$(bash "${STATE_PATH_SCRIPT}" glm-run-state-file)}"
GLM_FAILURE_THRESHOLD="${KERNEL_GLM_FAILURE_THRESHOLD:-2}"
LOCK_DIR="${KERNEL_GLM_RUN_STATE_LOCK_DIR:-${STATE_FILE}.lock}"
LOCK_OWNER_FILE="${LOCK_DIR}/owner.pid"
LOCK_HELD=0
source "${SCRIPT_DIR}/kernel-lock.sh"

repo_slug() {
  if [[ -n "${KERNEL_REPO_SLUG:-}" ]]; then
    printf '%s\n' "${KERNEL_REPO_SLUG}"
    return 0
  fi
  printf 'kernel-workspace\n'
}

default_run_id() {
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

RUN_ID="$(default_run_id)"
export KERNEL_RUN_ID="${RUN_ID}"

usage() {
  cat <<'EOF'
Usage:
  kernel-glm-run-state.sh status
  kernel-glm-run-state.sh fail [note]
  kernel-glm-run-state.sh recover [note]
  kernel-glm-run-state.sh reset [note]
EOF
}

trap cleanup_lock EXIT INT TERM

ensure_state() {
  mkdir -p "$(dirname "${STATE_FILE}")"
  if [[ ! -f "${STATE_FILE}" ]]; then
    printf '{\n  "version": 1,\n  "runs": {}\n}\n' >"${STATE_FILE}"
  fi
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

current_mode() {
  jq -r --arg run_id "${RUN_ID}" '.runs[$run_id].mode // "healthy"' "${STATE_FILE}"
}

cmd_status() {
  ensure_state
  local mode failures recovered
  mode="$(jq -r --arg run_id "${RUN_ID}" '.runs[$run_id].mode // "healthy"' "${STATE_FILE}")"
  failures="$(jq -r --arg run_id "${RUN_ID}" '.runs[$run_id].glm_failures // 0' "${STATE_FILE}")"
  recovered="$(jq -r --arg run_id "${RUN_ID}" '.runs[$run_id].glm_recovered // false' "${STATE_FILE}")"
  printf 'glm run state:\n'
  printf '  - run id: %s\n' "${RUN_ID}"
  printf '  - mode: %s\n' "${mode}"
  printf '  - failures: %s\n' "${failures}"
  printf '  - threshold: %s\n' "${GLM_FAILURE_THRESHOLD}"
  printf '  - recovered: %s\n' "${recovered}"
}

cmd_fail() {
  ensure_state
  local note="${1:-glm-failure}"
  local tmp_file
  acquire_lock "glm state"
  tmp_file="${STATE_FILE}.tmp.$$.$RANDOM"
  jq \
    --arg run_id "${RUN_ID}" \
    --arg note "${note}" \
    --arg ts "$(utc_timestamp)" \
    --argjson threshold "${GLM_FAILURE_THRESHOLD}" \
    '
      .runs[$run_id] = ((.runs[$run_id] // {
        glm_failures: 0,
        mode: "healthy",
        glm_recovered: false
      }) | .glm_failures += 1 | .last_failure_note = $note | .last_failure_at = $ts)
      | .runs[$run_id].mode =
          (if (.runs[$run_id].glm_failures >= $threshold) then "degraded-allowed" else "healthy" end)
    ' "${STATE_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${STATE_FILE}"
  release_lock
  cmd_status
}

cmd_recover() {
  ensure_state
  local note="${1:-glm-recovered}"
  local mode
  local tmp_file
  mode="$(current_mode)"
  acquire_lock "glm state"
  tmp_file="${STATE_FILE}.tmp.$$.$RANDOM"
  jq \
    --arg run_id "${RUN_ID}" \
    --arg note "${note}" \
    --arg ts "$(utc_timestamp)" \
    --arg mode "${mode}" \
    '
      .runs[$run_id] = ((.runs[$run_id] // {
        glm_failures: 0,
        mode: "healthy",
        glm_recovered: false
      })
      | .glm_recovered = true
      | .last_recovery_note = $note
      | .last_recovery_at = $ts
      | .mode = $mode)
    ' "${STATE_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${STATE_FILE}"
  release_lock
  cmd_status
}

cmd_reset() {
  ensure_state
  local note="${1:-glm-reset}"
  local tmp_file
  acquire_lock "glm state"
  tmp_file="${STATE_FILE}.tmp.$$.$RANDOM"
  jq \
    --arg run_id "${RUN_ID}" \
    --arg note "${note}" \
    --arg ts "$(utc_timestamp)" \
    '
      .runs[$run_id] = {
        glm_failures: 0,
        mode: "healthy",
        glm_recovered: false,
        last_reset_note: $note,
        last_reset_at: $ts
      }
    ' "${STATE_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${STATE_FILE}"
  release_lock
  cmd_status
}

cmd="${1:-status}"
case "${cmd}" in
  status)
    shift || true
    cmd_status "$@"
    ;;
  fail)
    shift || true
    cmd_fail "$@"
    ;;
  recover)
    shift || true
    cmd_recover "$@"
    ;;
  reset)
    shift || true
    cmd_reset "$@"
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
