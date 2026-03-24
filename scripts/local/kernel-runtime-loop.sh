#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HEALTH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-health.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"
INTERVAL_SEC="${KERNEL_RUNTIME_LOOP_INTERVAL_SEC:-300}"
RUN_ONCE="${KERNEL_RUNTIME_LOOP_ONCE:-false}"
STOP_FILE="${KERNEL_RUNTIME_LOOP_STOP_FILE:-}"

usage() {
  cat <<'EOF'
Usage:
  kernel-runtime-loop.sh [run_id]
EOF
}

health_field() {
  local label="${1:?label is required}"
  sed -n "s/^  - ${label}: //p" | head -n 1
}

record_scheduler_state() {
  local run_id="${1:?run_id is required}"
  local scheduler_state="${2:?scheduler_state is required}"
  local reason="${3:-runtime-loop}"
  local workspace_receipt_path="${4:-}"
  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" scheduler-state "${scheduler_state}" "${reason}" "${workspace_receipt_path}" >/dev/null
}

map_health_to_scheduler_state() {
  local health_state="${1:-invalid}"
  case "${health_state}" in
    healthy)
      printf 'running\n'
      ;;
    degraded-allowed)
      printf 'continuity_degraded\n'
      ;;
    *)
      printf 'retry_queued\n'
      ;;
  esac
}

map_health_to_scheduler_reason() {
  local health_state="${1:-invalid}"
  local health_reason="${2:-runtime-loop}"
  case "${health_state}" in
    healthy)
      printf 'live-running\n'
      ;;
    degraded-allowed)
      printf 'live-continuity-degraded\n'
      ;;
    *)
      printf '%s\n' "${health_reason}"
      ;;
  esac
}

if [[ "${1:-}" == "help" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

RUN_ID="${1:-${KERNEL_RUN_ID:-unknown-run}}"
if [[ -z "${RUN_ID}" || "${RUN_ID}" == "unknown-run" ]]; then
  echo "kernel-runtime-loop requires an explicit run id or KERNEL_RUN_ID" >&2
  exit 2
fi

WORKSPACE_RECEIPT_PATH="$(KERNEL_RUN_ID="${RUN_ID}" bash "${WORKSPACE_SCRIPT}" write)"
WORKSPACE_DIR="$(KERNEL_RUN_ID="${RUN_ID}" bash "${WORKSPACE_SCRIPT}" path)"
if [[ -z "${STOP_FILE}" ]]; then
  STOP_FILE="${WORKSPACE_DIR}/stop"
fi

record_scheduler_state "${RUN_ID}" claimed "runtime-loop-start" "${WORKSPACE_RECEIPT_PATH}"
KERNEL_RUN_ID="${RUN_ID}" bash "${LEDGER_SCRIPT}" record-event runtime-loop start "workspace=${WORKSPACE_DIR}" >/dev/null

while true; do
  if [[ -f "${STOP_FILE}" ]]; then
    record_scheduler_state "${RUN_ID}" terminal "stop-file-detected" "${WORKSPACE_RECEIPT_PATH}"
    KERNEL_RUN_ID="${RUN_ID}" bash "${LEDGER_SCRIPT}" record-event runtime-loop stop "stop-file=${STOP_FILE}" >/dev/null
    exit 0
  fi

  set +e
  health_output="$(KERNEL_RUN_ID="${RUN_ID}" bash "${HEALTH_SCRIPT}" status 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "${health_output}"

  health_state="$(printf '%s\n' "${health_output}" | health_field state)"
  health_reason="$(printf '%s\n' "${health_output}" | health_field reason)"
  scheduler_state="$(map_health_to_scheduler_state "${health_state}")"
  scheduler_reason="$(map_health_to_scheduler_reason "${health_state}" "${health_reason:-runtime-loop}")"
  record_scheduler_state "${RUN_ID}" "${scheduler_state}" "${scheduler_reason}" "${WORKSPACE_RECEIPT_PATH}"
  KERNEL_RUN_ID="${RUN_ID}" bash "${LEDGER_SCRIPT}" record-event runtime-loop tick "health=${health_state:-unknown}; reason=${health_reason:-unknown}" >/dev/null

  if [[ "${RUN_ONCE}" == "true" ]]; then
    exit "${rc}"
  fi
  sleep "${INTERVAL_SEC}"
done
