#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BOOTSTRAP_SCRIPT="${KERNEL_COMPLETION_AGENT_BOOTSTRAP_SCRIPT:-${ROOT_DIR}/scripts/local/bootstrap-kernel-task-completion-backup-agent.sh}"
AUTO_BOOTSTRAP="${KERNEL_AUTO_COMPLETION_AGENT:-false}"
ORCH_DRY_RUN_VALUE="${ORCH_DRY_RUN:-false}"

usage() {
  cat <<'EOF'
Usage:
  kernel-completion-agent.sh ensure
EOF
}

should_skip() {
  [[ "${AUTO_BOOTSTRAP}" == "false" ]] && return 0
  [[ "${ORCH_DRY_RUN_VALUE}" == "1" || "${ORCH_DRY_RUN_VALUE}" == "true" ]] && return 0
  [[ ! -f "${BOOTSTRAP_SCRIPT}" ]] && return 0
  return 1
}

cmd_ensure() {
  should_skip && return 0
  bash "${BOOTSTRAP_SCRIPT}" >/dev/null 2>&1 || true
}

cmd="${1:-ensure}"
case "${cmd}" in
  ensure)
    shift || true
    cmd_ensure "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    usage >&2
    exit 2
    ;;
esac
