#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLAIM_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-claim.sh"
STATE_PATHS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
STATE_ROOT="${KERNEL_SUBSTRATE_STATE_ROOT:-$(bash "${STATE_PATHS_SCRIPT}" state-root)}"
STATUS_DIR="${KERNEL_RUNTIME_STATUS_DIR:-${STATE_ROOT}/status}"
STATUS_PATH="${KERNEL_RUNTIME_STATUS_PATH:-${STATUS_DIR}/runtime-status.json}"

usage() {
  cat <<'EOF'
Usage:
  kernel-runtime-status-surface.sh path
  kernel-runtime-status-surface.sh snapshot [--queue-file <path>] [--queue-json <json>] [--write]
EOF
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

load_queue_json() {
  local queue_file="${1:-}"
  local queue_json="${2:-}"
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
        dispatchable: (
          if .dispatchable == null then (inferred_authorized and inferred_eligible and (inferred_terminal | not))
          else (.dispatchable | bool_or(false))
          end
        ),
        authorized: inferred_authorized,
        eligible: inferred_eligible,
        terminal: inferred_terminal,
        reason: (.reason // .blocking_reason // "")
      })
  ' <<<"${raw_json}"
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

cmd_path() {
  printf '%s\n' "${STATUS_PATH}"
}

cmd_snapshot() {
  local queue_file="" queue_json="" write_snapshot=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --queue-file) queue_file="${2:-}"; shift 2 ;;
      --queue-json) queue_json="${2:-}"; shift 2 ;;
      --write) write_snapshot=true; shift ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done

  local claims_json queue_raw queue_items snapshot_json
  claims_json="$(bash "${CLAIM_SCRIPT}" list)"
  queue_raw="$(load_queue_json "${queue_file}" "${queue_json}")"
  queue_items="$(normalize_queue_json "${queue_raw}")"
  snapshot_json="$(
    jq -n \
      --arg generated_at "$(utc_timestamp)" \
      --arg state_root "${STATE_ROOT}" \
      --arg status_path "${STATUS_PATH}" \
      --argjson claims "${claims_json}" \
      --argjson queue_items "${queue_items}" \
      '
        ($claims // []) as $all_claims
        | ($queue_items // []) as $items
        | ($all_claims | map(select((.claim_active // false) == true and (.status // "") != "terminal"))) as $active_claims
        | ($all_claims | map(select((.status // "") == "running"))) as $running
        | ($all_claims | map(select((.status // "") == "retry_queued"))) as $retrying
        | ($all_claims | map(select((.status // "") == "continuity_degraded"))) as $degraded
        | ($all_claims | map(select((.status // "") == "awaiting_human"))) as $blocked_claims
        | ($all_claims | map(select((.status // "") == "terminal"))) as $terminal
        | ($items | map(select(.dispatchable == false and ((.identity as $id | $active_claims | map(.identity) | index($id)) == null) and ((.terminal // false) == false)))) as $blocked_queue
        | ($active_claims | map(select((.continuity_owner // "local-primary") == "local-primary") | .identity)) as $local_primary
        | ($active_claims | map(select((.continuity_owner // "") == "gha-continuity") | .identity)) as $gha_continuity
        | {
            version: 1,
            generated_at: $generated_at,
            state_root: $state_root,
            status_path: $status_path,
            summary: {
              active_claims: ($active_claims | length),
              running: ($running | length),
              retrying: ($retrying | length),
              degraded: ($degraded | length),
              blocked: (($blocked_claims | length) + ($blocked_queue | length)),
              terminal: ($terminal | length)
            },
            running: $running,
            retrying: $retrying,
            degraded: $degraded,
            blocked: ($blocked_claims + $blocked_queue),
            terminal: $terminal,
            recovery_handoff: {
              local_primary: {
                active: (($local_primary | length) > 0),
                identities: $local_primary
              },
              gha_continuity: {
                active: (($gha_continuity | length) > 0),
                identities: $gha_continuity
              },
              preferred_recovery: (
                if ($local_primary | length) > 0 then "local-primary"
                elif ($gha_continuity | length) > 0 then "gha-continuity"
                else "idle"
                end
              )
            },
            claims: $all_claims
          }
      '
  )"

  if [[ "${write_snapshot}" == "true" ]]; then
    write_json_atomic "${STATUS_PATH}" "${snapshot_json}"
  fi
  printf '%s\n' "${snapshot_json}"
}

cmd="${1:-help}"
shift || true
case "${cmd}" in
  path)
    cmd_path "$@"
    ;;
  snapshot)
    cmd_snapshot "$@"
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
