#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GLM_STATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
GLM_BIN="${KERNEL_GLM_BIN:-glm}"

default_run_id() {
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  printf 'unknown-run\n'
}

RUN_ID="$(default_run_id)"
export KERNEL_RUN_ID="${RUN_ID}"

usage() {
  cat <<'EOF'
Usage:
  kernel-glm-exec.sh [args...]
EOF
}

mark_fail() {
  local note="$1"
  KERNEL_RUN_ID="${RUN_ID}" bash "${GLM_STATE_SCRIPT}" fail "${note}" >/dev/null
  KERNEL_RUN_ID="${RUN_ID}" bash "${LEDGER_SCRIPT}" record-provider glm failure "${note}" >/dev/null
}

mark_recover() {
  local note="$1"
  KERNEL_RUN_ID="${RUN_ID}" bash "${GLM_STATE_SCRIPT}" recover "${note}" >/dev/null
  KERNEL_RUN_ID="${RUN_ID}" bash "${LEDGER_SCRIPT}" record-provider glm success "${note}" >/dev/null
}

if [[ "${1:-}" == "help" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v "${GLM_BIN}" >/dev/null 2>&1; then
  mark_fail "glm-command-missing"
  echo "glm command missing: ${GLM_BIN}" >&2
  exit 127
fi

set +e
"${GLM_BIN}" "$@"
rc=$?
set -e

if [[ "${rc}" -eq 0 ]]; then
  mark_recover "glm-command-success"
else
  mark_fail "glm-command-exit-${rc}"
fi

exit "${rc}"
