#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

resolve_health_script() {
  local candidate
  for candidate in \
    "${X_AUTO_HEALTH_SCRIPT:-}" \
    "${ROOT_DIR}/scripts/eval/x-auto-health.py" \
    "${HOME}/.claude/skills/x-auto/scripts/x-auto-health.py"
  do
    [[ -n "${candidate}" ]] || continue
    [[ -f "${candidate}" ]] || continue
    printf '%s\n' "${candidate}"
    return 0
  done
  return 1
}

main() {
  local script_path
  script_path="$(resolve_health_script)" || {
    echo "x-auto health script not found. Checked X_AUTO_HEALTH_SCRIPT, repo fallback, and ~/.claude/skills/x-auto/scripts/x-auto-health.py" >&2
    exit 1
  }
  exec python3 "${script_path}" "$@"
}

main "$@"
