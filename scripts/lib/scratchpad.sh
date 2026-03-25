#!/usr/bin/env bash
# scratchpad.sh — JSONL audit trail logger for FUGUE skill execution.
#
# Source this file to gain scratchpad_init / scratchpad_log functions.
# Idempotent: safe to source multiple times.

if [[ -z "${_FUGUE_SCRATCHPAD_LOADED:-}" ]]; then
_FUGUE_SCRATCHPAD_LOADED=1

# Escape characters that would break JSON string values.
_scratchpad_json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

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
    "$(_scratchpad_json_escape "${tool_name}")" \
    "$(_scratchpad_json_escape "${status}")" \
    "${duration_ms}" \
    "$(_scratchpad_json_escape "${summary}")" >> "${repo_root}/${SCRATCHPAD_FILE}"
}

fi
