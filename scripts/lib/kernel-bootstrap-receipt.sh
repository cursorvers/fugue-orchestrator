#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
RECEIPT_DIR="${KERNEL_BOOTSTRAP_RECEIPT_DIR:-$(bash "${STATE_PATH_SCRIPT}" bootstrap-receipt-dir)}"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"

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
  kernel-bootstrap-receipt.sh path [run_id]
  kernel-bootstrap-receipt.sh write <lane_count> <providers_csv> <mode> [note]
  kernel-bootstrap-receipt.sh status [run_id]

Optional evidence environment:
  KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV
  KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT
  KERNEL_BOOTSTRAP_AGENT_LABELS=true|false
  KERNEL_BOOTSTRAP_SUBAGENT_LABELS=true|false
EOF
}

receipt_path_for() {
  local run_id="$1"
  mkdir -p "${RECEIPT_DIR}"
  printf '%s/%s.json\n' "${RECEIPT_DIR}" "$(printf '%s' "${run_id}" | tr '/:' '__')"
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

cmd_path() {
  printf '%s\n' "$(receipt_path_for "${1:-${RUN_ID}}")"
}

cmd_write() {
  local lane_count="${1:-}"
  local providers_csv="${2:-}"
  local mode="${3:-}"
  local note="${4:-bootstrap-receipt}"
  local active_models_csv="${KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV:-}"
  local manifest_lane_count="${KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT:-0}"
  local agent_labels="${KERNEL_BOOTSTRAP_AGENT_LABELS:-false}"
  local subagent_labels="${KERNEL_BOOTSTRAP_SUBAGENT_LABELS:-false}"
  local path
  if [[ -z "${lane_count}" || -z "${providers_csv}" || -z "${mode}" ]]; then
    echo "lane_count, providers_csv, and mode are required" >&2
    exit 2
  fi
  path="$(receipt_path_for "${RUN_ID}")"
  jq -n \
    --arg run_id "${RUN_ID}" \
    --arg recorded_at "$(utc_timestamp)" \
    --arg providers_csv "${providers_csv}" \
    --arg mode "${mode}" \
    --arg note "${note}" \
    --arg active_models_csv "${active_models_csv}" \
    --arg agent_labels "${agent_labels}" \
    --arg subagent_labels "${subagent_labels}" \
    --argjson manifest_lane_count "${manifest_lane_count}" \
    --argjson lane_count "${lane_count}" \
    '
      ($providers_csv | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))) as $providers
      | ($active_models_csv | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))) as $active_models
      | {
          run_id: $run_id,
          recorded_at: $recorded_at,
          lane_count: $lane_count,
          providers: $providers,
          active_models: $active_models,
          active_model_count: ($active_models | length),
          manifest_lane_count: $manifest_lane_count,
          has_agent_labels: ($agent_labels == "true"),
          has_subagent_labels: ($subagent_labels == "true"),
          mode: $mode,
          note: $note,
          has_codex: ($providers | index("codex") != null),
          has_glm: ($providers | index("glm") != null),
          specialist_count: ($providers | map(select(. != "codex" and . != "glm")) | length)
        }
    ' >"${path}"
  if [[ -f "${WORKSPACE_SCRIPT}" ]]; then
    KERNEL_RUN_ID="${RUN_ID}" bash "${WORKSPACE_SCRIPT}" write >/dev/null
  fi
  KERNEL_RUN_ID="${RUN_ID}" bash "${LEDGER_SCRIPT}" transition running "bootstrap-receipt" "${path}" >/dev/null
  cmd_status "${RUN_ID}"
}

cmd_status() {
  local run_id="${1:-${RUN_ID}}"
  local path
  path="$(receipt_path_for "${run_id}")"
  if [[ ! -f "${path}" ]]; then
    printf 'bootstrap receipt:\n'
    printf '  - run id: %s\n' "${run_id}"
    printf '  - present: false\n'
    printf '  - path: %s\n' "${path}"
    return 1
  fi
  printf 'bootstrap receipt:\n'
  printf '  - run id: %s\n' "${run_id}"
  printf '  - present: true\n'
  printf '  - path: %s\n' "${path}"
  jq -r '
    "  - lane count: \(.lane_count)",
    "  - mode: \(.mode)",
    "  - providers: \(.providers | join(","))",
    "  - active models: \(.active_models | join(","))",
    "  - active model count: \(.active_model_count)",
    "  - manifest lane count: \(.manifest_lane_count)",
    "  - has agent labels: \(.has_agent_labels)",
    "  - has subagent labels: \(.has_subagent_labels)",
    "  - has codex: \(.has_codex)",
    "  - has glm: \(.has_glm)",
    "  - specialist count: \(.specialist_count)"
  ' "${path}"
}

cmd="${1:-status}"
case "${cmd}" in
  path)
    shift || true
    cmd_path "$@"
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
