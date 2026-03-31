#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SURFACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-4pane-surface.sh"
INTERVAL_SEC="${KERNEL_4PANE_REFRESH_SEC:-3}"

usage() {
  cat <<'EOF'
Usage:
  kernel-lanes-monitor.sh [--once] [run_id]
EOF
}

render_once() {
  local run_id="${1:-${KERNEL_RUN_ID:-unknown-run}}"
  KERNEL_RUN_ID="${run_id}" bash "${SURFACE_SCRIPT}" snapshot --write >/dev/null
  printf '\033[H\033[2J'
  KERNEL_RUN_ID="${run_id}" bash "${SURFACE_SCRIPT}" render-lanes
}

once=false
run_id="${KERNEL_RUN_ID:-unknown-run}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) once=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) run_id="$1"; shift ;;
  esac
done

if [[ "${once}" == "true" ]]; then
  render_once "${run_id}"
  exit 0
fi

while true; do
  render_once "${run_id}"
  sleep "${INTERVAL_SEC}"
done
