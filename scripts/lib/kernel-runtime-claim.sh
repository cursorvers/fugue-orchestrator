#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
STATE_PATHS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
STATE_ROOT="${KERNEL_SUBSTRATE_STATE_ROOT:-$(bash "${STATE_PATHS_SCRIPT}" state-root)}"
CLAIMS_DIR="${KERNEL_RUNTIME_CLAIMS_DIR:-${STATE_ROOT}/claims}"
LOCK_DIR="${KERNEL_RUNTIME_CLAIMS_LOCK_DIR:-${CLAIMS_DIR}/.lock}"
LOCK_OWNER_FILE="${LOCK_DIR}/owner.pid"
LOCK_HELD=0
source "${SCRIPT_DIR}/kernel-lock.sh"

trap cleanup_lock EXIT INT TERM

usage() {
  cat <<'EOF'
Usage:
  kernel-runtime-claim.sh path --identity <identity>
  kernel-runtime-claim.sh status --identity <identity>
  kernel-runtime-claim.sh list [--active-only]
  kernel-runtime-claim.sh claim [options]
  kernel-runtime-claim.sh set-state [options] --state <state>
  kernel-runtime-claim.sh release [options]
  kernel-runtime-claim.sh rebuild [--ttl-seconds <seconds>]

Options:
  --identity <identity>
  --project <project>
  --issue-number <number>
  --task-key <task_key>
  --run-id <run_id>
  --source <source>
  --reason <reason>
  --refresh-token <token>
  --state <claimed|running|retry_queued|continuity_degraded|awaiting_human|terminal>
  --workspace-receipt-path <path>
  --envelope-path <path>
  --topology-path <path>
  --command-string <command>
  --provider <provider>
  --continuity-owner <local-primary|gha-continuity|unknown>
  --run-driver-pid <pid>
EOF
}

ensure_claims_dir() {
  mkdir -p "${CLAIMS_DIR}"
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

epoch_now() {
  date -u '+%s'
}

normalize_state() {
  local state="${1:-claimed}"
  case "${state}" in
    claimed|running|retry_queued|continuity_degraded|awaiting_human|terminal)
      printf '%s\n' "${state}"
      ;;
    *)
      echo "unsupported claim state: ${state}" >&2
      exit 2
      ;;
  esac
}

bool_string() {
  case "$(printf '%s' "${1:-false}" | tr '[:upper:]' '[:lower:]')" in
    true|1|yes|on) printf 'true\n' ;;
    *) printf 'false\n' ;;
  esac
}

slugify() {
  local value="${1:-}"
  value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "${value}" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  if [[ -z "${value}" ]]; then
    printf 'claim\n'
  else
    printf '%s\n' "${value}"
  fi
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
  if [[ -n "${task_key}" ]]; then
    printf '%s/%s\n' "${project}" "${task_key}"
    return 0
  fi
  if [[ -n "${run_id}" ]]; then
    printf '%s@%s\n' "${project}" "${run_id}"
    return 0
  fi
  echo "unable to derive claim identity" >&2
  exit 2
}

claim_path_for_identity() {
  local identity="${1:?identity is required}"
  local identity_slug identity_hash
  identity_slug="$(slugify "${identity}")"
  identity_hash="$(hash_text "${identity}")"
  ensure_claims_dir
  printf '%s/%s-%s.json\n' "${CLAIMS_DIR}" "${identity_slug:0:72}" "${identity_hash:0:12}"
}

load_claim_json() {
  local claim_path="${1:?claim_path is required}"
  if [[ -f "${claim_path}" ]]; then
    jq -c '.' "${claim_path}"
  else
    printf '{}\n'
  fi
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

claim_status_active() {
  local status="${1:-}"
  case "${status}" in
    terminal|"") return 1 ;;
    *) return 0 ;;
  esac
}

resolve_existing_run_id() {
  local claim_json="${1:-}"
  if [[ -z "${claim_json}" ]]; then
    claim_json='{}'
  fi
  jq -r '.run_id // ""' <<<"${claim_json}"
}

