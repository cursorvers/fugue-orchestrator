#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
CLAIM_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-claim.sh"
ATTESTATION_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-provider-attestation.sh"

usage() {
  cat <<'EOF'
Usage:
  kernel-runtime-run-driver.sh path [run_id]
  kernel-runtime-run-driver.sh run [options]

Options:
  --run-id <run_id>
  --identity <identity>
  --project <project>
  --issue-number <number>
  --task-key <task_key>
  --provider <provider>
  --topology-file <path>
  --command-string <command>
  --continuity-owner <owner>
  --trace-id <trace_id>
  --evidence-links-json <json-array>
EOF
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

epoch_now() {
  date -u '+%s'
}

hash_text() {
  local payload="${1:-}"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "${payload}" | shasum -a 256 | awk '{print $1}'
    return 0
  fi
  python3 - "${payload}" <<'PY'
import hashlib
import sys

print(hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest())
PY
}

derive_identity() {
  local identity="${1:-}"
  local project="${2:-${KERNEL_PROJECT:-kernel-workspace}}"
  local issue_number="${3:-}"
  local task_key="${4:-}"
  local run_id="${5:-}"
  if [[ -n "${identity}" ]]; then
    printf '%s\n' "${identity}"
    return 0
  fi
  if [[ -n "${issue_number}" ]]; then
    if [[ -n "${task_key}" ]]; then
      printf '%s#%s/%s\n' "${project}" "${issue_number}" "${task_key}"
    else
      printf '%s#%s\n' "${project}" "${issue_number}"
    fi
    return 0
  fi
  printf '%s@%s\n' "${project}" "${run_id}"
}

default_run_id() {
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  printf 'unknown-run\n'
}

RUN_ID="$(default_run_id)"

workspace_dir_for() {
  KERNEL_RUN_ID="${1:-${RUN_ID}}" bash "${WORKSPACE_SCRIPT}" path
}

workspace_receipt_for() {
  KERNEL_RUN_ID="${1:-${RUN_ID}}" bash "${WORKSPACE_SCRIPT}" write
}

envelope_path_for() {
  local run_id="${1:-${RUN_ID}}"
  local workspace_dir
  workspace_dir="$(workspace_dir_for "${run_id}")"
  mkdir -p "${workspace_dir}/traces"
  printf '%s/traces/run-envelope.json\n' "${workspace_dir}"
}

trace_path_for() {
  local run_id="${1:-${RUN_ID}}"
  local workspace_dir
  workspace_dir="$(workspace_dir_for "${run_id}")"
  mkdir -p "${workspace_dir}/traces"
  printf '%s/traces/run-trace.json\n' "${workspace_dir}"
}

log_path_for() {
  local run_id="${1:-${RUN_ID}}"
  local workspace_dir
  workspace_dir="$(workspace_dir_for "${run_id}")"
  mkdir -p "${workspace_dir}/logs"
  printf '%s/logs/run-driver.log\n' "${workspace_dir}"
}

write_json_atomic() {
  local path="${1:?path is required}"
  local payload="${2:?payload is required}"
  local tmp_file
  mkdir -p "$(dirname "${path}")"
  tmp_file="$(umask 077 && mktemp "${path}.tmp.XXXXXXXXXX")"
  printf '%s\n' "${payload}" >"${tmp_file}"
  mv "${tmp_file}" "${path}"
}

resolve_topology_field() {
  local topology_file="${1:-}"
  local expr="${2:-.}"
  if [[ -n "${topology_file}" && -f "${topology_file}" ]]; then
    jq -r "${expr} // \"\"" "${topology_file}"
  else
    printf '\n'
  fi
}

resolve_topology_approved() {
  local topology_file="${1:-}"
  jq -r '(.approved // .ok_to_execute // false) | if . then "true" else "false" end' "${topology_file}"
}

contains_exit_code() {
  local codes="${1:-}"
  local rc="${2:-}"
  local code
  IFS=',' read -r -a code_array <<<"${codes}"
  for code in "${code_array[@]}"; do
    code="$(printf '%s' "${code}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -n "${code}" ]] || continue
    if [[ "${code}" == "${rc}" ]]; then
      return 0
    fi
  done
  return 1
}

