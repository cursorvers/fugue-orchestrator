#!/usr/bin/env bash
set -euo pipefail

notebooklm_candidate_from_dir() {
  local dir="${1:-}"
  local candidate=""

  [[ -n "${dir}" ]] || return 1
  candidate="${dir%/}/nlm"
  [[ -x "${candidate}" ]] || return 1
  printf '%s\n' "${candidate}"
  return 0
}

notebooklm_candidate_from_prefix() {
  local prefix="${1:-}"
  notebooklm_candidate_from_dir "${prefix%/}/bin"
}

notebooklm_candidate_from_command() {
  local tool="$1"
  shift
  local output=""

  command -v "${tool}" >/dev/null 2>&1 || return 1
  output="$("${tool}" "$@" 2>/dev/null | tail -n 1 | tr -d '\r')" || return 1
  [[ -n "${output}" ]] || return 1
  printf '%s\n' "${output}"
  return 0
}

notebooklm_resolve_bin() {
  local requested="${1:-}"
  local candidate=""
  local resolved=""
  local manager_path=""

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
${HOME}/.npm-global/bin/nlm
${HOME}/.local/share/pnpm/nlm
${HOME}/Library/pnpm/nlm
${HOME}/.volta/bin/nlm
/usr/local/bin/nlm
/opt/homebrew/bin/nlm
/opt/local/bin/nlm
EOF

  if manager_path="$(notebooklm_candidate_from_command npm prefix -g)"; then
    if candidate="$(notebooklm_candidate_from_prefix "${manager_path}")"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  if manager_path="$(notebooklm_candidate_from_command pnpm bin -g)"; then
    if candidate="$(notebooklm_candidate_from_dir "${manager_path}")"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  if manager_path="$(notebooklm_candidate_from_command yarn global bin)"; then
    if candidate="$(notebooklm_candidate_from_dir "${manager_path}")"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  if manager_path="$(notebooklm_candidate_from_command volta which nlm)"; then
    if [[ -x "${manager_path}" ]]; then
      printf '%s\n' "${manager_path}"
      return 0
    fi
  fi

  printf 'ERROR: missing required command: %s\n' "${requested}" >&2
  return 1
}
