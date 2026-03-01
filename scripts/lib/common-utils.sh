#!/usr/bin/env bash
# common-utils.sh — Shared utility functions for FUGUE policy scripts.
#
# Source this file instead of redefining lower_trim / normalize_bool locally.
# Idempotent: safe to source multiple times.

if [[ -z "${_FUGUE_COMMON_UTILS_LOADED:-}" ]]; then
_FUGUE_COMMON_UTILS_LOADED=1

lower_trim() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

normalize_bool() {
  local v
  v="$(lower_trim "$1")"
  if [[ "${v}" == "true" || "${v}" == "1" || "${v}" == "yes" || "${v}" == "on" ]]; then
    printf '%s' "true"
  else
    printf '%s' "false"
  fi
}

fi