record_scheduler_state() {
  local run_id="${1:-}"
  local scheduler_state="${2:-}"
  local reason="${3:-}"
  local workspace_receipt_path="${4:-}"
  [[ -n "${run_id}" ]] || return 0
  [[ -x "${LEDGER_SCRIPT}" || -f "${LEDGER_SCRIPT}" ]] || return 0
  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" scheduler-state "${scheduler_state}" "${reason}" "${workspace_receipt_path}" >/dev/null 2>&1 || true
}

record_event() {
  local run_id="${1:-}"
  local command_name="${2:-}"
  local summary="${3:-}"
  [[ -n "${run_id}" ]] || return 0
  [[ -x "${LEDGER_SCRIPT}" || -f "${LEDGER_SCRIPT}" ]] || return 0
  KERNEL_RUN_ID="${run_id}" bash "${LEDGER_SCRIPT}" record-event kernel-runtime-claim "${command_name}" "${summary}" >/dev/null 2>&1 || true
}

claim_upsert() {
  local identity="${1:?identity is required}"
  local project="${2:-${KERNEL_PROJECT:-kernel-workspace}}"
  local issue_number="${3:-}"
  local task_key="${4:-}"
  local run_id="${5:-}"
  local source="${6:-scheduler}"
  local reason="${7:-dispatchable}"
  local refresh_token="${8:-}"
  local state="${9:-claimed}"
  local workspace_receipt_path="${10:-}"
  local envelope_path="${11:-}"
  local topology_path="${12:-}"
  local command_string="${13:-}"
  local provider="${14:-}"
  local continuity_owner="${15:-local-primary}"
  local run_driver_pid="${16:-}"
  local claim_path existing_json now now_epoch claim_token identity_hash identity_slug action existing_run_id

  state="$(normalize_state "${state}")"
  claim_path="$(claim_path_for_identity "${identity}")"
  existing_json="$(load_claim_json "${claim_path}")"
  now="$(utc_timestamp)"
  now_epoch="$(epoch_now)"
  identity_hash="$(hash_text "${identity}")"
  identity_slug="$(slugify "${identity}")"
  existing_run_id="$(resolve_existing_run_id "${existing_json}")"
  if [[ -n "${existing_run_id}" && -z "${run_id}" ]]; then
    run_id="${existing_run_id}"
  fi
  claim_token="claim:${identity_hash:0:16}"
  if [[ "$(jq -r '((.claim_active // false) and ((.status // "") != "terminal"))' <<<"${existing_json}")" == "true" ]]; then
    action="coalesced"
  else
    action="claimed"
  fi

  acquire_lock "kernel runtime claims"
  local next_json
  next_json="$(
    jq -n \
      --argjson prev "${existing_json}" \
      --arg identity "${identity}" \
      --arg identity_slug "${identity_slug}" \
      --arg identity_hash "${identity_hash}" \
      --arg project "${project}" \
      --arg issue_number "${issue_number}" \
      --arg task_key "${task_key}" \
      --arg run_id "${run_id}" \
      --arg source "${source}" \
      --arg reason "${reason}" \
      --arg refresh_token "${refresh_token}" \
      --arg state "${state}" \
      --arg workspace_receipt_path "${workspace_receipt_path}" \
      --arg envelope_path "${envelope_path}" \
      --arg topology_path "${topology_path}" \
      --arg command_string "${command_string}" \
      --arg provider "${provider}" \
      --arg continuity_owner "${continuity_owner}" \
      --arg run_driver_pid "${run_driver_pid}" \
      --arg claim_token "${claim_token}" \
      --arg claimed_at "${now}" \
      --arg updated_at "${now}" \
      --argjson claimed_at_epoch "${now_epoch}" \
      --argjson updated_at_epoch "${now_epoch}" \
      '
        ($prev // {}) as $p
        | (($p.claim_active // false) and (($p.status // "") != "terminal")) as $active
        | {
            version: 1,
            identity: $identity,
            identity_slug: $identity_slug,
            identity_hash: $identity_hash,
            project: (if $project != "" then $project else ($p.project // "kernel-workspace") end),
            issue_number: (if $issue_number == "" then ($p.issue_number // null) else ($issue_number | tonumber) end),
            task_key: (if $task_key != "" then $task_key else ($p.task_key // "") end),
            run_id: (if $run_id != "" then $run_id else ($p.run_id // "") end),
            claim_token: (if ($p.claim_token // "") != "" then ($p.claim_token // "") else $claim_token end),
            source: (if $source != "" then $source else ($p.source // "") end),
            reason: (if $reason != "" then $reason else ($p.reason // "") end),
            refresh_token: (if $refresh_token != "" then $refresh_token else ($p.refresh_token // "") end),
            refresh_count: (if $active then (($p.refresh_count // 0) + 1) else 1 end),
            first_refresh_at: (if $active and (($p.first_refresh_at // "") != "") then ($p.first_refresh_at // "") else $claimed_at end),
            first_refresh_epoch: (if $active and (($p.first_refresh_epoch // 0) > 0) then ($p.first_refresh_epoch // 0) else $claimed_at_epoch end),
            last_refresh_at: $updated_at,
            last_refresh_epoch: $updated_at_epoch,
            status: (if $state != "" then $state else (if $active and (($p.status // "") != "") then ($p.status // "") else "claimed" end) end),
            claim_active: ($state != "terminal"),
            claimed_at: (if $active and (($p.claimed_at // "") != "") then ($p.claimed_at // "") else $claimed_at end),
            claimed_at_epoch: (if $active and (($p.claimed_at_epoch // 0) > 0) then ($p.claimed_at_epoch // 0) else $claimed_at_epoch end),
            updated_at: $updated_at,
            updated_at_epoch: $updated_at_epoch,
            released_at: (if $state == "terminal" then $updated_at else ($p.released_at // "") end),
            released_at_epoch: (if $state == "terminal" then $updated_at_epoch else ($p.released_at_epoch // null) end),
            workspace_receipt_path: (if $workspace_receipt_path != "" then $workspace_receipt_path else ($p.workspace_receipt_path // "") end),
            envelope_path: (if $envelope_path != "" then $envelope_path else ($p.envelope_path // "") end),
            topology_path: (if $topology_path != "" then $topology_path else ($p.topology_path // "") end),
            command_string: (if $command_string != "" then $command_string else ($p.command_string // "") end),
            provider: (if $provider != "" then $provider else ($p.provider // "") end),
            continuity_owner: (if $continuity_owner != "" then $continuity_owner else ($p.continuity_owner // "local-primary") end),
            run_driver_pid: (if $run_driver_pid != "" then ($run_driver_pid | tonumber) else ($p.run_driver_pid // null) end),
            stop_reason: ($p.stop_reason // ""),
            retry_reason: ($p.retry_reason // ""),
            downgrade_reason: ($p.downgrade_reason // ""),
            last_action: "claim"
          }
      '
  )"
  write_json_atomic "${claim_path}" "${next_json}"
  release_lock

  local effective_run_id effective_workspace
  effective_run_id="$(jq -r '.run_id // ""' <<<"${next_json}")"
  effective_workspace="$(jq -r '.workspace_receipt_path // ""' <<<"${next_json}")"
  record_scheduler_state "${effective_run_id}" "$(jq -r '.status' <<<"${next_json}")" "${reason}" "${effective_workspace}"
  record_event "${effective_run_id}" claim "${identity}; action=${action}; reason=${reason}"

  jq -n --arg action "${action}" --arg claim_path "${claim_path}" --argjson claim "${next_json}" \
    '{action: $action, claim_path: $claim_path, claim: $claim}'
}

set_state_for_identity() {
  local identity="${1:?identity is required}"
  local requested_state="${2:?state is required}"
  local reason="${3:-state-updated}"
  local workspace_receipt_path="${4:-}"
  local envelope_path="${5:-}"
  local continuity_owner="${6:-}"
  local run_driver_pid="${7:-}"
  local claim_path existing_json now now_epoch next_json run_id

  requested_state="$(normalize_state "${requested_state}")"
  claim_path="$(claim_path_for_identity "${identity}")"
  existing_json="$(load_claim_json "${claim_path}")"
  now="$(utc_timestamp)"
  now_epoch="$(epoch_now)"

  acquire_lock "kernel runtime claims"
  next_json="$(
    jq -n \
      --argjson prev "${existing_json}" \
      --arg state "${requested_state}" \
      --arg reason "${reason}" \
      --arg workspace_receipt_path "${workspace_receipt_path}" \
      --arg envelope_path "${envelope_path}" \
      --arg continuity_owner "${continuity_owner}" \
      --arg run_driver_pid "${run_driver_pid}" \
      --arg updated_at "${now}" \
      --argjson updated_at_epoch "${now_epoch}" \
      '
        ($prev // {}) as $p
        | ($state != "terminal") as $active
        | ($p + {
            status: $state,
            claim_active: $active,
            reason: $reason,
            updated_at: $updated_at,
            updated_at_epoch: $updated_at_epoch,
            last_action: "set-state",
            workspace_receipt_path: (if $workspace_receipt_path != "" then $workspace_receipt_path else ($p.workspace_receipt_path // "") end),
            envelope_path: (if $envelope_path != "" then $envelope_path else ($p.envelope_path // "") end),
            continuity_owner: (if $continuity_owner != "" then $continuity_owner else ($p.continuity_owner // "local-primary") end),
            run_driver_pid: (if $run_driver_pid != "" then ($run_driver_pid | tonumber) else ($p.run_driver_pid // null) end)
          })
        | if $state == "terminal" then . + {
            released_at: $updated_at,
            released_at_epoch: $updated_at_epoch,
            stop_reason: $reason,
            run_driver_pid: null
          } else . end
        | if $state == "retry_queued" then . + { retry_reason: $reason } else . end
        | if $state == "continuity_degraded" then . + { downgrade_reason: $reason } else . end
        | if $state == "awaiting_human" then . + { stop_reason: $reason } else . end
      '
  )"
  write_json_atomic "${claim_path}" "${next_json}"
  release_lock

  run_id="$(jq -r '.run_id // ""' <<<"${next_json}")"
  record_scheduler_state "${run_id}" "${requested_state}" "${reason}" "$(jq -r '.workspace_receipt_path // ""' <<<"${next_json}")"
  record_event "${run_id}" set-state "${identity}; state=${requested_state}; reason=${reason}"

  jq -n --arg claim_path "${claim_path}" --argjson claim "${next_json}" \
    '{claim_path: $claim_path, claim: $claim}'
}

release_identity() {
  local identity="${1:?identity is required}"
  local reason="${2:-claim-released}"
  set_state_for_identity "${identity}" terminal "${reason}"
}

cmd_path() {
  local identity=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --identity) identity="${2:-}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  [[ -n "${identity}" ]] || { echo "--identity is required" >&2; exit 2; }
  claim_path_for_identity "${identity}"
}

cmd_status() {
  local identity=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --identity) identity="${2:-}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  [[ -n "${identity}" ]] || { echo "--identity is required" >&2; exit 2; }
  local claim_path
  claim_path="$(claim_path_for_identity "${identity}")"
  if [[ ! -f "${claim_path}" ]]; then
    jq -n --arg identity "${identity}" --arg claim_path "${claim_path}" \
      '{present: false, identity: $identity, claim_path: $claim_path}'
    return 1
  fi
  jq -n --arg claim_path "${claim_path}" --slurpfile claim "${claim_path}" \
    '{present: true, claim_path: $claim_path, claim: $claim[0]}'
}

cmd_list() {
  local active_only=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --active-only) active_only=true; shift ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  ensure_claims_dir
  local files=()
  while IFS= read -r file; do
    files+=("${file}")
  done < <(find "${CLAIMS_DIR}" -maxdepth 1 -type f -name '*.json' | sort)
  if ((${#files[@]} == 0)); then
    printf '[]\n'
    return 0
  fi
  local claims_json='[]'
  local file payload
  for file in "${files[@]}"; do
    payload="$(jq -c --arg claim_path "${file}" '. + {claim_path: $claim_path}' "${file}")"
    claims_json="$(jq -c --argjson claim "${payload}" '. + [$claim]' <<<"${claims_json}")"
  done
  jq --arg active_only "$(bool_string "${active_only}")" '
    if $active_only == "true" then map(select(.claim_active == true and (.status // "") != "terminal")) else . end
    | sort_by(.project // "", .issue_number // 0, .identity // "")
  ' <<<"${claims_json}"
}

cmd_claim() {
  local identity="" project="${KERNEL_PROJECT:-kernel-workspace}" issue_number="" task_key="" run_id=""
  local source="scheduler" reason="dispatchable" refresh_token="" state="claimed"
  local workspace_receipt_path="" envelope_path="" topology_path="" command_string="" provider=""
  local continuity_owner="local-primary" run_driver_pid=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --identity) identity="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      --issue-number) issue_number="${2:-}"; shift 2 ;;
      --task-key) task_key="${2:-}"; shift 2 ;;
      --run-id) run_id="${2:-}"; shift 2 ;;
      --source) source="${2:-}"; shift 2 ;;
      --reason) reason="${2:-}"; shift 2 ;;
      --refresh-token) refresh_token="${2:-}"; shift 2 ;;
      --state) state="${2:-}"; shift 2 ;;
      --workspace-receipt-path) workspace_receipt_path="${2:-}"; shift 2 ;;
      --envelope-path) envelope_path="${2:-}"; shift 2 ;;
      --topology-path) topology_path="${2:-}"; shift 2 ;;
      --command-string) command_string="${2:-}"; shift 2 ;;
      --provider) provider="${2:-}"; shift 2 ;;
      --continuity-owner) continuity_owner="${2:-}"; shift 2 ;;
      --run-driver-pid) run_driver_pid="${2:-}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  identity="$(derive_identity "${identity}" "${project}" "${issue_number}" "${task_key}" "${run_id}")"
  claim_upsert "${identity}" "${project}" "${issue_number}" "${task_key}" "${run_id}" "${source}" "${reason}" "${refresh_token}" "${state}" "${workspace_receipt_path}" "${envelope_path}" "${topology_path}" "${command_string}" "${provider}" "${continuity_owner}" "${run_driver_pid}"
}

cmd_set_state() {
  local identity="" project="${KERNEL_PROJECT:-kernel-workspace}" issue_number="" task_key="" run_id=""
  local requested_state="" reason="state-updated" workspace_receipt_path="" envelope_path=""
  local continuity_owner="" run_driver_pid=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --identity) identity="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      --issue-number) issue_number="${2:-}"; shift 2 ;;
      --task-key) task_key="${2:-}"; shift 2 ;;
      --run-id) run_id="${2:-}"; shift 2 ;;
      --state) requested_state="${2:-}"; shift 2 ;;
      --reason) reason="${2:-}"; shift 2 ;;
      --workspace-receipt-path) workspace_receipt_path="${2:-}"; shift 2 ;;
      --envelope-path) envelope_path="${2:-}"; shift 2 ;;
      --continuity-owner) continuity_owner="${2:-}"; shift 2 ;;
      --run-driver-pid) run_driver_pid="${2:-}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  [[ -n "${requested_state}" ]] || { echo "--state is required" >&2; exit 2; }
  identity="$(derive_identity "${identity}" "${project}" "${issue_number}" "${task_key}" "${run_id}")"
  set_state_for_identity "${identity}" "${requested_state}" "${reason}" "${workspace_receipt_path}" "${envelope_path}" "${continuity_owner}" "${run_driver_pid}"
}

cmd_release() {
  local identity="" project="${KERNEL_PROJECT:-kernel-workspace}" issue_number="" task_key="" run_id=""
  local reason="claim-released"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --identity) identity="${2:-}"; shift 2 ;;
      --project) project="${2:-}"; shift 2 ;;
      --issue-number) issue_number="${2:-}"; shift 2 ;;
      --task-key) task_key="${2:-}"; shift 2 ;;
      --run-id) run_id="${2:-}"; shift 2 ;;
      --reason) reason="${2:-}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  identity="$(derive_identity "${identity}" "${project}" "${issue_number}" "${task_key}" "${run_id}")"
  release_identity "${identity}" "${reason}"
}

cmd_rebuild() {
  local ttl_seconds="${KERNEL_RUNTIME_CLAIM_STALE_TTL_SEC:-3600}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ttl-seconds) ttl_seconds="${2:-}"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
  done
  [[ "${ttl_seconds}" =~ ^[0-9]+$ ]] || ttl_seconds=3600

  local claims_json
  claims_json="$(cmd_list --active-only)"
  local count=0 released=0 updated=0
  while IFS= read -r claim_json; do
    [[ -n "${claim_json}" ]] || continue
    count=$((count + 1))
    local identity run_id claim_path status pid updated_epoch envelope_path live_pid=false age=0 envelope_state envelope_reason ledger_state ledger_reason
    identity="$(jq -r '.identity // ""' <<<"${claim_json}")"
    run_id="$(jq -r '.run_id // ""' <<<"${claim_json}")"
    claim_path="$(jq -r '.claim_path // ""' <<<"${claim_json}")"
    status="$(jq -r '.status // ""' <<<"${claim_json}")"
    pid="$(jq -r '.run_driver_pid // ""' <<<"${claim_json}")"
    updated_epoch="$(jq -r '.updated_at_epoch // 0' <<<"${claim_json}")"
    envelope_path="$(jq -r '.envelope_path // ""' <<<"${claim_json}")"
    if [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
      live_pid=true
    fi
    age="$(( $(epoch_now) - updated_epoch ))"
    if [[ -n "${envelope_path}" && -f "${envelope_path}" ]]; then
      envelope_state="$(jq -r '.scheduler_state // ""' "${envelope_path}")"
      envelope_reason="$(jq -r '.reason // .status_reason // "run-envelope"' "${envelope_path}")"
      if [[ -n "${envelope_state}" ]]; then
        cmd_set_state --identity "${identity}" --state "${envelope_state}" --reason "${envelope_reason}" --envelope-path "${envelope_path}" >/dev/null
        updated=$((updated + 1))
        continue
      fi
    fi
    if [[ -n "${run_id}" && -f "${KERNEL_RUNTIME_LEDGER_FILE:-${STATE_ROOT}/runtime-ledger.json}" ]]; then
      ledger_state="$(jq -r --arg run_id "${run_id}" '.runs[$run_id].scheduler_state // ""' "${KERNEL_RUNTIME_LEDGER_FILE:-${STATE_ROOT}/runtime-ledger.json}" 2>/dev/null || true)"
      ledger_reason="$(jq -r --arg run_id "${run_id}" '.runs[$run_id].scheduler_reason // "runtime-ledger"' "${KERNEL_RUNTIME_LEDGER_FILE:-${STATE_ROOT}/runtime-ledger.json}" 2>/dev/null || true)"
      if [[ "${ledger_state}" == "terminal" ]]; then
        cmd_set_state --identity "${identity}" --state terminal --reason "${ledger_reason}" >/dev/null
        updated=$((updated + 1))
        continue
      fi
    fi
    if [[ "${live_pid}" == "true" ]]; then
      continue
    fi
    if claim_status_active "${status}" && (( age >= ttl_seconds )); then
      cmd_release --identity "${identity}" --reason "stale-claim-released" >/dev/null
      released=$((released + 1))
    fi
  done < <(jq -c '.[]' <<<"${claims_json}")

  jq -n \
    --arg generated_at "$(utc_timestamp)" \
    --argjson scanned "${count}" \
    --argjson released "${released}" \
    --argjson updated "${updated}" \
    '{generated_at: $generated_at, scanned: $scanned, released: $released, updated: $updated}'
}

cmd="${1:-help}"
shift || true
case "${cmd}" in
  path)
    cmd_path "$@"
    ;;
  status)
    cmd_status "$@"
    ;;
  list)
    cmd_list "$@"
    ;;
  claim)
    cmd_claim "$@"
    ;;
  set-state)
    cmd_set_state "$@"
    ;;
  release)
    cmd_release "$@"
    ;;
  rebuild)
    cmd_rebuild "$@"
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
