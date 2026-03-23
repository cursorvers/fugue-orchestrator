#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
COMPACT_DIR="${KERNEL_COMPACT_DIR:-$(bash "${STATE_PATH_SCRIPT}" compact-dir)}"
LOCK_DIR="${KERNEL_COMPACT_LOCK_DIR:-${COMPACT_DIR}/.lock}"
LOCK_OWNER_FILE="${LOCK_DIR}/owner.pid"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
SESSION_NAME_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-session-name.sh"
CONSENSUS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-consensus-evidence.sh"
LOCK_HELD=0
source "${SCRIPT_DIR}/kernel-lock.sh"

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
  kernel-compact-artifact.sh path [run_id]
  kernel-compact-artifact.sh update <event> [summary]
  kernel-compact-artifact.sh status [run_id]
EOF
}

trap cleanup_lock EXIT INT TERM

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

artifact_path_for() {
  local run_id="$1"
  mkdir -p "${COMPACT_DIR}"
  printf '%s/%s.json\n' "${COMPACT_DIR}" "$(printf '%s' "${run_id}" | tr '/:' '__')"
}

default_session_short_id() {
  local source cleaned
  if [[ -n "${KERNEL_SESSION_SHORT_ID:-}" ]]; then
    printf '%s\n' "${KERNEL_SESSION_SHORT_ID}"
    return 0
  fi
  source="${RUN_ID}"
  [[ -n "${source}" ]] || return 0
  cleaned="$(printf '%s' "${source}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
  [[ -n "${cleaned}" ]] || return 0
  if (( ${#cleaned} > 8 )); then
    cleaned="${cleaned: -8}"
  fi
  printf '%s\n' "${cleaned}"
}

normalize_runtime() {
  local value="${1:-}"
  value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  case "${value}" in
    kernel|fugue)
      printf '%s\n' "${value}"
      ;;
    *)
      printf 'kernel\n'
      ;;
  esac
}

hash_payload() {
  local payload="${1:-}"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "${payload}" | shasum -a 256 | awk '{print $1}'
    return 0
  fi
  python3 - "${payload}" <<'PY'
import hashlib, sys
print(hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest())
PY
}

session_fingerprint_for() {
  local run_id="${1:-${RUN_ID}}"
  local project="${2:-${KERNEL_PROJECT:-kernel-workspace}}"
  local purpose="${3:-${KERNEL_PURPOSE:-unspecified}}"
  local runtime="${4:-kernel}"
  local tmux_session="${5:-}"
  [[ -n "${tmux_session}" ]] || return 1
  hash_payload "${run_id}|${project}|${purpose}|${runtime}|${tmux_session}"
}

resolve_runtime() {
  local existing_json="${1:-}"
  if [[ -n "${KERNEL_RUNTIME:-}" ]]; then
    normalize_runtime "${KERNEL_RUNTIME}"
    return 0
  fi
  if [[ -n "${KERNEL_ORCHESTRATION_RUNTIME:-}" ]]; then
    normalize_runtime "${KERNEL_ORCHESTRATION_RUNTIME}"
    return 0
  fi
  if [[ -n "${FUGUE_RUNTIME:-}" ]]; then
    normalize_runtime "${FUGUE_RUNTIME}"
    return 0
  fi
  if [[ -n "${FUGUE_ORCHESTRATION_RUNTIME:-}" ]]; then
    normalize_runtime "${FUGUE_ORCHESTRATION_RUNTIME}"
    return 0
  fi
  if [[ -n "${existing_json}" ]]; then
    normalize_runtime "$(jq -r '.runtime // ""' <<<"${existing_json}")"
    return 0
  fi
  printf 'kernel\n'
}

resolve_tmux_session() {
  local existing_json="${1:-}"
  local session_short_id existing_session
  local current_tmux_session=""
  if [[ -n "${KERNEL_TMUX_SESSION:-}" ]]; then
    printf '%s\n' "${KERNEL_TMUX_SESSION}"
    return 0
  fi
  if [[ -n "${existing_json}" ]]; then
    existing_session="$(jq -r '.tmux_session // ""' <<<"${existing_json}")"
    if [[ -n "${existing_session}" ]]; then
      printf '%s\n' "${existing_session}"
      return 0
    fi
  fi
  if [[ "${KERNEL_REUSE_CURRENT_TMUX_SESSION:-false}" == "true" ]] && [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    current_tmux_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
    if [[ -n "${current_tmux_session}" ]]; then
      printf '%s\n' "${current_tmux_session}"
      return 0
    fi
  fi
  session_short_id="$(default_session_short_id)"
  if [[ -f "${SESSION_NAME_SCRIPT}" ]]; then
    KERNEL_PROJECT="${KERNEL_PROJECT:-kernel-workspace}" \
      KERNEL_PURPOSE="${KERNEL_PURPOSE:-unspecified}" \
      KERNEL_SESSION_SHORT_ID="${session_short_id}" \
      bash "${SESSION_NAME_SCRIPT}" slug 2>/dev/null || true
  fi
}

resolve_codex_thread_title() {
  local existing_json="${1:-}"
  local existing_title=""
  local session_short_id
  if [[ -n "${existing_json}" ]]; then
    existing_title="$(jq -r '.codex_thread_title // ""' <<<"${existing_json}")"
    if [[ -n "${existing_title}" ]]; then
      printf '%s\n' "${existing_title}"
      return 0
    fi
    jq -r '(.project // "kernel-workspace") + ":" + (.purpose // "unspecified")' <<<"${existing_json}"
    return 0
  fi
  session_short_id="$(default_session_short_id)"
  if [[ -f "${SESSION_NAME_SCRIPT}" ]]; then
    KERNEL_PROJECT="${KERNEL_PROJECT:-kernel-workspace}" \
      KERNEL_PURPOSE="${KERNEL_PURPOSE:-unspecified}" \
      KERNEL_SESSION_SHORT_ID="${session_short_id}" \
      bash "${SESSION_NAME_SCRIPT}" label 2>/dev/null || true
    return 0
  fi
  printf '%s:%s\n' "${KERNEL_PROJECT:-kernel-workspace}" "${KERNEL_PURPOSE:-unspecified}"
}

sync_tmux_session_metadata() {
  local run_id="${1:-${RUN_ID}}"
  local tmux_session="${2:-}"
  local project="${3:-${KERNEL_PROJECT:-kernel-workspace}}"
  local purpose="${4:-${KERNEL_PURPOSE:-unspecified}}"
  local runtime="${5:-kernel}"
  local session_fingerprint="${6:-}"
  [[ -n "${tmux_session}" ]] || return 0
  command -v tmux >/dev/null 2>&1 || return 0
  tmux has-session -t "=${tmux_session}" 2>/dev/null || return 0
  tmux set-option -q -t "${tmux_session}" @kernel_run_id "${run_id}" >/dev/null 2>&1 || true
  tmux set-option -q -t "${tmux_session}" @kernel_project "${project}" >/dev/null 2>&1 || true
  tmux set-option -q -t "${tmux_session}" @kernel_purpose "${purpose}" >/dev/null 2>&1 || true
  tmux set-option -q -t "${tmux_session}" @kernel_runtime "${runtime}" >/dev/null 2>&1 || true
  if [[ -n "${session_fingerprint}" ]]; then
    tmux set-option -q -t "${tmux_session}" @kernel_session_fingerprint "${session_fingerprint}" >/dev/null 2>&1 || true
  fi
}

receipt_path() {
  KERNEL_RUN_ID="${RUN_ID}" bash "${RECEIPT_SCRIPT}" path 2>/dev/null || true
}

ledger_json() {
  KERNEL_RUN_ID="${RUN_ID}" bash "${LEDGER_SCRIPT}" status >/dev/null 2>&1 || true
  local ledger_file="${KERNEL_RUNTIME_LEDGER_FILE:-$(bash "${STATE_PATH_SCRIPT}" runtime-ledger-file)}"
  [[ -f "${ledger_file}" ]] || return 1
  jq -c --arg run_id "${RUN_ID}" '.runs[$run_id] // {}' "${ledger_file}"
}

receipt_json() {
  local path
  path="$(receipt_path)"
  [[ -f "${path}" ]] || return 1
  jq -c '.' "${path}"
}

consensus_receipt_path() {
  local path
  [[ -f "${CONSENSUS_SCRIPT}" ]] || return 0
  path="$(KERNEL_RUN_ID="${RUN_ID}" bash "${CONSENSUS_SCRIPT}" path 2>/dev/null || true)"
  if [[ -n "${path}" && -f "${path}" ]]; then
    printf '%s\n' "${path}"
  fi
}

normalize_summary() {
  local raw="${1:-}"
  printf '%s\n' "${raw}" | awk 'NF {print}' | sed -n '1,3p'
}

json_array_from_pipe_csv() {
  local raw="${1:-}"
  if [[ -z "${raw}" ]]; then
    printf '[]\n'
    return 0
  fi
  RAW="${raw}" python3 - <<'PY'
import json, os
raw = os.environ.get("RAW", "")
parts = [p.strip() for p in raw.split("|") if p.strip()]
print(json.dumps(parts[:3]))
PY
}

json_array_from_pipe_csv_first_only() {
  local raw="${1:-}"
  if [[ -z "${raw}" ]]; then
    printf '[]\n'
    return 0
  fi
  RAW="${raw}" python3 - <<'PY'
import json, os
raw = os.environ.get("RAW", "")
parts = [p.strip() for p in raw.split("|") if p.strip()]
print(json.dumps(parts[:1]))
PY
}

resolve_phase_artifacts_json() {
  local existing_json="${1:-}"
  local existing_phase_artifacts='{}'
  local research_report_path="${KERNEL_RESEARCH_REPORT_PATH:-${RESEARCH_REPORT_PATH:-}}"
  local plan_report_path="${KERNEL_PLAN_REPORT_PATH:-${PLAN_REPORT_PATH:-}}"
  local critic_report_path="${KERNEL_CRITIC_REPORT_PATH:-${CRITIC_REPORT_PATH:-}}"
  local preflight_report_path="${KERNEL_PREFLIGHT_REPORT_PATH:-${PREFLIGHT_REPORT_PATH:-}}"
  local implementation_report_path="${KERNEL_IMPLEMENTATION_REPORT_PATH:-${IMPLEMENTATION_REPORT_PATH:-}}"
  local todo_report_path="${KERNEL_TODO_REPORT_PATH:-${TODO_REPORT_PATH:-}}"
  local lessons_report_path="${KERNEL_LESSONS_REPORT_PATH:-${LESSONS_REPORT_PATH:-}}"
  if [[ -n "${existing_json}" ]]; then
    existing_phase_artifacts="$(jq -c '.phase_artifacts // {}' <<<"${existing_json}")"
  fi
  jq -cn \
    --argjson existing_phase_artifacts "${existing_phase_artifacts}" \
    --arg research_report_path "${research_report_path}" \
    --arg plan_report_path "${plan_report_path}" \
    --arg critic_report_path "${critic_report_path}" \
    --arg preflight_report_path "${preflight_report_path}" \
    --arg implementation_report_path "${implementation_report_path}" \
    --arg todo_report_path "${todo_report_path}" \
    --arg lessons_report_path "${lessons_report_path}" \
    '
      $existing_phase_artifacts
      + (if $research_report_path == "" then {} else {research_report_path: $research_report_path} end)
      + (if $plan_report_path == "" then {} else {plan_report_path: $plan_report_path} end)
      + (if $critic_report_path == "" then {} else {critic_report_path: $critic_report_path} end)
      + (if $preflight_report_path == "" then {} else {preflight_report_path: $preflight_report_path} end)
      + (if $implementation_report_path == "" then {} else {implementation_report_path: $implementation_report_path} end)
      + (if $todo_report_path == "" then {} else {todo_report_path: $todo_report_path} end)
      + (if $lessons_report_path == "" then {} else {lessons_report_path: $lessons_report_path} end)
    '
}

cmd_path() {
  printf '%s\n' "$(artifact_path_for "${1:-${RUN_ID}}")"
}

cmd_update() {
  local event="${1:-}"
  local summary_input="${2:-${KERNEL_SUMMARY:-}}"
  local path tmp_file existing_json existing_project existing_purpose
  local tmux_session phase project purpose owner blocking_reason codex_thread_title
  local mode runtime active_models_json decisions_json next_actions_json phase_artifacts_json ledger_compact receipt_compact
  local existing_mode existing_blocking_reason existing_scheduler_state existing_scheduler_reason
  local existing_workspace_receipt_path existing_consensus_receipt_path scheduler_state scheduler_reason workspace_receipt_path consensus_receipt_path_value
  local session_fingerprint
  local summary normalized_summary

  [[ -n "${event}" ]] || {
    echo "event is required" >&2
    exit 2
  }

  path="$(artifact_path_for "${RUN_ID}")"
  if [[ -f "${path}" ]]; then
    existing_json="$(jq -c '.' "${path}")"
    local _ep _eu
    IFS=$'\t' read -r _ep _eu < <(jq -r '[(.project // ""), (.purpose // "")] | @tsv' <<<"${existing_json}")
    existing_project="${_ep}"
    existing_purpose="${_eu}"
  else
    existing_json=""
    existing_project=""
    existing_purpose=""
  fi
  existing_mode="${KERNEL_MODE:-}"
  existing_blocking_reason=""
  existing_scheduler_state=""
  existing_scheduler_reason=""
  existing_workspace_receipt_path=""
  existing_consensus_receipt_path=""
  if [[ -n "${existing_json}" ]]; then
    if [[ -z "${existing_mode}" ]]; then
      existing_mode="$(jq -r '.mode // "unknown"' <<<"${existing_json}")"
    fi
    local _eb _ess _esr _ewp _ecrp
    IFS=$'\t' read -r _eb _ess _esr _ewp < <(jq -r '[
      (.blocking_reason // ""),
      (.scheduler_state // ""),
      (.scheduler_reason // ""),
      (.workspace_receipt_path // "")
    ] | @tsv' <<<"${existing_json}")
    existing_blocking_reason="${_eb}"
    existing_scheduler_state="${_ess}"
    existing_scheduler_reason="${_esr}"
    existing_workspace_receipt_path="${_ewp}"
    _ecrp="$(jq -r '.consensus_receipt_path // ""' <<<"${existing_json}")"
    existing_consensus_receipt_path="${_ecrp}"
  fi

  project="${KERNEL_PROJECT:-${existing_project:-kernel-workspace}}"
  purpose="${KERNEL_PURPOSE:-${existing_purpose:-unspecified}}"
  if [[ -n "${existing_project}" && "${project}" != "${existing_project}" ]]; then
    echo "project is fixed for run ${RUN_ID}; expected ${existing_project}, got ${project}" >&2
    exit 2
  fi
  if [[ -n "${existing_purpose}" && "${purpose}" != "${existing_purpose}" ]]; then
    echo "purpose is fixed for run ${RUN_ID}; expected ${existing_purpose}, got ${purpose}" >&2
    exit 2
  fi
  phase="${KERNEL_PHASE:-unknown}"
  owner="${KERNEL_OWNER:-local-operator}"
  tmux_session="$(resolve_tmux_session "${existing_json}")"
  codex_thread_title="$(resolve_codex_thread_title "${existing_json}")"
  runtime="$(resolve_runtime "${existing_json}")"
  session_fingerprint="$(session_fingerprint_for "${RUN_ID}" "${project}" "${purpose}" "${runtime}" "${tmux_session}")"
  blocking_reason="${KERNEL_BLOCKING_REASON:-}"
  scheduler_state="${KERNEL_SCHEDULER_STATE:-}"
  scheduler_reason="${KERNEL_SCHEDULER_REASON:-}"
  workspace_receipt_path="${KERNEL_WORKSPACE_RECEIPT_PATH:-}"
  consensus_receipt_path_value="${KERNEL_CONSENSUS_RECEIPT_PATH:-}"
  if [[ -n "${KERNEL_DECISIONS:-}" ]]; then
    decisions_json="$(json_array_from_pipe_csv "${KERNEL_DECISIONS}")"
  elif [[ -n "${existing_json}" ]]; then
    decisions_json="$(jq -c '.decisions // []' <<<"${existing_json}")"
  else
    decisions_json='[]'
  fi
  if [[ -n "${KERNEL_NEXT_ACTIONS:-}" ]]; then
    next_actions_json="$(json_array_from_pipe_csv_first_only "${KERNEL_NEXT_ACTIONS}")"
  elif [[ -n "${existing_json}" ]]; then
    next_actions_json="$(jq -c '.next_action // []' <<<"${existing_json}")"
  else
    next_actions_json='[]'
  fi

  if ledger_compact="$(ledger_json 2>/dev/null)"; then
    local _lstate _lreason _lscheduler_state _lscheduler_reason _lworkspace_receipt_path
    IFS=$'\t' read -r _lstate _lreason _lscheduler_state _lscheduler_reason _lworkspace_receipt_path < <(jq -r '[
      (.state // ""),
      (.reason // ""),
      (.scheduler_state // ""),
      (.scheduler_reason // ""),
      (.workspace_receipt_path // "")
    ] | @tsv' <<<"${ledger_compact}")
    if [[ -n "${_lstate}" && "${_lstate}" != "unknown" ]]; then
      mode="${_lstate}"
    else
      mode="${existing_mode:-unknown}"
    fi
    if [[ -z "${blocking_reason}" && -n "${_lreason}" ]]; then
      blocking_reason="${_lreason}"
    fi
    if [[ -z "${scheduler_state}" && -n "${_lscheduler_state}" && "${_lscheduler_state}" != "unknown" ]]; then
      scheduler_state="${_lscheduler_state}"
    fi
    if [[ -z "${scheduler_reason}" && -n "${_lscheduler_reason}" ]]; then
      scheduler_reason="${_lscheduler_reason}"
    fi
    if [[ -z "${workspace_receipt_path}" && -n "${_lworkspace_receipt_path}" ]]; then
      workspace_receipt_path="${_lworkspace_receipt_path}"
    fi
  else
    mode="${existing_mode:-unknown}"
  fi
  if [[ -z "${blocking_reason}" ]]; then
    blocking_reason="${existing_blocking_reason}"
  fi
  if [[ -z "${scheduler_state}" ]]; then
    scheduler_state="${existing_scheduler_state}"
  fi
  if [[ -z "${scheduler_reason}" ]]; then
    scheduler_reason="${existing_scheduler_reason}"
  fi
  if [[ -z "${workspace_receipt_path}" ]]; then
    workspace_receipt_path="${existing_workspace_receipt_path}"
  fi
  if [[ -z "${consensus_receipt_path_value}" ]]; then
    consensus_receipt_path_value="$(consensus_receipt_path)"
  fi
  if [[ -z "${consensus_receipt_path_value}" ]]; then
    consensus_receipt_path_value="${existing_consensus_receipt_path}"
  fi

  if receipt_compact="$(receipt_json 2>/dev/null)"; then
    active_models_json="$(jq -c '.active_models // []' <<<"${receipt_compact}")"
  elif [[ -n "${existing_json}" ]]; then
    active_models_json="$(jq -c '.active_models // []' <<<"${existing_json}")"
  else
    active_models_json='[]'
  fi

  if [[ -z "${summary_input}" ]]; then
    summary="event=${event}; mode=${mode}; phase=${phase}; next=$(jq -r '.[0] // ""' <<<"${next_actions_json}")"
  else
    summary="${summary_input}"
  fi
  if [[ -z "${summary}" && -n "${existing_json}" ]]; then
    summary="$(jq -r '(.summary // []) | join("\n")' <<<"${existing_json}")"
  fi
  normalized_summary="$(normalize_summary "${summary}")"
  phase_artifacts_json="$(resolve_phase_artifacts_json "${existing_json}")"

  acquire_lock "compact artifact"
  tmp_file="${path}.tmp.$$.$RANDOM"
  jq -n \
    --arg run_id "${RUN_ID}" \
    --arg project "${project}" \
    --arg purpose "${purpose}" \
    --arg phase "${phase}" \
    --arg mode "${mode}" \
    --arg runtime "${runtime}" \
    --arg tmux_session "${tmux_session}" \
    --arg session_fingerprint "${session_fingerprint}" \
    --arg codex_thread_title "${codex_thread_title}" \
    --arg owner "${owner}" \
    --arg blocking_reason "${blocking_reason}" \
    --arg scheduler_state "${scheduler_state}" \
    --arg scheduler_reason "${scheduler_reason}" \
    --arg workspace_receipt_path "${workspace_receipt_path}" \
    --arg consensus_receipt_path "${consensus_receipt_path_value}" \
    --arg event "${event}" \
    --arg updated_at "$(utc_timestamp)" \
    --arg summary "${normalized_summary}" \
    --argjson active_models "${active_models_json}" \
    --argjson decisions "${decisions_json}" \
    --argjson next_action "${next_actions_json}" \
    --argjson phase_artifacts "${phase_artifacts_json}" \
    '
      {
        run_id: $run_id,
        project: $project,
        purpose: $purpose,
        current_phase: $phase,
        mode: $mode,
        runtime: $runtime,
        tmux_session: $tmux_session,
        session_fingerprint: $session_fingerprint,
        codex_thread_title: $codex_thread_title,
        owner: $owner,
        active_models: $active_models,
        blocking_reason: $blocking_reason,
        scheduler_state: $scheduler_state,
        scheduler_reason: $scheduler_reason,
        workspace_receipt_path: $workspace_receipt_path,
        consensus_receipt_path: $consensus_receipt_path,
        next_action: $next_action,
        decisions: $decisions,
        phase_artifacts: $phase_artifacts,
        summary: ($summary | split("\n") | map(select(length > 0)) | .[:3]),
        last_event: $event,
        updated_at: $updated_at
      }
    ' >"${tmp_file}"
  mv "${tmp_file}" "${path}"
  sync_tmux_session_metadata "${RUN_ID}" "${tmux_session}" "${project}" "${purpose}" "${runtime}" "${session_fingerprint}"
  cleanup_lock
  cmd_status "${RUN_ID}"
}

cmd_status() {
  local run_id="${1:-${RUN_ID}}"
  local path
  path="$(artifact_path_for "${run_id}")"
  if [[ ! -f "${path}" ]]; then
    printf 'compact artifact:\n'
    printf '  - run id: %s\n' "${run_id}"
    printf '  - present: false\n'
    printf '  - path: %s\n' "${path}"
    return 1
  fi
  printf 'compact artifact:\n'
  printf '  - run id: %s\n' "${run_id}"
  printf '  - present: true\n'
  printf '  - path: %s\n' "${path}"
  jq -r '
    "  - project: \(.project)",
    "  - purpose: \(.purpose)",
    "  - phase: \(.current_phase)",
    "  - mode: \(.mode)",
    "  - runtime: \(.runtime // "kernel")",
    "  - tmux session: \(.tmux_session)",
    "  - session fingerprint: \(.session_fingerprint // "unknown")",
    "  - codex thread: \(.codex_thread_title)",
    "  - owner: \(.owner)",
    "  - active models: \(.active_models | join(","))",
    "  - blocking reason: \(.blocking_reason)",
    "  - scheduler state: \(.scheduler_state // "unknown")",
    "  - scheduler reason: \(.scheduler_reason // "")",
    "  - workspace receipt path: \(.workspace_receipt_path // "")",
    "  - consensus receipt path: \(.consensus_receipt_path // "")",
    "  - phase artifacts: \(if ((.phase_artifacts // {}) | length) == 0 then "none" else ((.phase_artifacts // {}) | keys | join(" | ")) end)",
    "  - next action: \(.next_action | join(" | "))",
    "  - decisions: \(.decisions | join(" | "))",
    "  - summary: \(.summary | join(" || "))",
    "  - last event: \(.last_event)",
    "  - updated at: \(.updated_at)"
  ' "${path}"
}

cmd="${1:-status}"
case "${cmd}" in
  path)
    shift || true
    cmd_path "$@"
    ;;
  update)
    shift || true
    cmd_update "$@"
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
