#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"

default_run_id() {
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  printf 'unknown-run\n'
}

RUN_ID="$(default_run_id)"

usage() {
  cat <<'EOF'
Usage:
  kernel-auth-evidence.sh path <provider> [run_id]
  kernel-auth-evidence.sh status <provider> [run_id]
  kernel-auth-evidence.sh record <provider> <ready|not-ready> [note]
EOF
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

epoch_timestamp() {
  date '+%s'
}

state_root() {
  bash "${STATE_PATH_SCRIPT}" state-root
}

run_slug() {
  printf '%s' "${1:-${RUN_ID}}" | tr -c '[:alnum:]._-=' '_'
}

path_for() {
  local provider="${1:?provider is required}"
  local run_id="${2:-${RUN_ID}}"
  local dir
  dir="$(state_root)/auth-evidence/$(run_slug "${run_id}")"
  mkdir -p "${dir}"
  printf '%s/%s.json\n' "${dir}" "${provider}"
}

cmd_path() {
  local provider="${1:?provider is required}"
  local run_id="${2:-${RUN_ID}}"
  path_for "${provider}" "${run_id}"
}

cmd_record() {
  local provider="${1:?provider is required}"
  local state="${2:?state is required}"
  local note="${3:-}"
  local path tmp_file now now_epoch created_at

  case "${state}" in
    ready|not-ready) ;;
    *)
      echo "state must be ready or not-ready" >&2
      exit 2
      ;;
  esac

  path="$(path_for "${provider}" "${RUN_ID}")"
  now="$(utc_timestamp)"
  now_epoch="$(epoch_timestamp)"
  created_at="${now}"
  if [[ -f "${path}" ]]; then
    created_at="$(jq -r '.created_at // empty' "${path}")"
    [[ -n "${created_at}" ]] || created_at="${now}"
  fi
  tmp_file="$(umask 077 && mktemp "${path}.tmp.XXXXXXXXXX")"
  jq -n \
    --arg run_id "${RUN_ID}" \
    --arg provider "${provider}" \
    --arg state "${state}" \
    --arg note "${note}" \
    --arg created_at "${created_at}" \
    --arg updated_at "${now}" \
    --argjson updated_at_epoch "${now_epoch}" \
    '{
      run_id: $run_id,
      provider: $provider,
      state: $state,
      note: $note,
      created_at: $created_at,
      updated_at: $updated_at,
      updated_at_epoch: $updated_at_epoch
    }' > "${tmp_file}"
  mv "${tmp_file}" "${path}"
  printf '%s\n' "${path}"
}

cmd_status() {
  local provider="${1:?provider is required}"
  local run_id="${2:-${RUN_ID}}"
  local path

  path="$(path_for "${provider}" "${run_id}")"
  if [[ ! -f "${path}" ]]; then
    printf 'kernel auth evidence:\n'
    printf '  - run id: %s\n' "${run_id}"
    printf '  - provider: %s\n' "${provider}"
    printf '  - present: false\n'
    printf '  - path: %s\n' "${path}"
    return 1
  fi

  printf 'kernel auth evidence:\n'
  printf '  - run id: %s\n' "${run_id}"
  printf '  - provider: %s\n' "${provider}"
  printf '  - present: true\n'
  printf '  - path: %s\n' "${path}"
  jq -r '
    "  - state: \(.state)",
    "  - note: \(.note)",
    "  - updated at: \(.updated_at)"
  ' "${path}"
}

cmd="${1:-status}"
case "${cmd}" in
  path)
    shift || true
    cmd_path "$@"
    ;;
  status)
    shift || true
    cmd_status "$@"
    ;;
  record)
    shift || true
    cmd_record "$@"
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
