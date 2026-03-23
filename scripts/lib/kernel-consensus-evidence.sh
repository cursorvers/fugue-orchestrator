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
  kernel-consensus-evidence.sh path [run_id]
  kernel-consensus-evidence.sh status [run_id]
  kernel-consensus-evidence.sh record <approved|rejected> [source] [summary]
  kernel-consensus-evidence.sh from-local-orchestration <integrated.json> [source] [summary]
EOF
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

state_root() {
  bash "${STATE_PATH_SCRIPT}" state-root
}

receipt_dir() {
  printf '%s/consensus-receipts\n' "$(state_root)"
}

path_for() {
  local run_id="${1:-${RUN_ID}}"
  mkdir -p "$(receipt_dir)"
  printf '%s/%s.json\n' "$(receipt_dir)" "$(printf '%s' "${run_id}" | tr '/:' '__')"
}

normalize_tier() {
  local tier="${1:-medium}"
  tier="$(printf '%s' "${tier}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  case "${tier}" in
    small|medium|large|critical) printf '%s\n' "${tier}" ;;
    *) printf 'medium\n' ;;
  esac
}

write_receipt() {
  local run_id="$1"
  local decision="$2"
  local source="$3"
  local summary="$4"
  local task_size_tier="$5"
  local weighted_vote_passed="$6"
  local ok_to_execute="$7"
  local lanes="$8"
  local now created_at path tmp_file

  path="$(path_for "${run_id}")"
  now="$(utc_timestamp)"
  created_at="${now}"
  if [[ -f "${path}" ]]; then
    created_at="$(jq -r '.created_at // empty' "${path}")"
    [[ -n "${created_at}" ]] || created_at="${now}"
  fi
  tmp_file="$(umask 077 && mktemp "${path}.tmp.XXXXXXXXXX")"
  jq -n \
    --arg run_id "${run_id}" \
    --arg decision "${decision}" \
    --arg source "${source}" \
    --arg summary "${summary}" \
    --arg task_size_tier "${task_size_tier}" \
    --arg weighted_vote_passed "${weighted_vote_passed}" \
    --arg ok_to_execute "${ok_to_execute}" \
    --argjson lanes "${lanes}" \
    --arg created_at "${created_at}" \
    --arg updated_at "${now}" \
    '{
      run_id: $run_id,
      decision: $decision,
      source: $source,
      summary: $summary,
      task_size_tier: $task_size_tier,
      critical: ($task_size_tier == "critical"),
      weighted_vote_passed: ($weighted_vote_passed == "true"),
      ok_to_execute: ($ok_to_execute == "true"),
      lanes_configured: $lanes,
      created_at: $created_at,
      updated_at: $updated_at
    }' > "${tmp_file}"
  mv "${tmp_file}" "${path}"
  printf '%s\n' "${path}"
}

cmd_path() {
  path_for "${1:-${RUN_ID}}"
}

cmd_status() {
  local run_id="${1:-${RUN_ID}}"
  local path
  path="$(path_for "${run_id}")"
  if [[ ! -f "${path}" ]]; then
    printf 'kernel consensus evidence:\n'
    printf '  - run id: %s\n' "${run_id}"
    printf '  - present: false\n'
    printf '  - path: %s\n' "${path}"
    return 1
  fi
  printf 'kernel consensus evidence:\n'
  printf '  - run id: %s\n' "${run_id}"
  printf '  - present: true\n'
  printf '  - path: %s\n' "${path}"
  jq -r '
    "  - decision: \(.decision)",
    "  - source: \(.source)",
    "  - task size tier: \(.task_size_tier)",
    "  - critical: \(.critical)",
    "  - weighted vote passed: \(.weighted_vote_passed)",
    "  - ok to execute: \(.ok_to_execute)",
    "  - lanes configured: \(.lanes_configured)",
    "  - summary: \(.summary)",
    "  - updated at: \(.updated_at)"
  ' "${path}"
}

cmd_record() {
  local decision="${1:-}"
  local source="${2:-local-vote}"
  local summary="${3:-local kernel consensus}"
  local task_size_tier weighted_vote_passed ok_to_execute lanes

  [[ "${decision}" == "approved" || "${decision}" == "rejected" ]] || {
    echo "decision must be approved or rejected" >&2
    exit 2
  }

  task_size_tier="$(normalize_tier "${KERNEL_TASK_SIZE_TIER:-medium}")"
  if [[ "${decision}" == "approved" ]]; then
    weighted_vote_passed="${KERNEL_WEIGHTED_VOTE_PASSED:-true}"
    ok_to_execute="${KERNEL_OK_TO_EXECUTE:-true}"
  else
    weighted_vote_passed="${KERNEL_WEIGHTED_VOTE_PASSED:-false}"
    ok_to_execute="${KERNEL_OK_TO_EXECUTE:-false}"
  fi
  lanes="${KERNEL_CONSENSUS_LANES:-2}"

  write_receipt "${RUN_ID}" "${decision}" "${source}" "${summary}" "${task_size_tier}" "${weighted_vote_passed}" "${ok_to_execute}" "${lanes}" >/dev/null
  cmd_status "${RUN_ID}"
}

cmd_from_local_orchestration() {
  local json_path="${1:-}"
  local source="${2:-local-vote}"
  local summary="${3:-local orchestration consensus}"
  local task_size_tier decision weighted_vote_passed ok_to_execute lanes

  [[ -f "${json_path}" ]] || {
    echo "integrated orchestration json missing: ${json_path}" >&2
    exit 1
  }

  task_size_tier="$(normalize_tier "$(jq -r '.issue_task_size_tier // "medium"' "${json_path}")")"
  weighted_vote_passed="$(jq -r '.weighted_vote_passed // false' "${json_path}")"
  ok_to_execute="$(jq -r '.ok_to_execute // false' "${json_path}")"
  lanes="$(jq -r '.lanes_configured // 0' "${json_path}")"
  if [[ "${weighted_vote_passed}" == "true" && "${ok_to_execute}" == "true" ]]; then
    decision="approved"
  else
    decision="rejected"
  fi

  write_receipt "${RUN_ID}" "${decision}" "${source}" "${summary}" "${task_size_tier}" "${weighted_vote_passed}" "${ok_to_execute}" "${lanes}" >/dev/null
  cmd_status "${RUN_ID}"
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
  from-local-orchestration)
    shift || true
    cmd_from_local_orchestration "$@"
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
