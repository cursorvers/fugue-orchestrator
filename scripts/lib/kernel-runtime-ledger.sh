#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
LEDGER_FILE="${KERNEL_RUNTIME_LEDGER_FILE:-$(bash "${STATE_PATH_SCRIPT}" runtime-ledger-file)}"
LOCK_DIR="${KERNEL_RUNTIME_LEDGER_LOCK_DIR:-${LEDGER_FILE}.lock}"
LOCK_OWNER_FILE="${LOCK_DIR}/owner.pid"
LOCK_HELD=0
source "${SCRIPT_DIR}/kernel-lock.sh"

default_run_id() {
  if [[ -n "${KERNEL_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_RUN_ID}"
    return 0
  fi
  if [[ -n "${KERNEL_OPTIONAL_LANE_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_OPTIONAL_LANE_RUN_ID}"
    return 0
  fi
  if [[ -n "${KERNEL_GLM_RUN_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_GLM_RUN_ID}"
    return 0
  fi
  printf 'unknown-run\n'
}

RUN_ID="$(default_run_id)"

usage() {
  cat <<'EOF'
Usage:
  kernel-runtime-ledger.sh status [run_id]
  kernel-runtime-ledger.sh transition <state> [reason] [receipt_path]
  kernel-runtime-ledger.sh scheduler-state <claimed|running|retry_queued|continuity_degraded|awaiting_human|terminal> [reason] [workspace_receipt_path]
  kernel-runtime-ledger.sh record-provider <provider> [success|failure] [note]
  kernel-runtime-ledger.sh record-event <actor> <command> [summary]
EOF
}

derive_lifecycle_state() {
  local state="${1:-unknown}"
  local scheduler_state="${2:-unknown}"
  if [[ "${state}" == "degraded-allowed" ]]; then
    case "${scheduler_state}" in
      running|continuity_degraded)
        printf 'live-continuity-degraded\n'
        return 0
        ;;
    esac
  fi
  case "${scheduler_state}" in
    running)
      printf 'live-running\n'
      ;;
    continuity_degraded)
      printf 'live-continuity-degraded\n'
      ;;
    terminal)
      printf 'terminal\n'
      ;;
    awaiting_human)
      printf 'awaiting-human\n'
      ;;
    retry_queued)
      printf 'retry-queued\n'
      ;;
    claimed|"")
      case "${state}" in
        healthy|degraded-allowed)
          printf 'bootstrap-valid\n'
          ;;
        *)
          printf 'blocked\n'
          ;;
      esac
      ;;
    *)
      case "${state}" in
        healthy|degraded-allowed)
          printf 'bootstrap-valid\n'
          ;;
        *)
          printf 'blocked\n'
          ;;
      esac
      ;;
  esac
}

compact_script_path() {
  printf '%s\n' "${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
}

maybe_auto_compact() {
  local event="${1:-status_changed}"
  local summary="${2:-}"
  local script
  [[ "${KERNEL_RUNTIME_LEDGER_AUTO_COMPACT:-true}" == "true" ]] || return 0
  script="$(compact_script_path)"
  [[ -f "${script}" ]] || return 0
  KERNEL_RUN_ID="${RUN_ID}" bash "${script}" update "${event}" "${summary}" >/dev/null 2>&1 || true
}

trap cleanup_lock EXIT INT TERM

