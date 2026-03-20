#!/usr/bin/env bash
set -euo pipefail

LEDGER_FILE="${KERNEL_RUNTIME_LEDGER_FILE:-$HOME/.config/kernel/runtime-ledger.json}"
LOCK_DIR="${KERNEL_RUNTIME_LEDGER_LOCK_DIR:-${LEDGER_FILE}.lock}"
LOCK_OWNER_FILE="${LOCK_DIR}/owner.pid"
LOCK_HELD=0

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
  kernel-runtime-ledger.sh record-provider <provider> [success|failure] [note]
  kernel-runtime-ledger.sh record-event <actor> <command> [summary]
EOF
}

compact_script_path() {
  local root_dir
  root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  printf '%s\n' "${root_dir}/scripts/lib/kernel-compact-artifact.sh"
}

maybe_auto_compact() {
  local event="${1:-status_changed}"
  local summary="${2:-}"
  local script
  script="$(compact_script_path)"
  [[ -f "${script}" ]] || return 0
  KERNEL_RUN_ID="${RUN_ID}" bash "${script}" update "${event}" "${summary}" >/dev/null 2>&1 || true
}

cleanup_lock() {
  if [[ "${LOCK_HELD}" == "1" ]]; then
    rm -rf "${LOCK_DIR}" 2>/dev/null || true
    LOCK_HELD=0
  fi
}

trap cleanup_lock EXIT INT TERM

stale_lock_owner_dead() {
  [[ -f "${LOCK_OWNER_FILE}" ]] || return 1
  local owner_pid=""
  owner_pid="$(cat "${LOCK_OWNER_FILE}" 2>/dev/null || true)"
  [[ -n "${owner_pid}" ]] || return 1
  kill -0 "${owner_pid}" 2>/dev/null && return 1
  return 0
}

acquire_lock() {
  local attempts=0
  mkdir -p "$(dirname "${LOCK_DIR}")"
  while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
    if stale_lock_owner_dead; then
      rm -rf "${LOCK_DIR}" 2>/dev/null || true
      continue
    fi
    attempts=$((attempts + 1))
    if (( attempts >= 200 )); then
      echo "runtime ledger lock timeout: ${LOCK_DIR}" >&2
      exit 1
    fi
    sleep 0.05
  done
  printf '%s\n' "$$" >"${LOCK_OWNER_FILE}"
  LOCK_HELD=1
}

release_lock() {
  cleanup_lock
}

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
  local state reason receipt updated_at
  state="$(jq -r --arg run_id "${run_id}" '.runs[$run_id].state // "unknown"' "${LEDGER_FILE}")"
  reason="$(jq -r --arg run_id "${run_id}" '.runs[$run_id].reason // ""' "${LEDGER_FILE}")"
  receipt="$(jq -r --arg run_id "${run_id}" '.runs[$run_id].receipt_path // ""' "${LEDGER_FILE}")"
  updated_at="$(jq -r --arg run_id "${run_id}" '.runs[$run_id].updated_at // ""' "${LEDGER_FILE}")"
  printf 'runtime ledger:\n'
  printf '  - run id: %s\n' "${run_id}"
  printf '  - state: %s\n' "${state}"
  printf '  - reason: %s\n' "${reason}"
  printf '  - receipt path: %s\n' "${receipt}"
  printf '  - updated at: %s\n' "${updated_at}"
  jq -r --arg run_id "${run_id}" '
    (.runs[$run_id].provider_usage // {}) as $usage
    | ($usage | to_entries | map(select(.value.success_count > 0) | .key) | join(",")) as $successes
    | ($usage | to_entries | map("\(.key): success \(.value.success_count // 0), failure \(.value.failure_count // 0)") | .[])?
    | "  - successful providers: " + (if $successes == "" then "none" else $successes end),
      .
  ' "${LEDGER_FILE}"
  jq -r --arg run_id "${run_id}" '
    (.runs[$run_id].events // []) as $events
    | "  - recent events: " + (if ($events | length) == 0 then "none" else (($events | length) | tostring) end)
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

  acquire_lock
  tmp_file="${LEDGER_FILE}.tmp.$$.$RANDOM"
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

  acquire_lock
  tmp_file="${LEDGER_FILE}.tmp.$$.$RANDOM"
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

  acquire_lock
  tmp_file="${LEDGER_FILE}.tmp.$$.$RANDOM"
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
