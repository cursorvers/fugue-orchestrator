#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
CONSENSUS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-consensus-evidence.sh"
source "${SCRIPT_DIR}/workspace-root-policy.sh"

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
  kernel-runtime-workspace.sh key [run_id]
  kernel-runtime-workspace.sh path [run_id]
  kernel-runtime-workspace.sh receipt-path [run_id]
  kernel-runtime-workspace.sh ensure [run_id]
  kernel-runtime-workspace.sh write [run_id]
  kernel-runtime-workspace.sh status [run_id]
EOF
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

slugify() {
  local value="${1:-}"
  value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "${value}" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  if [[ -z "${value}" ]]; then
    printf 'unknown\n'
  else
    printf '%s\n' "${value}"
  fi
}

workspace_root_base() {
  local candidate="${KERNEL_RUNTIME_WORKSPACE_ROOT:-${ROOT_DIR}/.fugue/kernel-workspaces}"
  fugue_resolve_workspace_dir "${ROOT_DIR}" "${candidate}" "kernel runtime workspace root"
}

receipt_root_base() {
  local candidate="${KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR:-${ROOT_DIR}/.fugue/kernel-runtime-workspaces}"
  fugue_resolve_workspace_dir "${ROOT_DIR}" "${candidate}" "kernel runtime workspace receipt dir"
}

workspace_key_for() {
  local run_id="${1:-${RUN_ID}}"
  local project_slug
  project_slug="$(slugify "${KERNEL_PROJECT:-kernel-workspace}")"
  printf '%s--%s\n' "${project_slug}" "$(slugify "${run_id}")"
}

workspace_dir_for() {
  local run_id="${1:-${RUN_ID}}"
  local base project_slug workspace_key
  base="$(workspace_root_base)"
  project_slug="$(slugify "${KERNEL_PROJECT:-kernel-workspace}")"
  workspace_key="$(workspace_key_for "${run_id}")"
  fugue_resolve_workspace_dir "${ROOT_DIR}" "${base}/${project_slug}/${workspace_key}" "kernel runtime workspace"
}

receipt_path_for() {
  local run_id="${1:-${RUN_ID}}"
  local base
  base="$(receipt_root_base)"
  mkdir -p "${base}"
  printf '%s/%s.json\n' "${base}" "$(printf '%s' "${run_id}" | tr '/:' '__')"
}

compact_artifact_path_for() {
  local run_id="${1:-${RUN_ID}}"
  local compact_dir="${KERNEL_COMPACT_DIR:-$(bash "${STATE_PATH_SCRIPT}" compact-dir)}"
  printf '%s/%s.json\n' "${compact_dir}" "$(printf '%s' "${run_id}" | tr '/:' '__')"
}

bootstrap_receipt_path_for() {
  local run_id="${1:-${RUN_ID}}"
  local dir="${KERNEL_BOOTSTRAP_RECEIPT_DIR:-$(bash "${STATE_PATH_SCRIPT}" bootstrap-receipt-dir)}"
  printf '%s/%s.json\n' "${dir}" "$(printf '%s' "${run_id}" | tr '/:' '__')"
}

ledger_path_for() {
  printf '%s\n' "${KERNEL_RUNTIME_LEDGER_FILE:-$(bash "${STATE_PATH_SCRIPT}" runtime-ledger-file)}"
}

consensus_receipt_path_for() {
  local run_id="${1:-${RUN_ID}}"
  local path
  [[ -f "${CONSENSUS_SCRIPT}" ]] || return 0
  path="$(KERNEL_RUN_ID="${run_id}" bash "${CONSENSUS_SCRIPT}" path 2>/dev/null || true)"
  if [[ -n "${path}" && -f "${path}" ]]; then
    printf '%s\n' "${path}"
  fi
}

