#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HEALTH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-health.sh"
INTERVAL_SEC="${KERNEL_RUNTIME_LOOP_INTERVAL_SEC:-300}"
RUN_ONCE="${KERNEL_RUNTIME_LOOP_ONCE:-false}"

usage() {
  cat <<'EOF'
Usage:
  kernel-runtime-loop.sh [run_id]
EOF
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

while true; do
  set +e
  KERNEL_RUN_ID="${RUN_ID}" bash "${HEALTH_SCRIPT}" status
  rc=$?
  set -e
  if [[ "${RUN_ONCE}" == "true" ]]; then
    exit "${rc}"
  fi
  sleep "${INTERVAL_SEC}"
done
