#!/usr/bin/env bash
set -euo pipefail

notebooklm_resolve_bin() {
  local requested="${1:-}"
  local candidate=""
  local resolved=""

  if [[ -z "${requested}" ]]; then
    requested="${NLM_BIN:-${FUGUE_NOTEBOOKLM_BIN:-nlm}}"
  fi

  if [[ "${requested}" == */* ]]; then
    [[ -x "${requested}" ]] || {
      printf 'ERROR: missing required command: %s\n' "${requested}" >&2
      return 1
    }
    printf '%s\n' "${requested}"
    return 0
  fi

  if resolved="$(command -v "${requested}" 2>/dev/null)"; then
    printf '%s\n' "${resolved}"
    return 0
  fi

  if [[ "${requested}" != "nlm" ]]; then
    printf 'ERROR: missing required command: %s\n' "${requested}" >&2
    return 1
  fi

  while IFS= read -r candidate; do
    [[ -n "${candidate}" ]] || continue
    if [[ -x "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done <<EOF
${HOME}/.local/bin/nlm
${HOME}/bin/nlm
/usr/local/bin/nlm
/opt/homebrew/bin/nlm
/opt/local/bin/nlm
EOF

  printf 'ERROR: missing required command: %s\n' "${requested}" >&2
  return 1
}
