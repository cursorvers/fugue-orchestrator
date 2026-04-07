#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLAIM_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-claim.sh"
RECONCILER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-reconciler.sh"
RUN_DRIVER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-run-driver.sh"
STATUS_SURFACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-status-surface.sh"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"
STATE_ROOT="${KERNEL_SUBSTRATE_STATE_ROOT:-${ROOT_DIR}/.fugue/kernel-state}"
SCHEDULER_DIR="${KERNEL_RUNTIME_SCHEDULER_DIR:-${STATE_ROOT}/scheduler}"
SCHEDULER_STATE_PATH="${KERNEL_RUNTIME_SCHEDULER_STATE_PATH:-${SCHEDULER_DIR}/state.json}"
LOCK_DIR="${KERNEL_RUNTIME_SCHEDULER_LOCK_DIR:-${SCHEDULER_DIR}/.lock}"
LOCK_OWNER_FILE="${LOCK_DIR}/owner.pid"
LOCK_HELD=0
source "${ROOT_DIR}/scripts/lib/kernel-lock.sh"

trap cleanup_lock EXIT INT TERM

usage() {
  cat <<'EOF'
Usage:
  kernel-scheduler.sh once [--queue-file <path>] [--queue-json <json>]
  kernel-scheduler.sh daemon [--queue-file <path>] [--queue-json <json>]
  kernel-scheduler.sh status
EOF
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

epoch_now() {
  date -u '+%s'
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

write_scheduler_topology() {
  local run_id="${1:?run_id is required}"
  local identity="${2:?identity is required}"
  local project="${3:?project is required}"
  local issue_number="${4:-}"
  local task_key="${5:-}"
  local provider="${6:-codex}"
  local command_string="${7:?command_string is required}"
  local continuity_owner="${8:-local-primary}"
  local workspace_dir topology_path topology_json

  workspace_dir="$(KERNEL_RUN_ID="${run_id}" bash "${WORKSPACE_SCRIPT}" ensure)"
  topology_path="${workspace_dir}/traces/scheduler-topology.json"
  topology_json="$(
    jq -n \
      --arg generated_at "$(utc_timestamp)" \
      --arg run_id "${run_id}" \
      --arg identity "${identity}" \
      --arg project "${project}" \
      --arg issue_number "${issue_number}" \
      --arg task_key "${task_key}" \
      --arg provider "${provider}" \
      --arg command_string "${command_string}" \
      --arg continuity_owner "${continuity_owner}" \
      '{
        version: 1,
        generated_at: $generated_at,
        source: "kernel-scheduler",
        approved: true,
        ok_to_execute: true,
        run_id: $run_id,
        identity: $identity,
        project: $project,
        issue_number: (if $issue_number == "" then null else ($issue_number | tonumber) end),
        task_key: $task_key,
        continuity_owner: $continuity_owner,
        launch: {
          provider: $provider,
          command_string: $command_string
        }
      }'
  )"
  write_json_atomic "${topology_path}" "${topology_json}"
  printf '%s\n' "${topology_path}"
}

default_run_id_for_item() {
  local project="${1:-kernel-workspace}"
  local issue_number="${2:-}"
  local task_key="${3:-}"
  local ts slug
  ts="$(date -u '+%Y%m%dT%H%M%SZ')"
  slug="$(printf '%s' "${project}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
  if [[ -n "${issue_number}" ]]; then
    if [[ -n "${task_key}" ]]; then
      printf 'kernel:%s:issue-%s:%s:%s\n' "${slug}" "${issue_number}" "${task_key}" "${ts}"
    else
      printf 'kernel:%s:issue-%s:%s\n' "${slug}" "${issue_number}" "${ts}"
    fi
  elif [[ -n "${task_key}" ]]; then
    printf 'kernel:%s:task-%s:%s\n' "${slug}" "${task_key}" "${ts}"
  else
    printf 'kernel:%s:adhoc:%s\n' "${slug}" "${ts}"
  fi
}

