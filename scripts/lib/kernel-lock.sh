#!/usr/bin/env bash
# Shared lock infrastructure for kernel scripts.
# Source this file and call the functions with explicit parameters.
#
# Required variables before sourcing:
#   LOCK_DIR          - path to the lock directory
#   LOCK_OWNER_FILE   - path to the owner PID file (typically ${LOCK_DIR}/owner.pid)
#   LOCK_HELD         - initialize to 0 before sourcing
#
# Usage:
#   LOCK_DIR="/path/to/.lock"
#   LOCK_OWNER_FILE="${LOCK_DIR}/owner.pid"
#   LOCK_HELD=0
#   source "kernel-lock.sh"
#   trap cleanup_lock EXIT INT TERM
#   acquire_lock
#   ...
#   release_lock

cleanup_lock() {
  if [[ "${LOCK_HELD}" == "1" ]]; then
    rm -rf "${LOCK_DIR:?}" 2>/dev/null || true
    LOCK_HELD=0
  fi
}

stale_lock_owner_dead() {
  [[ -f "${LOCK_OWNER_FILE}" ]] || return 1
  local owner_pid=""
  owner_pid="$(cat "${LOCK_OWNER_FILE}" 2>/dev/null || true)"
  [[ -n "${owner_pid}" ]] || return 1
  kill -0 "${owner_pid}" 2>/dev/null && return 1
  return 0
}

acquire_lock() {
  local label="${1:-lock}"
  local attempts=0
  mkdir -p "$(dirname "${LOCK_DIR}")"
  while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
    if stale_lock_owner_dead; then
      rm -rf "${LOCK_DIR:?}" 2>/dev/null || true
      continue
    fi
    attempts=$((attempts + 1))
    if (( attempts >= 200 )); then
      echo "${label} lock timeout: ${LOCK_DIR}" >&2
      exit 1
    fi
    sleep 0.05
  done
  printf '%s\n' "$$" >"${LOCK_OWNER_FILE}"
  LOCK_HELD=1
}

release_lock() {
  cleanup_lock
}