cmd_path() {
  printf '%s\n' "$(envelope_path_for "${1:-${RUN_ID}}")"
}

cmd_run() {
  local run_id="${RUN_ID}" identity="" project="${KERNEL_PROJECT:-kernel-workspace}" issue_number="" task_key=""
  local provider="${KERNEL_RUN_DRIVER_PROVIDER:-codex}" topology_file="" command_string="" continuity_owner="local-primary"
  local trace_id="" evidence_links_json='[]'
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run-id) run_id="${2:-}"; shift 2 ;;
      --identity) identity="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      --issue-number) issue_number="${2:-}"; shift 2 ;;
      --task-key) task_key="${2:-}"; shift 2 ;;
      --provider) provider="${2:-}"; shift 2 ;;
      --topology-file) topology_file="${2:-}"; shift 2 ;;
      --command-string) command_string="${2:-}"; shift 2 ;;
      --continuity-owner) continuity_owner="${2:-}"; shift 2 ;;
      --trace-id) trace_id="${2:-}"; shift 2 ;;
      --evidence-links-json) evidence_links_json="${2:-[]}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done

  identity="$(derive_identity "${identity}" "${project}" "${issue_number}" "${task_key}" "${run_id}")"
  local topology_approved topology_command topology_provider
  if [[ -z "${topology_file}" ]]; then
    echo "run driver requires --topology-file for Kernel-approved execution" >&2
    exit 2
  fi
  if [[ ! -f "${topology_file}" ]]; then
    echo "topology file not found: ${topology_file}" >&2
    exit 2
  fi
  topology_approved="$(resolve_topology_approved "${topology_file}")"
  topology_command="$(resolve_topology_field "${topology_file}" '.launch.command_string // .execution.command_string')"
  topology_provider="$(resolve_topology_field "${topology_file}" '.launch.provider // .provider')"
  command_string="${command_string:-${KERNEL_RUN_DRIVER_COMMAND_STRING:-}}"
  if [[ -n "${topology_provider}" && -z "${provider}" ]]; then
    provider="${topology_provider}"
  fi
  if [[ -z "${provider}" ]]; then
    provider="codex"
  fi
  if [[ "${topology_approved}" != "true" ]]; then
    echo "topology is not Kernel-approved" >&2
    exit 1
  fi
  if [[ -z "${topology_command}" ]]; then
    echo "topology launch command missing" >&2
    exit 2
  fi
  if [[ -n "${command_string}" && "${command_string}" != "${topology_command}" ]]; then
    echo "command-string must match approved topology launch command" >&2
    exit 2
  fi
  command_string="${topology_command}"

  local workspace_receipt_path workspace_dir envelope_path trace_path log_path started_at started_epoch
  local finished_at finished_epoch duration_sec scheduler_state status reason rc=0
  local child_pid="" interrupted=0
  workspace_receipt_path="$(KERNEL_RUN_ID="${run_id}" bash "${WORKSPACE_SCRIPT}" write)"
  workspace_dir="$(KERNEL_RUN_ID="${run_id}" bash "${WORKSPACE_SCRIPT}" path)"
  envelope_path="$(envelope_path_for "${run_id}")"
  trace_path="$(trace_path_for "${run_id}")"
  log_path="$(log_path_for "${run_id}")"
  started_at="$(utc_timestamp)"
  started_epoch="$(epoch_now)"
  if [[ -z "${trace_id}" ]]; then
    trace_id="ktrace:${run_id}:$(hash_text "${identity}|${started_at}")"
  fi

  local initial_trace
  initial_trace="$(
    jq -n \
      --arg run_id "${run_id}" \
      --arg trace_id "${trace_id}" \
      --arg identity "${identity}" \
      --arg project "${project}" \
      --arg issue_number "${issue_number}" \
      --arg task_key "${task_key}" \
      --arg provider "${provider}" \
      --arg topology_file "${topology_file}" \
      --arg command_string "${command_string}" \
      --arg continuity_owner "${continuity_owner}" \
      --arg started_at "${started_at}" \
      --arg workspace_dir "${workspace_dir}" \
      --arg workspace_receipt_path "${workspace_receipt_path}" \
      '{
        version: 1,
        run_id: $run_id,
        trace_id: $trace_id,
        identity: $identity,
        project: $project,
        issue_number: (if $issue_number == "" then null else ($issue_number | tonumber) end),
        task_key: $task_key,
        provider: $provider,
        topology_file: $topology_file,
        command_string: $command_string,
        continuity_owner: $continuity_owner,
        started_at: $started_at,
        workspace_dir: $workspace_dir,
        workspace_receipt_path: $workspace_receipt_path
      }'
  )"
  write_json_atomic "${trace_path}" "${initial_trace}"

  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" scheduler-state running "run-driver-start" "${workspace_receipt_path}" >/dev/null
  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" record-event kernel-runtime-run-driver start "${identity}; trace_id=${trace_id}" >/dev/null
  bash "${CLAIM_SCRIPT}" set-state --identity "${identity}" --run-id "${run_id}" --state running --reason "run-driver-start" --workspace-receipt-path "${workspace_receipt_path}" --envelope-path "${envelope_path}" --continuity-owner "${continuity_owner}" >/dev/null 2>&1 || true

  on_interrupt() {
    interrupted=1
    if [[ -n "${child_pid}" ]]; then
      kill "${child_pid}" 2>/dev/null || true
    fi
  }
  trap on_interrupt INT TERM

  {
    printf '[%s] run-driver start trace_id=%s provider=%s\n' "${started_at}" "${trace_id}" "${provider}"
    printf '[%s] command=%s\n' "${started_at}" "${command_string}"
  } >>"${log_path}"

  set +e
  bash -lc "${command_string}" >>"${log_path}" 2>&1 &
  child_pid=$!
  wait "${child_pid}"
  rc=$?
  set -e

  finished_at="$(utc_timestamp)"
  finished_epoch="$(epoch_now)"
  duration_sec="$(( finished_epoch - started_epoch ))"
  if [[ "${interrupted}" == "1" ]]; then
    scheduler_state="${KERNEL_RUN_DRIVER_INTERRUPT_STATE:-awaiting_human}"
    status="interrupted"
    reason="driver-interrupted"
  elif [[ "${rc}" == "0" ]]; then
    scheduler_state="terminal"
    status="completed"
    reason="command-succeeded"
  elif contains_exit_code "${KERNEL_RUN_DRIVER_AWAITING_HUMAN_EXIT_CODES:-77}" "${rc}"; then
    scheduler_state="awaiting_human"
    status="failed"
    reason="awaiting-human-exit-${rc}"
  elif contains_exit_code "${KERNEL_RUN_DRIVER_DEGRADED_EXIT_CODES:-65}" "${rc}"; then
    scheduler_state="continuity_degraded"
    status="failed"
    reason="continuity-degraded-exit-${rc}"
  elif contains_exit_code "${KERNEL_RUN_DRIVER_RETRY_EXIT_CODES:-75,85}" "${rc}"; then
    scheduler_state="retry_queued"
    status="failed"
    reason="retry-queued-exit-${rc}"
  else
    scheduler_state="retry_queued"
    status="failed"
    reason="command-exit-${rc}"
  fi

  local attestation_path=""
  if [[ "${status}" == "completed" ]]; then
    attestation_path="$(KERNEL_RUN_ID="${run_id}" bash "${ATTESTATION_SCRIPT}" issue "${provider}" success run-driver "run-driver" "trace=${trace_id};identity=${identity}" 2>/dev/null || true)"
    KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" record-provider "${provider}" success "run-driver" run-driver "${attestation_path}" >/dev/null
  else
    attestation_path="$(KERNEL_RUN_ID="${run_id}" bash "${ATTESTATION_SCRIPT}" issue "${provider}" failure run-driver "${reason}" "trace=${trace_id};identity=${identity}" 2>/dev/null || true)"
    KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" record-provider "${provider}" failure "${reason}" run-driver "${attestation_path}" >/dev/null
  fi
  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" scheduler-state "${scheduler_state}" "${reason}" "${workspace_receipt_path}" >/dev/null
  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" record-event kernel-runtime-run-driver finish "${identity}; state=${scheduler_state}; rc=${rc}" >/dev/null

  local envelope_json
  envelope_json="$(
    jq -n \
      --arg run_id "${run_id}" \
      --arg trace_id "${trace_id}" \
      --arg identity "${identity}" \
      --arg project "${project}" \
      --arg issue_number "${issue_number}" \
      --arg task_key "${task_key}" \
      --arg provider "${provider}" \
      --arg topology_file "${topology_file}" \
      --arg command_string "${command_string}" \
      --arg continuity_owner "${continuity_owner}" \
      --arg started_at "${started_at}" \
      --arg finished_at "${finished_at}" \
      --arg status "${status}" \
      --arg scheduler_state "${scheduler_state}" \
      --arg reason "${reason}" \
      --arg workspace_receipt_path "${workspace_receipt_path}" \
      --arg workspace_dir "${workspace_dir}" \
      --arg trace_path "${trace_path}" \
      --arg log_path "${log_path}" \
      --argjson exit_code "${rc}" \
      --argjson duration_sec "${duration_sec}" \
      --argjson topology_approved "$( [[ "${topology_approved}" == "true" ]] && printf 'true' || printf 'false' )" \
      --argjson evidence_links "${evidence_links_json}" \
      '{
        version: 1,
        run_id: $run_id,
        trace_id: $trace_id,
        identity: $identity,
        project: $project,
        issue_number: (if $issue_number == "" then null else ($issue_number | tonumber) end),
        task_key: $task_key,
        provider: $provider,
        topology_file: $topology_file,
        topology_approved: $topology_approved,
        command_string: $command_string,
        continuity_owner: $continuity_owner,
        started_at: $started_at,
        finished_at: $finished_at,
        duration_sec: $duration_sec,
        status: $status,
        scheduler_state: $scheduler_state,
        reason: $reason,
        exit_code: $exit_code,
        workspace_receipt_path: $workspace_receipt_path,
        workspace_dir: $workspace_dir,
        trace_path: $trace_path,
        log_path: $log_path,
        evidence_links: $evidence_links
      }'
  )"
  write_json_atomic "${envelope_path}" "${envelope_json}"
  bash "${CLAIM_SCRIPT}" set-state --identity "${identity}" --run-id "${run_id}" --state "${scheduler_state}" --reason "${reason}" --workspace-receipt-path "${workspace_receipt_path}" --envelope-path "${envelope_path}" --continuity-owner "${continuity_owner}" >/dev/null 2>&1 || true

  jq -n --arg envelope_path "${envelope_path}" --arg trace_path "${trace_path}" --arg log_path "${log_path}" --argjson envelope "${envelope_json}" \
    '{envelope_path: $envelope_path, trace_path: $trace_path, log_path: $log_path, envelope: $envelope}'

  if [[ "${status}" == "completed" ]]; then
    exit 0
  fi
  exit "${rc}"
}

cmd="${1:-help}"
shift || true
case "${cmd}" in
  path)
    cmd_path "$@"
    ;;
  run)
    cmd_run "$@"
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
