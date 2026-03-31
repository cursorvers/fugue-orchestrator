#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SURFACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-4pane-surface.sh"
INTERVAL_SEC="${KERNEL_4PANE_REFRESH_SEC:-3}"

usage() {
  cat <<'EOF'
Usage:
  kernel-ship.sh status [run_id]
  kernel-ship.sh watch [run_id]
  kernel-ship.sh execute [run_id]
EOF
}

branch_name() {
  git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'unknown\n'
}

dirty_count() {
  git -C "${ROOT_DIR}" status --short 2>/dev/null | wc -l | tr -d ' '
}

can_ship() {
  local branch dirty
  branch="$(branch_name)"
  dirty="$(dirty_count)"
  [[ "${branch}" != "main" && "${branch}" != "master" && "${dirty}" != "0" ]]
}

render_status() {
  local run_id="${1:-${KERNEL_RUN_ID:-unknown-run}}"
  printf '\033[H\033[2J'
  KERNEL_RUN_ID="${run_id}" bash "${SURFACE_SCRIPT}" render-ship
}

execute_ship() {
  local run_id="${1:-${KERNEL_RUN_ID:-unknown-run}}"
  local branch
  branch="$(branch_name)"
  can_ship || {
    echo "ship is blocked for branch=${branch} or there are no local changes" >&2
    exit 1
  }
  if [[ "${KERNEL_4PANE_SHIP_ENABLED:-false}" != "true" ]]; then
    echo "ship is monitor-only; set KERNEL_4PANE_SHIP_ENABLED=true to allow execution" >&2
    exit 1
  fi
  if [[ "${KERNEL_4PANE_SHIP_DRY_RUN:-true}" == "true" ]]; then
    printf 'dry-run ship plan for %s\n' "${run_id}"
    printf '  git add -A\n'
    printf '  git commit -m %q\n' "${KERNEL_4PANE_SHIP_COMMIT_MESSAGE:-kernel 4-pane checkpoint}"
    printf '  git push -u origin HEAD\n'
    printf '  gh pr create --fill\n'
    exit 0
  fi
  echo "non-dry-run ship execution is intentionally explicit and not invoked automatically" >&2
  exit 1
}

cmd="${1:-status}"
shift || true
case "${cmd}" in
  status)
    render_status "${1:-${KERNEL_RUN_ID:-unknown-run}}"
    ;;
  watch)
    run_id="${1:-${KERNEL_RUN_ID:-unknown-run}}"
    while true; do
      render_status "${run_id}"
      sleep "${INTERVAL_SEC}"
    done
    ;;
  execute)
    execute_ship "${1:-${KERNEL_RUN_ID:-unknown-run}}"
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
