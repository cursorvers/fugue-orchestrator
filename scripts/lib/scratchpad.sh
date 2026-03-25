#!/usr/bin/env bash

if [[ -z "${_FUGUE_SCRATCHPAD_LOADED:-}" ]]; then
_FUGUE_SCRATCHPAD_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/common-utils.sh"

scratchpad_init() {
  local context_name="${1:?context_name is required}"
  local repo_root scratchpad_dir timestamp
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  scratchpad_dir="${repo_root}/.fugue/scratchpad"
  timestamp="$(date -u +%Y-%m-%d_%H-%M-%S)"
  mkdir -p "${scratchpad_dir}"
  SCRATCHPAD_FILE=".fugue/scratchpad/${timestamp}_${context_name}.jsonl"
}

scratchpad_log() {
  local tool_name="${1:?tool_name is required}"
  local status="${2:?status is required}"
  local duration_ms="${3:?duration_ms is required}"
  local summary="${4:-}"
  local repo_root ts

  if [[ -z "${SCRATCHPAD_FILE:-}" ]]; then
    echo "Error: SCRATCHPAD_FILE is not initialized. Call scratchpad_init first." >&2
    return 1
  fi

  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","tool":"%s","status":"%s","duration_ms":%s,"summary":"%s"}\n' \
    "${ts}" \
    "${tool_name}" \
    "${status}" \
    "${duration_ms}" \
    "${summary}" >> "${repo_root}/${SCRATCHPAD_FILE}"
}

fi