write_receipt() {
  local run_id="${1:-${RUN_ID}}"
  local workspace_dir receipt_path artifacts_dir logs_dir traces_dir workspace_key
  local now created_at tmp_file

  workspace_dir="$(workspace_dir_for "${run_id}")"
  receipt_path="$(receipt_path_for "${run_id}")"
  workspace_key="$(workspace_key_for "${run_id}")"
  artifacts_dir="${workspace_dir}/artifacts"
  logs_dir="${workspace_dir}/logs"
  traces_dir="${workspace_dir}/traces"
  mkdir -p "${workspace_dir}" "${artifacts_dir}" "${logs_dir}" "${traces_dir}" "$(dirname "${receipt_path}")"
  now="$(utc_timestamp)"
  created_at="${now}"
  if [[ -f "${receipt_path}" ]]; then
    created_at="$(jq -r '.created_at // empty' "${receipt_path}")"
    [[ -n "${created_at}" ]] || created_at="${now}"
  fi
  tmp_file="$(umask 077 && mktemp "${receipt_path}.tmp.XXXXXXXXXX")"
  jq -n \
    --arg version "1" \
    --arg run_id "${run_id}" \
    --arg project "${KERNEL_PROJECT:-kernel-workspace}" \
    --arg purpose "${KERNEL_PURPOSE:-unspecified}" \
    --arg runtime "$(printf '%s' "${KERNEL_RUNTIME:-kernel}" | tr '[:upper:]' '[:lower:]')" \
    --arg workspace_key "${workspace_key}" \
    --arg workspace_dir "${workspace_dir}" \
    --arg artifacts_dir "${artifacts_dir}" \
    --arg logs_dir "${logs_dir}" \
    --arg traces_dir "${traces_dir}" \
    --arg compact_artifact_path "$(compact_artifact_path_for "${run_id}")" \
    --arg bootstrap_receipt_path "$(bootstrap_receipt_path_for "${run_id}")" \
    --arg runtime_ledger_path "$(ledger_path_for)" \
    --arg consensus_receipt_path "$(consensus_receipt_path_for "${run_id}")" \
    --arg created_at "${created_at}" \
    --arg updated_at "${now}" \
    '{
      version: ($version | tonumber),
      run_id: $run_id,
      project: $project,
      purpose: $purpose,
      runtime: $runtime,
      workspace_key: $workspace_key,
      workspace_dir: $workspace_dir,
      artifacts_dir: $artifacts_dir,
      logs_dir: $logs_dir,
      traces_dir: $traces_dir,
      compact_artifact_path: $compact_artifact_path,
      bootstrap_receipt_path: $bootstrap_receipt_path,
      runtime_ledger_path: $runtime_ledger_path,
      consensus_receipt_path: $consensus_receipt_path,
      created_at: $created_at,
      updated_at: $updated_at
    }' >"${tmp_file}"
  mv "${tmp_file}" "${receipt_path}"
  printf '%s\n' "${receipt_path}"
}

cmd_key() {
  workspace_key_for "${1:-${RUN_ID}}"
}

cmd_path() {
  workspace_dir_for "${1:-${RUN_ID}}"
}

cmd_receipt_path() {
  receipt_path_for "${1:-${RUN_ID}}"
}

cmd_ensure() {
  local run_id="${1:-${RUN_ID}}"
  write_receipt "${run_id}" >/dev/null
  workspace_dir_for "${run_id}"
}

cmd_write() {
  write_receipt "${1:-${RUN_ID}}"
}

cmd_status() {
  local receipt_path="${2:-}"
  local run_id="${1:-${RUN_ID}}"
  if [[ -z "${receipt_path}" ]]; then
    receipt_path="$(receipt_path_for "${run_id}")"
  fi
  if [[ ! -f "${receipt_path}" ]]; then
    echo "workspace receipt missing for run: ${run_id}" >&2
    exit 1
  fi
  printf 'kernel runtime workspace:\n'
  jq -r '
    "  - run id: \(.run_id)",
    "  - project: \(.project)",
    "  - purpose: \(.purpose)",
    "  - runtime: \(.runtime)",
    "  - workspace key: \(.workspace_key)",
    "  - workspace dir: \(.workspace_dir)",
    "  - artifacts dir: \(.artifacts_dir)",
    "  - logs dir: \(.logs_dir)",
    "  - traces dir: \(.traces_dir)",
    "  - compact artifact path: \(.compact_artifact_path)",
    "  - bootstrap receipt path: \(.bootstrap_receipt_path)",
    "  - runtime ledger path: \(.runtime_ledger_path)",
    "  - consensus receipt path: \(.consensus_receipt_path // "")",
    "  - created at: \(.created_at)",
    "  - updated at: \(.updated_at)"
  ' "${receipt_path}"
}

cmd="${1:-status}"
case "${cmd}" in
  key)
    shift || true
    cmd_key "$@"
    ;;
  path)
    shift || true
    cmd_path "$@"
    ;;
  receipt-path)
    shift || true
    cmd_receipt_path "$@"
    ;;
  ensure)
    shift || true
    cmd_ensure "$@"
    ;;
  write)
    shift || true
    cmd_write "$@"
    ;;
  status)
    shift || true
    cmd_status "$@"
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