ensure_ledger() {
  mkdir -p "$(dirname "${LEDGER_FILE}")"
  if [[ ! -f "${LEDGER_FILE}" ]]; then
    printf '{\n  "version": 1,\n  "runs": {}\n}\n' >"${LEDGER_FILE}"
  fi
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

cmd_status() {
  ensure_ledger
  local run_id="${1:-${RUN_ID}}"
  local state scheduler_state lifecycle_state
  state="$(jq -r --arg run_id "${run_id}" '.runs[$run_id].state // "unknown"' "${LEDGER_FILE}")"
  scheduler_state="$(jq -r --arg run_id "${run_id}" '.runs[$run_id].scheduler_state // "unknown"' "${LEDGER_FILE}")"
  lifecycle_state="$(derive_lifecycle_state "${state}" "${scheduler_state}")"
  printf 'runtime ledger:\n'
  printf '  - run id: %s\n' "${run_id}"
  printf '  - lifecycle state: %s\n' "${lifecycle_state}"
  jq -r --arg run_id "${run_id}" '
    (.runs[$run_id] // {}) as $run |
    ($run.provider_usage // {}) as $usage |
    ($usage | to_entries | map(select(.value.success_count > 0) | .key) | join(",")) as $successes |
    ($run.events // []) as $events |
    "  - state: \($run.state // "unknown")",
    "  - reason: \($run.reason // "")",
    "  - receipt path: \($run.receipt_path // "")",
    "  - scheduler state: \($run.scheduler_state // "unknown")",
    "  - scheduler reason: \($run.scheduler_reason // "")",
    "  - workspace receipt path: \($run.workspace_receipt_path // "")",
    "  - updated at: \($run.updated_at // "")",
    (if ($usage | length) > 0 then
      "  - successful providers: \(if $successes == "" then "none" else $successes end)",
      ($usage | to_entries[] | "  - \(.key): success \(.value.success_count // 0), failure \(.value.failure_count // 0)")
    else
      "  - successful providers: none"
    end),
    "  - recent events: \(if ($events | length) == 0 then "none" else (($events | length) | tostring) end)"
  ' "${LEDGER_FILE}"
}

cmd_transition() {
  ensure_ledger
  local state="${1:-}"
  local reason="${2:-manual}"
  local receipt_path="${3:-}"
  local tmp_file
  if [[ -z "${state}" ]]; then
    echo "state is required" >&2
    exit 2
  fi

  acquire_lock "runtime ledger"
  tmp_file="$(umask 077 && mktemp "${LEDGER_FILE}.tmp.XXXXXXXXXX")"
  jq \
    --arg run_id "${RUN_ID}" \
    --arg state "${state}" \
    --arg reason "${reason}" \
    --arg receipt_path "${receipt_path}" \
    --arg updated_at "$(utc_timestamp)" \
    '
      .runs[$run_id] = ((.runs[$run_id] // {}) + {
        state: $state,
        reason: $reason,
        updated_at: $updated_at
      } + (if $receipt_path == "" then {} else {receipt_path: $receipt_path} end))
    ' "${LEDGER_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${LEDGER_FILE}"
  release_lock
  maybe_auto_compact "status_changed" "state=${state}; reason=${reason}"
  cmd_status "${RUN_ID}"
}

cmd_scheduler_state() {
  ensure_ledger
  local scheduler_state="${1:-}"
  local reason="${2:-runtime-loop}"
  local workspace_receipt_path="${3:-}"
  local tmp_file

  case "${scheduler_state}" in
    claimed|running|retry_queued|continuity_degraded|awaiting_human|terminal)
      ;;
    *)
      echo "scheduler state must be one of claimed, running, retry_queued, continuity_degraded, awaiting_human, terminal" >&2
      exit 2
      ;;
  esac

  acquire_lock "runtime ledger"
  tmp_file="$(umask 077 && mktemp "${LEDGER_FILE}.tmp.XXXXXXXXXX")"
  jq \
    --arg run_id "${RUN_ID}" \
    --arg scheduler_state "${scheduler_state}" \
    --arg reason "${reason}" \
    --arg workspace_receipt_path "${workspace_receipt_path}" \
    --arg updated_at "$(utc_timestamp)" \
    '
      .runs[$run_id] = ((.runs[$run_id] // {}) + {
        scheduler_state: $scheduler_state,
        scheduler_reason: $reason,
        updated_at: $updated_at
      } + (if $workspace_receipt_path == "" then {} else {workspace_receipt_path: $workspace_receipt_path} end))
    ' "${LEDGER_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${LEDGER_FILE}"
  release_lock
  maybe_auto_compact "scheduler_state_changed" "scheduler_state=${scheduler_state}; reason=${reason}"
  cmd_status "${RUN_ID}"
}

cmd_record_provider() {
  ensure_ledger
  local provider="${1:-}"
  local result="${2:-success}"
  local note="${3:-provider-exec}"
  local success_inc=0
  local failure_inc=0
  local tmp_file

  if [[ -z "${provider}" ]]; then
    echo "provider is required" >&2
    exit 2
  fi

  case "${result}" in
    success) success_inc=1 ;;
    failure) failure_inc=1 ;;
    *)
      echo "result must be success or failure" >&2
      exit 2
      ;;
  esac

  acquire_lock "runtime ledger"
  tmp_file="$(umask 077 && mktemp "${LEDGER_FILE}.tmp.XXXXXXXXXX")"
  jq \
    --arg run_id "${RUN_ID}" \
    --arg provider "${provider}" \
    --arg note "${note}" \
    --arg updated_at "$(utc_timestamp)" \
    --arg result "${result}" \
    --argjson success_inc "${success_inc}" \
    --argjson failure_inc "${failure_inc}" \
    '
      .runs[$run_id] = ((.runs[$run_id] // {}) + {
        updated_at: $updated_at
      })
      | .runs[$run_id].provider_usage = ((.runs[$run_id].provider_usage // {}) + {
          ($provider): ((.runs[$run_id].provider_usage[$provider] // {
            success_count: 0,
            failure_count: 0
          }) + {
            success_count: ((.runs[$run_id].provider_usage[$provider].success_count // 0) + $success_inc),
            failure_count: ((.runs[$run_id].provider_usage[$provider].failure_count // 0) + $failure_inc),
            last_result: $result,
            last_note: $note,
            last_at: $updated_at
          })
        })
    ' "${LEDGER_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${LEDGER_FILE}"
  release_lock
  cmd_status "${RUN_ID}"
}

cmd_record_event() {
  ensure_ledger
  local actor="${1:-}"
  local command_name="${2:-}"
  local summary="${3:-}"
  local host node_role tmp_file

  if [[ -z "${actor}" || -z "${command_name}" ]]; then
    echo "actor and command are required" >&2
    exit 2
  fi

  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown-host')"
  node_role="${KERNEL_NODE_ROLE:-unknown}"

  acquire_lock "runtime ledger"
  tmp_file="$(umask 077 && mktemp "${LEDGER_FILE}.tmp.XXXXXXXXXX")"
  jq \
    --arg run_id "${RUN_ID}" \
    --arg actor "${actor}" \
    --arg command_name "${command_name}" \
    --arg summary "${summary}" \
    --arg host "${host}" \
    --arg node_role "${node_role}" \
    --arg at "$(utc_timestamp)" \
    '
      .runs[$run_id] = ((.runs[$run_id] // {}) + {
        updated_at: $at
      })
      | .runs[$run_id].events = (
          ((.runs[$run_id].events // []) + [{
            at: $at,
            actor: $actor,
            command: $command_name,
            summary: $summary,
            host: $host,
            node_role: $node_role
          }])[-20:]
        )
    ' "${LEDGER_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${LEDGER_FILE}"
  release_lock
}

cmd="${1:-status}"
case "${cmd}" in
  status)
    shift || true
    cmd_status "$@"
    ;;
  transition)
    shift || true
    cmd_transition "$@"
    ;;
  scheduler-state)
    shift || true
    cmd_scheduler_state "$@"
    ;;
  record-provider)
    shift || true
    cmd_record_provider "$@"
    ;;
  record-event)
    shift || true
    cmd_record_event "$@"
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
