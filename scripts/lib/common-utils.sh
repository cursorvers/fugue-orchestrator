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

fugue_gh_backoff_sleep() {
  local base="${1:-1}"
  local jitter_max="${2:-2}"
  local jitter="0"
  if [[ "${jitter_max}" =~ ^[0-9]+$ ]] && (( jitter_max > 0 )); then
    jitter=$(( RANDOM % (jitter_max + 1) ))
  fi
  sleep "$(( base + jitter ))"
}

fugue_gh_retry() {
  local attempts="${1:-5}"
  shift
  local sleep_sec=1
  local max_sleep="${FUGUE_GH_RETRY_MAX_SLEEP_SEC:-16}"
  local i out
  for ((i=1; i<=attempts; i++)); do
    if out="$("$@" 2>/dev/null)"; then
      printf '%s\n' "${out}"
      return 0
    fi
    if (( i == attempts )); then
      return 1
    fi
    fugue_gh_backoff_sleep "${sleep_sec}" 2
    if (( sleep_sec < max_sleep )); then
      sleep_sec=$((sleep_sec * 2))
      if (( sleep_sec > max_sleep )); then
        sleep_sec="${max_sleep}"
      fi
    fi
  done
  return 1
}

fugue_gh_api_retry() {
  local endpoint="$1"
  local attempts="${2:-5}"
  fugue_gh_retry "${attempts}" gh api "${endpoint}"
}

fi
