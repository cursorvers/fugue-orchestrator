#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLAIM_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-claim.sh"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
STATE_PATHS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
STATE_ROOT="${KERNEL_SUBSTRATE_STATE_ROOT:-$(bash "${STATE_PATHS_SCRIPT}" state-root)}"
COMPACT_DIR="${KERNEL_COMPACT_DIR:-$(bash "${STATE_PATHS_SCRIPT}" compact-dir)}"
TMUX_BIN="${TMUX_BIN:-tmux}"

usage() {
  cat <<'EOF'
Usage:
  kernel-runtime-reconciler.sh reconcile [options]

Options:
  --queue-file <path>
  --queue-json <json>
  --ttl-seconds <seconds>
  --archive-ttl-seconds <seconds>
EOF
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

epoch_now() {
  date -u '+%s'
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
  if [[ -n "${KERNEL_SCHEDULER_QUEUE_FILE:-}" && -f "${KERNEL_SCHEDULER_QUEUE_FILE}" ]]; then
    cat "${KERNEL_SCHEDULER_QUEUE_FILE}"
    return 0
  fi
  if [[ -n "${KERNEL_SCHEDULER_QUEUE_JSON:-}" ]]; then
    printf '%s\n' "${KERNEL_SCHEDULER_QUEUE_JSON}"
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
    ((.items // .work_items // .issues // .claims // .) | if type == "array" then . else [] end)
    | map({
        identity: derive_identity,
        project: (.project // "kernel-workspace"),
        issue_number: (if (.issue_number // "") == "" then null else (.issue_number | tonumber) end),
        task_key: (.task_key // ""),
        run_id: (.run_id // ""),
        authorized: inferred_authorized,
        eligible: inferred_eligible,
        terminal: inferred_terminal,
        refresh_token: (.refresh_token // .refresh_requested_at // .updated_at // .etag // ""),
        refresh_requested_at: (.refresh_requested_at // .updated_at // ""),
        reason: (.reason // .status_reason // .blocking_reason // ""),
        continuity_owner: (.continuity_owner // "local-primary"),
        topology_path: (.topology_path // ""),
        command_string: (.command_string // .launch_command // ""),
        provider: (.provider // ""),
        stop_reason: (.stop_reason // .reason // ""),
        dispatchable: (
          if .dispatchable == null then (inferred_authorized and inferred_eligible and (inferred_terminal | not))
          else ((.dispatchable | bool_or(false)) and inferred_authorized and inferred_eligible and (inferred_terminal | not))
          end
        )
      })
  ' <<<"${raw_json}"
}

reason_to_state() {
  local fallback="${1:-retry_queued}"
  local reason="${2:-}"
  local lower
  lower="$(printf '%s' "${reason}" | tr '[:upper:]' '[:lower:]')"
  if [[ "${lower}" == *"human"* || "${lower}" == *"approval"* || "${lower}" == *"manual"* || "${lower}" == *"auth"* ]]; then
    printf 'awaiting_human\n'
  else
    printf '%s\n' "${fallback}"
  fi
}

workspace_stop_file_for_claim() {
  local run_id="${1:-}"
  [[ -n "${run_id}" ]] || return 1
  local workspace_dir
  workspace_dir="$(KERNEL_RUN_ID="${run_id}" bash "${WORKSPACE_SCRIPT}" path 2>/dev/null || true)"
  [[ -n "${workspace_dir}" ]] || return 1
  printf '%s/stop\n' "${workspace_dir}"
}

workspace_receipt_for_run() {
  local run_id="${1:-}"
  [[ -n "${run_id}" ]] || return 1
  KERNEL_RUN_ID="${run_id}" bash "${WORKSPACE_SCRIPT}" receipt-path "${run_id}" 2>/dev/null || true
}

compact_path_for_run() {
  local run_id="${1:-}"
  [[ -n "${run_id}" ]] || return 1
  KERNEL_RUN_ID="${run_id}" bash "${COMPACT_SCRIPT}" path "${run_id}" 2>/dev/null || true
}

epoch_from_iso8601() {
  local value="${1:-}"
  [[ -n "${value}" ]] || return 1
  python3 - "${value}" <<'PY'
import datetime
import sys

try:
    dt = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ")
except ValueError:
    raise SystemExit(1)
print(int(dt.replace(tzinfo=datetime.timezone.utc).timestamp()))
PY
}

compact_updated_epoch() {
  local compact_path="${1:-}"
  local updated_at
  [[ -n "${compact_path}" && -f "${compact_path}" ]] || return 1
  updated_at="$(jq -r '.updated_at // ""' "${compact_path}" 2>/dev/null || true)"
  epoch_from_iso8601 "${updated_at}" 2>/dev/null || return 1
}

tmux_session_exists() {
  local session_name="${1:-}"
  local tmux_bin="${TMUX_BIN:-tmux}"
  [[ -n "${session_name}" ]] || return 1
  command -v "${tmux_bin}" >/dev/null 2>&1 || return 2
  "${tmux_bin}" has-session -t "=${session_name}" 2>/dev/null
  return $?
}

compact_path_for_claim() {
  local claim_json="${1:-}"
  local compact_path run_id workspace_receipt_path
  compact_path="$(jq -r '.compact_artifact_path // ""' <<<"${claim_json}")"
  if [[ -n "${compact_path}" ]]; then
    [[ -f "${compact_path}" ]] && {
      printf '%s\n' "${compact_path}"
      return 0
    }
  fi
  workspace_receipt_path="$(jq -r '.workspace_receipt_path // ""' <<<"${claim_json}")"
  if [[ -n "${workspace_receipt_path}" && -f "${workspace_receipt_path}" ]]; then
    compact_path="$(jq -r '.compact_artifact_path // ""' "${workspace_receipt_path}" 2>/dev/null || true)"
    [[ -n "${compact_path}" && -f "${compact_path}" ]] && {
      printf '%s\n' "${compact_path}"
      return 0
    }
  fi
  run_id="$(jq -r '.run_id // ""' <<<"${claim_json}")"
  if [[ -n "${run_id}" ]]; then
    compact_path="$(compact_path_for_run "${run_id}")"
    [[ -f "${compact_path}" ]] && {
      printf '%s\n' "${compact_path}"
      return 0
    }
  fi
  return 1
}

is_stale_claim_candidate() {
  local claim_json="${1:-}"
  local ttl_seconds="${2:-3600}"
  local now updated_epoch updated_at_age status claim_active pid compact_path compact_tmux_session compact_updated tmux_status

  status="$(jq -r '.status // ""' <<<"${claim_json}")"
  claim_active="$(jq -r '.claim_active // false' <<<"${claim_json}")"
  updated_epoch="$(jq -r '.updated_at_epoch // 0' <<<"${claim_json}")"
  pid="$(jq -r '.run_driver_pid // ""' <<<"${claim_json}")"

  if [[ "${claim_active}" != "true" || "${status}" == "terminal" ]]; then
    return 1
  fi
  now="$(epoch_now)"
  [[ "${updated_epoch}" =~ ^[0-9]+$ ]] || updated_epoch=0
  updated_at_age=$(( now - updated_epoch ))
  if (( updated_at_age < ttl_seconds )); then
    return 1
  fi
  if [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
    return 1
  fi

  compact_path="$(compact_path_for_claim "${claim_json}" || true)"
  if [[ -n "${compact_path}" ]]; then
    compact_tmux_session="$(jq -r '.tmux_session // ""' "${compact_path}" 2>/dev/null || true)"
    if [[ -n "${compact_tmux_session}" ]]; then
      tmux_session_exists "${compact_tmux_session}"
      tmux_status=$?
      if (( tmux_status == 0 )); then
        return 1
      fi
      if (( tmux_status > 1 )); then
        return 1
      fi
    fi
    compact_updated="$(compact_updated_epoch "${compact_path}" || true)"
    if [[ ! "${compact_updated}" =~ ^[0-9]+$ ]]; then
      return 1
    fi
    if (( now - compact_updated < ttl_seconds )); then
      return 1
    fi
  fi

  return 0
}

archive_root() {
  printf '%s/archive/runtime-reconciler\n' "${STATE_ROOT}"
}

archive_file_if_present() {
  local path="${1:-}"
  local run_id="${2:-}"
  local category="${3:-misc}"
  local archive_dir archive_path base safe_run
  [[ -n "${path}" && -f "${path}" ]] || return 1
  safe_run="$(printf '%s' "${run_id:-unknown-run}" | tr '/:' '__')"
  base="$(basename "${path}")"
  archive_dir="$(archive_root)/${category}"
  mkdir -p "${archive_dir}"
  archive_path="${archive_dir}/${safe_run}--${base}"
  if [[ -e "${archive_path}" ]]; then
    archive_path="${archive_dir}/${safe_run}--$(date -u '+%Y%m%dT%H%M%SZ')--${base}"
  fi
  mv "${path}" "${archive_path}"
  printf '%s\n' "${archive_path}"
}

archive_stale_artifacts_for_run() {
  local run_id="${1:-}"
  local workspace_receipt_path="${2:-}"
  local envelope_path="${3:-}"
  local compact_path_override="${4:-}"
  local compact_path archived=0
  [[ -n "${run_id}" ]] || {
    printf '0\n'
    return 0
  }
  if [[ -z "${workspace_receipt_path}" ]]; then
    workspace_receipt_path="$(workspace_receipt_for_run "${run_id}" || true)"
  fi
  if [[ -n "${workspace_receipt_path}" && -f "${workspace_receipt_path}" ]]; then
    compact_path="$(jq -r '.compact_artifact_path // ""' "${workspace_receipt_path}" 2>/dev/null || true)"
  fi
  [[ -n "${compact_path_override}" ]] && compact_path="${compact_path_override}"
  [[ -n "${compact_path:-}" ]] || compact_path="$(compact_path_for_run "${run_id}" || true)"
  if archive_file_if_present "${compact_path}" "${run_id}" compact >/dev/null 2>&1; then
    archived=$((archived + 1))
  fi
  if archive_file_if_present "${workspace_receipt_path}" "${run_id}" workspace-receipts >/dev/null 2>&1; then
    archived=$((archived + 1))
  fi
  if archive_file_if_present "${envelope_path}" "${run_id}" envelopes >/dev/null 2>&1; then
    archived=$((archived + 1))
  fi
  printf '%s\n' "${archived}"
}

compact_files() {
  mkdir -p "${COMPACT_DIR}"
  find "${COMPACT_DIR}" -maxdepth 1 -type f -name '*.json' | sort
}

kill_pid_if_live() {
  local pid="${1:-}"
  if [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}" 2>/dev/null || true
    return 0
  fi
  return 1
}

cmd_reconcile() {
  local queue_file="" queue_json="" ttl_seconds="${KERNEL_RUNTIME_RECONCILE_STALE_TTL_SEC:-3600}"
  local archive_ttl_seconds="${KERNEL_RUNTIME_RECONCILE_ARCHIVE_TTL_SEC:-${KERNEL_RUNTIME_RECONCILE_STALE_TTL_SEC:-3600}}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --queue-file) queue_file="${2:-}"; shift 2 ;;
      --queue-json) queue_json="${2:-}"; shift 2 ;;
      --ttl-seconds) ttl_seconds="${2:-}"; shift 2 ;;
      --archive-ttl-seconds) archive_ttl_seconds="${2:-}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  [[ "${ttl_seconds}" =~ ^[0-9]+$ ]] || ttl_seconds=3600
  [[ "${archive_ttl_seconds}" =~ ^[0-9]+$ ]] || archive_ttl_seconds="${ttl_seconds}"

  local live_queue_raw live_queue claims_json scanned=0 stopped=0 updated=0 released=0 continued=0 archived_files=0 orphan_archived=0
  local archived_runs_json='[]'
  live_queue_raw="$(load_queue_json "${queue_file}" "${queue_json}")"
  live_queue="$(normalize_queue_json "${live_queue_raw}")"
  bash "${CLAIM_SCRIPT}" rebuild --ttl-seconds "${ttl_seconds}" >/dev/null
  claims_json="$(bash "${CLAIM_SCRIPT}" list)"

  while IFS= read -r claim_json; do
    [[ -n "${claim_json}" ]] || continue
    scanned=$((scanned + 1))
    local identity run_id status pid updated_epoch envelope_path issue_item issue_terminal issue_eligible issue_reason live_pid=false stop_file target_state claim_active archived_now stop_reason
    identity="$(jq -r '.identity // ""' <<<"${claim_json}")"
    run_id="$(jq -r '.run_id // ""' <<<"${claim_json}")"
    status="$(jq -r '.status // ""' <<<"${claim_json}")"
    claim_active="$(jq -r '.claim_active // false' <<<"${claim_json}")"
    stop_reason="$(jq -r '.stop_reason // ""' <<<"${claim_json}")"
    pid="$(jq -r '.run_driver_pid // ""' <<<"${claim_json}")"
    updated_epoch="$(jq -r '.updated_at_epoch // 0' <<<"${claim_json}")"
    envelope_path="$(jq -r '.envelope_path // ""' <<<"${claim_json}")"
    if [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
      live_pid=true
    fi

    issue_item="$(jq -c --arg identity "${identity}" 'map(select(.identity == $identity)) | .[0] // {}' <<<"${live_queue}")"
    issue_terminal="$(jq -r 'if .terminal == null then "false" else (.terminal | tostring) end' <<<"${issue_item}")"
    issue_eligible="$(jq -r 'if .eligible == null then "true" else (.eligible | tostring) end' <<<"${issue_item}")"
    issue_reason="$(jq -r '.reason // .stop_reason // ""' <<<"${issue_item}")"

    if [[ "${claim_active}" != "true" ]]; then
      if [[ "${status}" == "terminal" && "${stop_reason}" == "stale-claim-released" && -n "${run_id}" ]]; then
        archived_now="$(archive_stale_artifacts_for_run "${run_id}" "$(jq -r '.workspace_receipt_path // ""' <<<"${claim_json}")" "${envelope_path}")"
        if [[ "${archived_now}" =~ ^[0-9]+$ ]] && (( archived_now > 0 )); then
          archived_files=$((archived_files + archived_now))
          archived_runs_json="$(jq -c --arg run_id "${run_id}" '. + [$run_id] | unique' <<<"${archived_runs_json}")"
        fi
      fi
      continue
    fi

    if [[ -n "${envelope_path}" && -f "${envelope_path}" ]]; then
      target_state="$(jq -r '.scheduler_state // ""' "${envelope_path}")"
      if [[ -n "${target_state}" ]]; then
        bash "${CLAIM_SCRIPT}" set-state --identity "${identity}" --state "${target_state}" --reason "$(jq -r '.reason // .status_reason // "run-envelope"' "${envelope_path}")" --envelope-path "${envelope_path}" >/dev/null
        updated=$((updated + 1))
        continue
      fi
    fi

    if [[ "${issue_terminal}" == "true" ]]; then
      stop_file="$(workspace_stop_file_for_claim "${run_id}" || true)"
      if [[ -n "${stop_file}" ]]; then
        mkdir -p "$(dirname "${stop_file}")"
        : >"${stop_file}"
      fi
      if kill_pid_if_live "${pid}"; then
        :
      fi
      bash "${CLAIM_SCRIPT}" set-state --identity "${identity}" --state terminal --reason "${issue_reason:-issue-terminal}" >/dev/null
      stopped=$((stopped + 1))
      continue
    fi

    if [[ "${issue_eligible}" != "true" ]]; then
      target_state="$(reason_to_state retry_queued "${issue_reason:-issue-ineligible}")"
      stop_file="$(workspace_stop_file_for_claim "${run_id}" || true)"
      if [[ -n "${stop_file}" ]]; then
        mkdir -p "$(dirname "${stop_file}")"
        : >"${stop_file}"
      fi
      kill_pid_if_live "${pid}" || true
      bash "${CLAIM_SCRIPT}" set-state --identity "${identity}" --state "${target_state}" --reason "${issue_reason:-issue-ineligible}" >/dev/null
      stopped=$((stopped + 1))
      continue
    fi

    if [[ "${live_pid}" == "true" ]]; then
      if [[ "${status}" == "continuity_degraded" ]]; then
        bash "${CLAIM_SCRIPT}" set-state --identity "${identity}" --state continuity_degraded --reason "$(jq -r '.reason // "live-continuity-degraded"' <<<"${claim_json}")" >/dev/null
      else
        bash "${CLAIM_SCRIPT}" set-state --identity "${identity}" --state running --reason "$(jq -r '.reason // "run-still-live"' <<<"${claim_json}")" >/dev/null
      fi
      continued=$((continued + 1))
      continue
    fi

    if is_stale_claim_candidate "${claim_json}" "${ttl_seconds}"; then
      bash "${CLAIM_SCRIPT}" release --identity "${identity}" --reason "stale-claim-released" >/dev/null
      released=$((released + 1))
      archived_now="$(archive_stale_artifacts_for_run "${run_id}" "$(jq -r '.workspace_receipt_path // ""' <<<"${claim_json}")" "${envelope_path}")"
      if [[ "${archived_now}" =~ ^[0-9]+$ ]] && (( archived_now > 0 )); then
        archived_files=$((archived_files + archived_now))
        archived_runs_json="$(jq -c --arg run_id "${run_id}" '. + [$run_id] | unique' <<<"${archived_runs_json}")"
      fi
    fi
  done < <(jq -c '.[]' <<<"${claims_json}")

  local active_run_ids_json compact_path compact_run_id compact_epoch
  active_run_ids_json="$(jq -c '[.[] | select((.claim_active // false) == true) | .run_id | select(length > 0)] | unique' <<<"${claims_json}")"
  while IFS= read -r compact_path; do
    [[ -f "${compact_path}" ]] || continue
    compact_run_id="$(jq -r '.run_id // ""' "${compact_path}" 2>/dev/null || true)"
    [[ -n "${compact_run_id}" ]] || continue
    if jq -e --arg run_id "${compact_run_id}" 'index($run_id) != null' <<<"${active_run_ids_json}" >/dev/null 2>&1; then
      continue
    fi
    compact_epoch="$(compact_updated_epoch "${compact_path}" || true)"
    [[ "${compact_epoch}" =~ ^[0-9]+$ ]] || continue
    if (( $(epoch_now) - compact_epoch < archive_ttl_seconds )); then
      continue
    fi
    archived_now="$(archive_stale_artifacts_for_run "${compact_run_id}" "" "" "${compact_path}")"
    if [[ "${archived_now}" =~ ^[0-9]+$ ]] && (( archived_now > 0 )); then
      archived_files=$((archived_files + archived_now))
      orphan_archived=$((orphan_archived + 1))
      archived_runs_json="$(jq -c --arg run_id "${compact_run_id}" '. + [$run_id] | unique' <<<"${archived_runs_json}")"
    fi
  done < <(compact_files)

  jq -n \
    --arg generated_at "$(utc_timestamp)" \
    --argjson scanned "${scanned}" \
    --argjson stopped "${stopped}" \
    --argjson updated "${updated}" \
    --argjson continued "${continued}" \
    --argjson released "${released}" \
    --argjson archived_files "${archived_files}" \
    --argjson orphan_archived "${orphan_archived}" \
    --argjson archived_runs "${archived_runs_json}" \
    '{
      generated_at: $generated_at,
      scanned: $scanned,
      stopped: $stopped,
      updated: $updated,
      continued: $continued,
      released: $released,
      archived_files: $archived_files,
      orphan_archived: $orphan_archived,
      archived_runs: $archived_runs
    }'
}

cmd="${1:-help}"
shift || true
case "${cmd}" in
  reconcile)
    cmd_reconcile "$@"
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