load_queue_json() {
  local queue_file="${1:-}"
  local queue_json="${2:-}"
  local source_cmd="${KERNEL_SCHEDULER_SOURCE_CMD:-}"
  if [[ -n "${queue_json}" ]]; then
    printf '%s\n' "${queue_json}"
    return 0
  fi
  if [[ -n "${queue_file}" && -f "${queue_file}" ]]; then
    cat "${queue_file}"
    return 0
  fi
  if [[ -n "${KERNEL_SCHEDULER_QUEUE_JSON:-}" ]]; then
    printf '%s\n' "${KERNEL_SCHEDULER_QUEUE_JSON}"
    return 0
  fi
  if [[ -n "${KERNEL_SCHEDULER_QUEUE_FILE:-}" && -f "${KERNEL_SCHEDULER_QUEUE_FILE}" ]]; then
    cat "${KERNEL_SCHEDULER_QUEUE_FILE}"
    return 0
  fi
  if [[ -n "${source_cmd}" ]]; then
    bash -lc "${source_cmd}"
    return 0
  fi
  printf '{"items":[]}\n'
}

normalize_queue_json() {
  local raw_json="${1:-}"
  if [[ -z "${raw_json}" ]]; then
    raw_json='{"items":[]}'
  fi
  jq -c '
    def bool_or($fallback):
      if . == null then $fallback
      elif type == "boolean" then .
      elif type == "string" then
        ((ascii_downcase) as $v | ($v == "true" or $v == "1" or $v == "yes" or $v == "on"))
      else $fallback end;
    def inferred_authorized:
      (.authorized | bool_or(false))
      or ((.start_signal // "") | ascii_downcase | test("^/(vote|v)$|^tutti$|^workflow_dispatch$"))
      or ((.signals // []) | map((. // "") | tostring | ascii_downcase) | any(. == "/vote" or . == "/v" or . == "tutti" or . == "workflow_dispatch"));
    def inferred_terminal:
      (.terminal | bool_or(false))
      or ((.state // .issue_state // "") | ascii_downcase | test("closed|done|terminal|merged|cancelled"));
    def inferred_eligible:
      if .eligible == null then true else (.eligible | bool_or(true)) end;
    def derive_identity:
      if (.identity // "") != "" then .identity
      elif (.issue_number // "") != "" and (.task_key // "") != "" then "\(.project // "kernel-workspace")#\(.issue_number)/\(.task_key)"
      elif (.issue_number // "") != "" then "\(.project // "kernel-workspace")#\(.issue_number)"
      elif (.task_key // "") != "" then "\(.project // "kernel-workspace")/\(.task_key)"
      else "\(.project // "kernel-workspace")@\(.run_id // "unknown")" end;
    ((.items // .work_items // .issues // .) | if type == "array" then . else [] end)
    | map({
        identity: derive_identity,
        project: (.project // "kernel-workspace"),
        issue_number: (if (.issue_number // "") == "" then null else (.issue_number | tonumber) end),
        task_key: (.task_key // ""),
        run_id: (.run_id // ""),
        authorized: inferred_authorized,
        eligible: inferred_eligible,
        terminal: inferred_terminal,
        dispatchable: (
          if .dispatchable == null then (inferred_authorized and inferred_eligible and (inferred_terminal | not))
          else (.dispatchable | bool_or(false))
          end
        ),
        refresh_token: (.refresh_token // .refresh_requested_at // .updated_at // .etag // ""),
        refresh_requested_at: (.refresh_requested_at // .updated_at // ""),
        reason: (.reason // .blocking_reason // ""),
        continuity_owner: (.continuity_owner // "local-primary"),
        topology_path: (.topology_path // ""),
        command_string: (.command_string // .launch_command // ""),
        provider: (.provider // "codex")
      })
      | sort_by(.project, (.issue_number // 0), .identity)
  ' <<<"${raw_json}"
}

reconstruct_claim_queue() {
  local claims_json="${1:-[]}"
  jq -c '
    map(select((.claim_active // false) == true and ((.status // "") == "claimed" or (.status // "") == "retry_queued" or (.status // "") == "continuity_degraded")))
    | map({
        identity: .identity,
        project: (.project // "kernel-workspace"),
        issue_number: (.issue_number // null),
        task_key: (.task_key // ""),
        run_id: (.run_id // ""),
        authorized: true,
        eligible: ((.status // "") != "awaiting_human"),
        terminal: false,
        dispatchable: ((.status // "") != "awaiting_human"),
        refresh_token: (.refresh_token // ""),
        refresh_requested_at: (.updated_at // ""),
        reason: (.reason // ""),
        continuity_owner: (.continuity_owner // "local-primary"),
        topology_path: (.topology_path // ""),
        command_string: (.command_string // ""),
        provider: (.provider // "codex")
      })
  ' <<<"${claims_json}"
}

project_running_map() {
  local claims_json="${1:-[]}"
  jq -c '
    reduce map(select((.claim_active // false) == true and ((.status // "") == "running" or (.status // "") == "continuity_degraded")))[] as $claim
      ({}; .[$claim.project] = ($claim.identity))
  ' <<<"${claims_json}"
}

claim_by_identity() {
  local claims_json="${1:-[]}"
  local identity="${2:-}"
  jq -c --arg identity "${identity}" 'map(select(.identity == $identity)) | .[0] // {}' <<<"${claims_json}"
}

record_scheduler_state() {
  local queue_json="${1:-}"
  local claims_json="${2:-[]}"
  local launched_json="${3:-[]}"
  local deferred_json="${4:-[]}"
  local scheduler_json
  if [[ -z "${queue_json}" ]]; then
    queue_json='{"items":[]}'
  fi
  scheduler_json="$(
    jq -n \
      --arg generated_at "$(utc_timestamp)" \
      --argjson queue "${queue_json}" \
      --argjson claims "${claims_json}" \
      --argjson launched "${launched_json}" \
      --argjson deferred "${deferred_json}" \
      '{
        version: 1,
        generated_at: $generated_at,
        queue_count: ($queue | length),
        active_claims: ($claims | map(select((.claim_active // false) == true and (.status // "") != "terminal")) | length),
        launched: $launched,
        deferred: $deferred
      }'
  )"
  write_json_atomic "${SCHEDULER_STATE_PATH}" "${scheduler_json}"
}

launch_item() {
  local item_json="${1:?item is required}"
  local run_id identity project issue_number task_key provider topology_path command_string continuity_owner refresh_token reason
  local claim_result claim_json action workspace_receipt_path envelope_path driver_pid existing_pid existing_status
  identity="$(jq -r '.identity' <<<"${item_json}")"
  project="$(jq -r '.project // "kernel-workspace"' <<<"${item_json}")"
  issue_number="$(jq -r '.issue_number // ""' <<<"${item_json}")"
  task_key="$(jq -r '.task_key // ""' <<<"${item_json}")"
  run_id="$(jq -r '.run_id // ""' <<<"${item_json}")"
  provider="$(jq -r '.provider // "codex"' <<<"${item_json}")"
  topology_path="$(jq -r '.topology_path // ""' <<<"${item_json}")"
  command_string="$(jq -r '.command_string // ""' <<<"${item_json}")"
  continuity_owner="$(jq -r '.continuity_owner // "local-primary"' <<<"${item_json}")"
  refresh_token="$(jq -r '.refresh_token // ""' <<<"${item_json}")"
  reason="$(jq -r '.reason // "dispatchable"' <<<"${item_json}")"
  if [[ -z "${run_id}" ]]; then
    run_id="$(default_run_id_for_item "${project}" "${issue_number}" "${task_key}")"
  fi
  if [[ -z "${topology_path}" && -n "${command_string}" ]]; then
    topology_path="$(write_scheduler_topology "${run_id}" "${identity}" "${project}" "${issue_number}" "${task_key}" "${provider}" "${command_string}" "${continuity_owner}")"
  fi

  claim_result="$(bash "${CLAIM_SCRIPT}" claim \
    --identity "${identity}" \
    --project "${project}" \
    --issue-number "${issue_number}" \
    --task-key "${task_key}" \
    --run-id "${run_id}" \
    --source "kernel-scheduler" \
    --reason "${reason}" \
    --refresh-token "${refresh_token}" \
    --state claimed \
    --topology-path "${topology_path}" \
    --command-string "${command_string}" \
    --provider "${provider}" \
    --continuity-owner "${continuity_owner}")"
  action="$(jq -r '.action' <<<"${claim_result}")"
  claim_json="$(jq -c '.claim' <<<"${claim_result}")"
  existing_pid="$(jq -r '.run_driver_pid // ""' <<<"${claim_json}")"
  existing_status="$(jq -r '.status // ""' <<<"${claim_json}")"
  if [[ -n "${existing_pid}" && "${existing_pid}" =~ ^[0-9]+$ ]] && kill -0 "${existing_pid}" 2>/dev/null; then
    jq -n --arg action "already-running" --argjson claim "${claim_json}" '{action: $action, claim: $claim}'
    return 0
  fi
  if [[ -z "${command_string}" && -z "${topology_path}" ]]; then
    bash "${CLAIM_SCRIPT}" set-state --identity "${identity}" --state awaiting_human --reason "launch-metadata-missing" >/dev/null
    jq -n --arg action "awaiting-human" --argjson claim "$(bash "${CLAIM_SCRIPT}" status --identity "${identity}" | jq '.claim')" '{action: $action, claim: $claim}'
    return 0
  fi
  workspace_receipt_path="$(KERNEL_RUN_ID="${run_id}" bash "${WORKSPACE_SCRIPT}" write)"
  envelope_path="$(KERNEL_RUN_ID="${run_id}" bash "${RUN_DRIVER_SCRIPT}" path)"
  mkdir -p "${SCHEDULER_DIR}"
  env \
    KERNEL_RUN_ID="${run_id}" \
    KERNEL_PROJECT="${project}" \
    KERNEL_PURPOSE="issue-${issue_number:-task}" \
    bash "${RUN_DRIVER_SCRIPT}" run \
      --run-id "${run_id}" \
      --identity "${identity}" \
      --project "${project}" \
      --issue-number "${issue_number}" \
      --task-key "${task_key}" \
      --provider "${provider}" \
      --topology-file "${topology_path}" \
      --continuity-owner "${continuity_owner}" \
      >>"${SCHEDULER_DIR}/scheduler.log" 2>&1 &
  driver_pid=$!
  bash "${CLAIM_SCRIPT}" set-state --identity "${identity}" --state running --reason "scheduler-dispatch" --workspace-receipt-path "${workspace_receipt_path}" --envelope-path "${envelope_path}" --continuity-owner "${continuity_owner}" --run-driver-pid "${driver_pid}" >/dev/null
  jq -n \
    --arg action "${action}" \
    --arg run_id "${run_id}" \
    --arg envelope_path "${envelope_path}" \
    --arg workspace_receipt_path "${workspace_receipt_path}" \
    --argjson claim "$(bash "${CLAIM_SCRIPT}" status --identity "${identity}" | jq '.claim')" \
    '{action: $action, run_id: $run_id, envelope_path: $envelope_path, workspace_receipt_path: $workspace_receipt_path, claim: $claim}'
}

tick_once() {
  local queue_file="${1:-}"
  local queue_json="${2:-}"
  local raw_queue normalized_queue claims_json reconstructed_items merged_items running_projects
  local launched='[]' deferred='[]'

  raw_queue="$(load_queue_json "${queue_file}" "${queue_json}")"
  normalized_queue="$(normalize_queue_json "${raw_queue}")"
  claims_json="$(bash "${CLAIM_SCRIPT}" list)"
  reconstructed_items="$(reconstruct_claim_queue "${claims_json}")"
  merged_items="$(
    jq -s '
      add
      | unique_by(.identity)
      | sort_by(.project, (.issue_number // 0), .identity)
    ' <(printf '%s\n' "${normalized_queue}") <(printf '%s\n' "${reconstructed_items}")
  )"

  bash "${RECONCILER_SCRIPT}" reconcile --queue-json "{\"items\":${merged_items}}" >/dev/null
  claims_json="$(bash "${CLAIM_SCRIPT}" list)"
  running_projects="$(project_running_map "${claims_json}")"

  while IFS= read -r item_json; do
    [[ -n "${item_json}" ]] || continue
    local identity project dispatchable terminal eligible existing_claim busy_identity launch_result action
    identity="$(jq -r '.identity' <<<"${item_json}")"
    project="$(jq -r '.project' <<<"${item_json}")"
    dispatchable="$(jq -r '.dispatchable // false' <<<"${item_json}")"
    terminal="$(jq -r '.terminal // false' <<<"${item_json}")"
    eligible="$(jq -r '.eligible // true' <<<"${item_json}")"
    if [[ "${terminal}" == "true" || "${eligible}" != "true" || "${dispatchable}" != "true" ]]; then
      continue
    fi
    existing_claim="$(claim_by_identity "${claims_json}" "${identity}")"
    if [[ "$(jq -r '.claim_active // false' <<<"${existing_claim}")" == "true" ]]; then
      local pid status
      pid="$(jq -r '.run_driver_pid // ""' <<<"${existing_claim}")"
      status="$(jq -r '.status // ""' <<<"${existing_claim}")"
      if [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
        continue
      fi
      if [[ "${status}" == "running" || "${status}" == "continuity_degraded" ]]; then
        continue
      fi
    fi
    busy_identity="$(jq -r --arg project "${project}" '.[$project] // ""' <<<"${running_projects}")"
    if [[ -n "${busy_identity}" && "${busy_identity}" != "${identity}" ]]; then
      bash "${CLAIM_SCRIPT}" claim \
        --identity "${identity}" \
        --project "${project}" \
        --issue-number "$(jq -r '.issue_number // ""' <<<"${item_json}")" \
        --task-key "$(jq -r '.task_key // ""' <<<"${item_json}")" \
        --run-id "$(jq -r '.run_id // ""' <<<"${item_json}")" \
        --source "kernel-scheduler" \
        --reason "project-concurrency-bound" \
        --refresh-token "$(jq -r '.refresh_token // ""' <<<"${item_json}")" \
        --state retry_queued \
        --topology-path "$(jq -r '.topology_path // ""' <<<"${item_json}")" \
        --command-string "$(jq -r '.command_string // ""' <<<"${item_json}")" \
        --provider "$(jq -r '.provider // "codex"' <<<"${item_json}")" \
        --continuity-owner "$(jq -r '.continuity_owner // "local-primary"' <<<"${item_json}")" >/dev/null
      deferred="$(jq -c --argjson item "${item_json}" '. + [$item + {deferred_reason:"project-concurrency-bound"}]' <<<"${deferred}")"
      continue
    fi

    launch_result="$(launch_item "${item_json}")"
    action="$(jq -r '.action // ""' <<<"${launch_result}")"
    launched="$(jq -c --argjson item "${launch_result}" '. + [$item]' <<<"${launched}")"
    if [[ "${action}" != "already-running" ]]; then
      running_projects="$(jq -c --arg project "${project}" --arg identity "${identity}" '. + {($project): $identity}' <<<"${running_projects}")"
    fi
    claims_json="$(bash "${CLAIM_SCRIPT}" list)"
  done < <(jq -c '.[]' <<<"${merged_items}")

  record_scheduler_state "${merged_items}" "${claims_json}" "${launched}" "${deferred}"
  bash "${STATUS_SURFACE_SCRIPT}" snapshot --queue-json "{\"items\":${merged_items}}" --write >/dev/null
  jq -n --arg generated_at "$(utc_timestamp)" --argjson launched "${launched}" --argjson deferred "${deferred}" \
    '{generated_at: $generated_at, launched: $launched, deferred: $deferred}'
}

cmd_status() {
  if [[ ! -f "${SCHEDULER_STATE_PATH}" ]]; then
    jq -n --arg status_path "${SCHEDULER_STATE_PATH}" '{present:false,status_path:$status_path}'
    return 1
  fi
  cat "${SCHEDULER_STATE_PATH}"
}

cmd_once() {
  local queue_file="" queue_json=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --queue-file) queue_file="${2:-}"; shift 2 ;;
      --queue-json) queue_json="${2:-}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  acquire_lock "kernel scheduler"
  tick_once "${queue_file}" "${queue_json}"
  release_lock
}

cmd_daemon() {
  local queue_file="" queue_json="" interval_sec="${KERNEL_SCHEDULER_INTERVAL_SEC:-60}"
  local stop_file="${KERNEL_SCHEDULER_STOP_FILE:-${SCHEDULER_DIR}/stop}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --queue-file) queue_file="${2:-}"; shift 2 ;;
      --queue-json) queue_json="${2:-}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  [[ "${interval_sec}" =~ ^[0-9]+$ ]] || interval_sec=60

  mkdir -p "${SCHEDULER_DIR}"
  while true; do
    if [[ -f "${stop_file}" ]]; then
      rm -f "${stop_file}"
      exit 0
    fi
    acquire_lock "kernel scheduler"
    tick_once "${queue_file}" "${queue_json}" >/dev/null
    release_lock
    sleep "${interval_sec}"
  done
}

cmd="${1:-help}"
shift || true
case "${cmd}" in
  once)
    cmd_once "$@"
    ;;
  daemon)
    cmd_daemon "$@"
    ;;
  status)
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
