#!/usr/bin/env bash
# safe-eval-policy.sh — Defense-in-depth wrapper for eval-ing policy script output.
#
# Validates that every non-empty line matches shell assignment syntax
# (VAR_NAME=value) before eval. Rejects lines that could execute
# arbitrary commands (e.g., command substitution, semicolons outside quotes).
#
# Usage:
#   source scripts/lib/safe-eval-policy.sh
#   safe_eval_policy orchestrator-policy.sh --main claude --assist codex
#
# Instead of:
#   eval "$(orchestrator-policy.sh --main claude --assist codex)"
set -euo pipefail

safe_eval_policy() {
  local script="$1"
  shift

  if [[ ! -x "${script}" ]]; then
    echo "safe_eval_policy: script not found or not executable: ${script}" >&2
    return 1
  fi

  local output
  output="$("${script}" "$@")" || {
    echo "safe_eval_policy: script failed: ${script}" >&2
    return 1
  }

  # Validate: every non-empty, non-comment line must be a shell assignment.
  # Allowed: VAR_NAME=<shell-quoted-value>
  # %q output produces $'...' or plain strings; both are safe.
  local line_num=0
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    # Skip empty lines and comments.
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    # Must match: identifier = something
    if ! [[ "${line}" =~ ^[A-Za-z_][A-Za-z_0-9]*= ]]; then
      echo "safe_eval_policy: invalid output at line ${line_num}: ${line}" >&2
      echo "safe_eval_policy: refusing to eval output from ${script}" >&2
      return 1
    fi
  done <<< "${output}"

  eval "${output}"
}
