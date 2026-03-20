#!/usr/bin/env bash
set -euo pipefail

COMPACT_DIR="${KERNEL_COMPACT_DIR:-$HOME/.config/kernel/compact}"
LOCK_DIR="${KERNEL_COMPACT_LOCK_DIR:-${COMPACT_DIR}/.lock}"
LOCK_OWNER_FILE="${LOCK_DIR}/owner.pid"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
SESSION_NAME_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-session-name.sh"
LOCK_HELD=0

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
  mkdir -p "${COMPACT_DIR}"
  while ! mkdir "${LOCK_DIR}" 2>/dev/null; do
    if stale_lock_owner_dead; then
      rm -rf "${LOCK_DIR}" 2>/dev/null || true
      continue
    fi
    attempts=$((attempts + 1))
    if (( attempts >= 200 )); then
      echo "compact artifact lock timeout: ${LOCK_DIR}" >&2
      exit 1
    fi
    sleep 0.05
  done
  printf '%s\n' "$$" >"${LOCK_OWNER_FILE}"
  LOCK_HELD=1
}

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
  local ledger_file="${KERNEL_RUNTIME_LEDGER_FILE:-$HOME/.config/kernel/runtime-ledger.json}"
  [[ -f "${ledger_file}" ]] || return 1
  jq -c --arg run_id "${RUN_ID}" '.runs[$run_id] // {}' "${ledger_file}"
}

receipt_json() {
  local path
  path="$(receipt_path)"
  [[ -f "${path}" ]] || return 1
  jq -c '.' "${path}"
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

cmd_path() {
  printf '%s\n' "$(artifact_path_for "${1:-${RUN_ID}}")"
}

cmd_update() {
  local event="${1:-}"
  local summary_input="${2:-${KERNEL_SUMMARY:-}}"
  local path tmp_file existing_json existing_project existing_purpose
  local tmux_session phase project purpose owner blocking_reason codex_thread_title
  local mode runtime active_models_json decisions_json next_actions_json ledger_compact receipt_compact
  local session_fingerprint
  local summary normalized_summary

  [[ -n "${event}" ]] || {
    echo "event is required" >&2
    exit 2
  }

  path="$(artifact_path_for "${RUN_ID}")"
  if [[ -f "${path}" ]]; then
    existing_json="$(jq -c '.' "${path}")"
    existing_project="$(jq -r '.project // ""' <<<"${existing_json}")"
    existing_purpose="$(jq -r '.purpose // ""' <<<"${existing_json}")"
  else
    existing_json=""
    existing_project=""
    existing_purpose=""
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
    mode="$(jq -r '.state // "unknown"' <<<"${ledger_compact}")"
    if [[ -z "${blocking_reason}" ]]; then
      blocking_reason="$(jq -r '.reason // ""' <<<"${ledger_compact}")"
    fi
  else
    mode="${KERNEL_MODE:-unknown}"
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

  acquire_lock
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
    --arg event "${event}" \
    --arg updated_at "$(utc_timestamp)" \
    --arg summary "${normalized_summary}" \
    --argjson active_models "${active_models_json}" \
    --argjson decisions "${decisions_json}" \
    --argjson next_action "${next_actions_json}" \
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
        next_action: $next_action,
        decisions: $decisions,
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
