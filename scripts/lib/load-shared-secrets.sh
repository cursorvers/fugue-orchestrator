#!/usr/bin/env bash
set -euo pipefail

KEYCHAIN_SERVICE="${SHARED_SECRETS_KEYCHAIN_SERVICE:-fugue-secrets}"
ENV_FILE="${SHARED_SECRETS_ENV_FILE:-}"

DEFAULT_VARS=(
  OPENAI_API_KEY
  ANTHROPIC_API_KEY
  ZAI_API_KEY
  GEMINI_API_KEY
  XAI_API_KEY
  TARGET_REPO_PAT
  FUGUE_OPS_PAT
)

usage() {
  cat <<'EOF'
Usage:
  load-shared-secrets.sh get <VAR>
  load-shared-secrets.sh source-of <VAR>
  load-shared-secrets.sh export [VAR...]
  load-shared-secrets.sh doctor [VAR...]

Resolution order:
  1) process env
  2) macOS Keychain
  3) explicit external env file (SHARED_SECRETS_ENV_FILE)
EOF
}

canonical_name() {
  case "${1:-}" in
    XAI_API) printf 'XAI_API_KEY\n' ;;
    *) printf '%s\n' "${1:-}" ;;
  esac
}

legacy_aliases() {
  case "${1:-}" in
    XAI_API_KEY) printf 'XAI_API\n' ;;
    *) ;;
  esac
}

keychain_account_for() {
  case "${1:-}" in
    OPENAI_API_KEY) printf 'openai-api-key\n' ;;
    ANTHROPIC_API_KEY) printf 'anthropic-api-key\n' ;;
    GEMINI_API_KEY) printf 'gemini-api-key\n' ;;
    ZAI_API_KEY) printf 'zai-api-key\n' ;;
    XAI_API_KEY) printf 'xai-api-key\n' ;;
    TARGET_REPO_PAT) printf 'target-repo-pat\n' ;;
    FUGUE_OPS_PAT) printf 'fugue-ops-pat\n' ;;
    *) return 1 ;;
  esac
}

resolve_from_env() {
  local name="$1"
  local value="${!name-}"
  if [[ -n "${value}" ]]; then
    printf 'process-env\t%s\n' "${value}"
    return 0
  fi

  local alias_name
  while IFS= read -r alias_name; do
    [[ -n "${alias_name}" ]] || continue
    value="${!alias_name-}"
    if [[ -n "${value}" ]]; then
      printf 'process-env\t%s\n' "${value}"
      return 0
    fi
  done < <(legacy_aliases "${name}")

  return 1
}

resolve_from_keychain() {
  command -v security >/dev/null 2>&1 || return 1

  local name="$1"
  local account value
  account="$(keychain_account_for "${name}" 2>/dev/null || true)"
  [[ -n "${account}" ]] || return 1

  if value="$(security find-generic-password -a "${account}" -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null)"; then
    printf 'keychain\t%s\n' "${value}"
    return 0
  fi

  return 1
}

resolve_from_env_file() {
  local name="$1"
  [[ -n "${ENV_FILE}" ]] || return 1
  [[ -f "${ENV_FILE}" ]] || return 1

  local value
  value="$(
    env -i bash -lc '
      set -a
      source "$1"
      set +a
      printf "%s" "${!2-}"
    ' bash "${ENV_FILE}" "${name}"
  )"
  if [[ -n "${value}" ]]; then
    printf 'external-env\t%s\n' "${value}"
    return 0
  fi

  local alias_name
  while IFS= read -r alias_name; do
    [[ -n "${alias_name}" ]] || continue
    value="$(
      env -i bash -lc '
        set -a
        source "$1"
        set +a
        printf "%s" "${!2-}"
      ' bash "${ENV_FILE}" "${alias_name}"
    )"
    if [[ -n "${value}" ]]; then
      printf 'external-env\t%s\n' "${value}"
      return 0
    fi
  done < <(legacy_aliases "${name}")

  return 1
}

resolve_secret() {
  local canonical
  canonical="$(canonical_name "${1:-}")"

  resolve_from_env "${canonical}" && return 0
  resolve_from_keychain "${canonical}" && return 0
  resolve_from_env_file "${canonical}" && return 0
  return 1
}

cmd_get() {
  local name="${1:-}"
  local resolved
  [[ -n "${name}" ]] || {
    echo "VAR is required" >&2
    exit 2
  }
  resolved="$(resolve_secret "${name}")" || return 1
  printf '%s\n' "${resolved#*$'\t'}"
}

cmd_source_of() {
  local name="${1:-}"
  local resolved
  [[ -n "${name}" ]] || {
    echo "VAR is required" >&2
    exit 2
  }
  if ! resolved="$(resolve_secret "${name}")"; then
    printf 'missing\n'
    return 1
  fi
  printf '%s\n' "${resolved%%$'\t'*}"
}

cmd_export() {
  local vars=("$@")
  local name canonical resolved value
  if ((${#vars[@]} == 0)); then
    vars=("${DEFAULT_VARS[@]}")
  fi
  for name in "${vars[@]}"; do
    canonical="$(canonical_name "${name}")"
    if resolved="$(resolve_secret "${canonical}" 2>/dev/null)"; then
      value="${resolved#*$'\t'}"
      printf 'export %s=%q\n' "${canonical}" "${value}"
    fi
  done
}

cmd_doctor() {
  local vars=("$@")
  local name canonical resolved source value
  if ((${#vars[@]} == 0)); then
    vars=("${DEFAULT_VARS[@]}")
  fi
  printf 'shared secrets doctor:\n'
  for name in "${vars[@]}"; do
    canonical="$(canonical_name "${name}")"
    if resolved="$(resolve_secret "${canonical}" 2>/dev/null)"; then
      source="${resolved%%$'\t'*}"
      value="${resolved#*$'\t'}"
      printf '  - %s: present (%s, len=%s)\n' "${canonical}" "${source}" "${#value}"
    else
      printf '  - %s: missing\n' "${canonical}"
    fi
  done
}

cmd="${1:-doctor}"
case "${cmd}" in
  get)
    shift || true
    cmd_get "$@"
    ;;
  source-of)
    shift || true
    cmd_source_of "$@"
    ;;
  export)
    shift || true
    cmd_export "$@"
    ;;
  doctor)
    shift || true
    cmd_doctor "$@"
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
