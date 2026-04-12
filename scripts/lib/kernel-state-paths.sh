#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${KERNEL_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
source "${SCRIPT_DIR}/workspace-root-policy.sh"

usage() {
  cat <<'EOF'
Usage:
  kernel-state-paths.sh state-root
  kernel-state-paths.sh bootstrap-receipt-dir
  kernel-state-paths.sh runtime-ledger-file
  kernel-state-paths.sh glm-run-state-file
  kernel-state-paths.sh optional-lane-ledger-file
  kernel-state-paths.sh compact-dir
EOF
}

ensure_writable_dir() {
  local dir="${1:?dir is required}"
  (umask 077 && mkdir -p "${dir}") >/dev/null 2>&1 || return 1
  [[ -d "${dir}" && -w "${dir}" ]]
}

fallback_state_root() {
  local candidate
  if [[ -n "${KERNEL_FALLBACK_STATE_ROOT:-}" ]]; then
    printf '%s\n' "${KERNEL_FALLBACK_STATE_ROOT}"
    return 0
  fi
  candidate="$(fugue_resolve_workspace_dir "${ROOT_DIR}" "${ROOT_DIR}/.fugue/kernel-state" "kernel state root")"
  printf '%s\n' "${candidate}"
}

tmp_state_root() {
  printf '%s\n' "${TMPDIR:-/tmp}/fugue-kernel-state"
}

state_root() {
  local preferred_root resolved_root

  if [[ -n "${KERNEL_STATE_ROOT:-}" ]]; then
    printf '%s\n' "${KERNEL_STATE_ROOT}"
    return 0
  fi

  preferred_root="${HOME}/.config/kernel"
  if ensure_writable_dir "${preferred_root}"; then
    printf '%s\n' "${preferred_root}"
    return 0
  fi

  resolved_root="$(fallback_state_root)"
  if ensure_writable_dir "${resolved_root}"; then
    printf '%s\n' "${resolved_root}"
    return 0
  fi

  resolved_root="$(tmp_state_root)"
  ensure_writable_dir "${resolved_root}" || {
    echo "unable to resolve writable kernel state root" >&2
    exit 1
  }
  printf '%s\n' "${resolved_root}"
}

cmd="${1:-state-root}"
case "${cmd}" in
  state-root)
    state_root
    ;;
  bootstrap-receipt-dir)
    printf '%s/bootstrap-receipts\n' "$(state_root)"
    ;;
  runtime-ledger-file)
    printf '%s/runtime-ledger.json\n' "$(state_root)"
    ;;
  glm-run-state-file)
    printf '%s/glm-run-state.json\n' "$(state_root)"
    ;;
  optional-lane-ledger-file)
    printf '%s/optional-lane-usage.json\n' "$(state_root)"
    ;;
  compact-dir)
    printf '%s/compact\n' "$(state_root)"
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
