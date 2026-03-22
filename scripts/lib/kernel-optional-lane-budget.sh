#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
LEDGER_FILE="${KERNEL_OPTIONAL_LANE_LEDGER_FILE:-$(bash "${STATE_PATH_SCRIPT}" optional-lane-ledger-file)}"

GEMINI_DAILY_SOFT_CAP="${KERNEL_GEMINI_DAILY_SOFT_CAP:-200}"
GEMINI_PER_RUN_SOFT_CAP="${KERNEL_GEMINI_PER_RUN_SOFT_CAP:-20}"
CURSOR_MONTHLY_SOFT_CAP="${KERNEL_CURSOR_MONTHLY_SOFT_CAP:-20}"
CURSOR_PER_RUN_SOFT_CAP="${KERNEL_CURSOR_PER_RUN_SOFT_CAP:-1}"
COPILOT_MONTHLY_SOFT_CAP="${KERNEL_COPILOT_MONTHLY_SOFT_CAP:-12}"
COPILOT_PER_RUN_SOFT_CAP="${KERNEL_COPILOT_PER_RUN_SOFT_CAP:-1}"
LOCK_DIR="${KERNEL_OPTIONAL_LANE_LOCK_DIR:-${LEDGER_FILE}.lock}"
LOCK_OWNER_FILE="${LOCK_DIR}/owner.pid"
LOCK_HELD=0
ALLOW_NONATOMIC_BUDGET="${KERNEL_ALLOW_NONATOMIC_BUDGET:-false}"
source "${SCRIPT_DIR}/kernel-lock.sh"

repo_slug() {
  if [[ -n "${KERNEL_REPO_SLUG:-}" ]]; then
    printf '%s\n' "${KERNEL_REPO_SLUG}"
    return 0
  fi
  printf 'kernel-workspace\n'
}

default_run_id() {
  local repo host session_name
  repo="$(repo_slug)"
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
  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    session_name="$(tmux display-message -p '#S' 2>/dev/null || true)"
    if [[ -n "${session_name}" ]]; then
      printf '%s:%s\n' "${repo}" "${session_name}"
      return 0
    fi
  fi
  host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown-host')"
  printf 'adhoc:%s:%s:%s\n' "${host}" "${repo}" "${PPID:-$$}"
}

RUN_ID="$(default_run_id)"
export KERNEL_RUN_ID="${RUN_ID}"

usage() {
  cat <<'EOF'
Usage:
  kernel-optional-lane-budget.sh status
  kernel-optional-lane-budget.sh can-use <provider> [units]
  kernel-optional-lane-budget.sh record <provider> [units] [note]
  kernel-optional-lane-budget.sh consume <provider> [units] [note]
  kernel-optional-lane-budget.sh refund <provider> [units] [note]
EOF
}

canonical_provider() {
  case "${1:-}" in
    gemini|gemini-cli) printf 'gemini-cli\n' ;;
    cursor|cursor-cli) printf 'cursor-cli\n' ;;
    copilot|copilot-cli) printf 'copilot-cli\n' ;;
    *)
      printf 'unknown\n'
      return 1
      ;;
  esac
}

ensure_ledger() {
  mkdir -p "$(dirname "${LEDGER_FILE}")"
  if [[ ! -f "${LEDGER_FILE}" ]]; then
    printf '{\n  "version": 1,\n  "events": []\n}\n' >"${LEDGER_FILE}"
  fi
}

trap cleanup_lock EXIT INT TERM

today_key() {
  date '+%Y-%m-%d'
}

month_key() {
  date '+%Y-%m'
}

utc_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

provider_cap_period() {
  case "$1" in
    gemini-cli) printf 'day\n' ;;
    cursor-cli|copilot-cli) printf 'month\n' ;;
    *)
      return 1
      ;;
  esac
}

provider_soft_cap() {
  case "$1" in
    gemini-cli) printf '%s\n' "${GEMINI_DAILY_SOFT_CAP}" ;;
    cursor-cli) printf '%s\n' "${CURSOR_MONTHLY_SOFT_CAP}" ;;
    copilot-cli) printf '%s\n' "${COPILOT_MONTHLY_SOFT_CAP}" ;;
    *)
      return 1
      ;;
  esac
}

provider_run_cap() {
  case "$1" in
    gemini-cli) printf '%s\n' "${GEMINI_PER_RUN_SOFT_CAP}" ;;
    cursor-cli) printf '%s\n' "${CURSOR_PER_RUN_SOFT_CAP}" ;;
    copilot-cli) printf '%s\n' "${COPILOT_PER_RUN_SOFT_CAP}" ;;
    *)
      return 1
      ;;
  esac
}

provider_period_usage() {
  local provider="$1"
  local period_type="$2"
  local key="$3"

  jq -r --arg provider "${provider}" --arg period_type "${period_type}" --arg key "${key}" '
    [
      .events[]
      | select(.provider == $provider)
      | select(
          ($period_type == "day" and (.day // "") == $key)
          or
          ($period_type == "month" and (.month // "") == $key)
        )
      | (.units // 0)
    ] | add // 0
  ' "${LEDGER_FILE}"
}

provider_run_usage() {
  local provider="$1"
  local run_id="$2"

  jq -r --arg provider "${provider}" --arg run_id "${run_id}" '
    [
      .events[]
      | select(.provider == $provider and (.run_id // "") == $run_id)
      | (.units // 0)
    ] | add // 0
  ' "${LEDGER_FILE}"
}

cmd_status() {
  ensure_ledger

  local day month
  day="$(today_key)"
  month="$(month_key)"

  printf 'ledger file: %s\n' "${LEDGER_FILE}"
  printf 'run id: %s\n' "${RUN_ID}"
  printf 'usage status:\n'

  local stats_tsv
  stats_tsv="$(jq -r --arg day "${day}" --arg month "${month}" --arg run_id "${RUN_ID}" '
    .events as $ev |
    def period_usage(prov; ptype; key):
      [$ev[] | select(.provider == prov)
        | select((ptype == "day" and (.day // "") == key)
                or (ptype == "month" and (.month // "") == key))
        | (.units // 0)] | add // 0;
    def run_usage(prov):
      [$ev[] | select(.provider == prov and (.run_id // "") == $run_id)
        | (.units // 0)] | add // 0;
    [
      ["gemini-cli",  "day",   (period_usage("gemini-cli";  "day";   $day)   | tostring), (run_usage("gemini-cli")  | tostring)],
      ["cursor-cli",  "month", (period_usage("cursor-cli";  "month"; $month) | tostring), (run_usage("cursor-cli")  | tostring)],
      ["copilot-cli", "month", (period_usage("copilot-cli"; "month"; $month) | tostring), (run_usage("copilot-cli") | tostring)]
    ] | .[] | @tsv
  ' "${LEDGER_FILE}")"

  local provider period_type used run_used cap run_cap
  while IFS=$'\t' read -r provider period_type used run_used; do
    cap="$(provider_soft_cap "${provider}")"
    run_cap="$(provider_run_cap "${provider}")"
    printf '  - %s: %s %s/%s, run %s/%s\n' "${provider}" "${period_type}" "${used}" "${cap}" "${run_used}" "${run_cap}"
  done <<<"${stats_tsv}"
}

cmd_can_use() {
  if [[ "${ALLOW_NONATOMIC_BUDGET}" != "true" ]]; then
    echo "non-atomic budget-can-use is disabled; use consume or set KERNEL_ALLOW_NONATOMIC_BUDGET=true" >&2
    exit 3
  fi
  ensure_ledger

  local provider units period_type cap run_cap key used run_used
  provider="$(canonical_provider "${1:-}")"
  units="${2:-1}"

  period_type="$(provider_cap_period "${provider}")"
  cap="$(provider_soft_cap "${provider}")"
  run_cap="$(provider_run_cap "${provider}")"
  if [[ "${period_type}" == "day" ]]; then
    key="$(today_key)"
  else
    key="$(month_key)"
  fi
  used="$(provider_period_usage "${provider}" "${period_type}" "${key}")"
  run_used="$(provider_run_usage "${provider}" "${RUN_ID}")"

  if (( used + units > cap )); then
    printf 'deny %s: %s cap exceeded (%s + %s > %s)\n' "${provider}" "${period_type}" "${used}" "${units}" "${cap}"
    return 1
  fi
  if (( run_used + units > run_cap )); then
    printf 'deny %s: run cap exceeded (%s + %s > %s) [run_id=%s]\n' "${provider}" "${run_used}" "${units}" "${run_cap}" "${RUN_ID}"
    return 1
  fi

  printf 'allow %s: %s %s/%s after request, run %s/%s [run_id=%s]\n' \
    "${provider}" \
    "${period_type}" "$((used + units))" "${cap}" \
    "$((run_used + units))" "${run_cap}" \
    "${RUN_ID}"
}

cmd_record() {
  if [[ "${ALLOW_NONATOMIC_BUDGET}" != "true" ]]; then
    echo "non-atomic budget-record is disabled; use consume or set KERNEL_ALLOW_NONATOMIC_BUDGET=true" >&2
    exit 3
  fi
  ensure_ledger

  local provider units note tmp_file
  provider="$(canonical_provider "${1:-}")"
  units="${2:-1}"
  note="${3:-manual}"

  acquire_lock "budget ledger"
  tmp_file="${LEDGER_FILE}.tmp.$$.$RANDOM"
  jq \
    --arg provider "${provider}" \
    --arg run_id "${RUN_ID}" \
    --arg recorded_at "$(utc_timestamp)" \
    --arg day "$(today_key)" \
    --arg month "$(month_key)" \
    --arg note "${note}" \
    --argjson units "${units}" \
    '
      .events += [{
        provider: $provider,
        units: $units,
        run_id: $run_id,
        recorded_at: $recorded_at,
        day: $day,
        month: $month,
        note: $note
      }]
    ' "${LEDGER_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${LEDGER_FILE}"
  release_lock

  cmd_status
}

cmd_consume() {
  ensure_ledger

  local provider units note period_type cap run_cap key used run_used
  provider="$(canonical_provider "${1:-}")"
  units="${2:-1}"
  note="${3:-consume}"

  acquire_lock "budget ledger"

  period_type="$(provider_cap_period "${provider}")"
  cap="$(provider_soft_cap "${provider}")"
  run_cap="$(provider_run_cap "${provider}")"
  if [[ "${period_type}" == "day" ]]; then
    key="$(today_key)"
  else
    key="$(month_key)"
  fi

  local consume_result
  consume_result="$(jq -r \
    --arg provider "${provider}" \
    --arg run_id "${RUN_ID}" \
    --arg recorded_at "$(utc_timestamp)" \
    --arg day "$(today_key)" \
    --arg month "$(month_key)" \
    --arg note "${note}" \
    --arg period_type "${period_type}" \
    --arg key "${key}" \
    --argjson units "${units}" \
    --argjson cap "${cap}" \
    --argjson run_cap "${run_cap}" \
    '
      .events as $ev |
      ([$ev[] | select(.provider == $provider)
        | select(($period_type == "day" and (.day // "") == $key)
                or ($period_type == "month" and (.month // "") == $key))
        | (.units // 0)] | add // 0) as $used |
      ([$ev[] | select(.provider == $provider and (.run_id // "") == $run_id)
        | (.units // 0)] | add // 0) as $run_used |
      if ($used + $units) > $cap then
        "DENY_PERIOD\t\($used)\t\($run_used)"
      elif ($run_used + $units) > $run_cap then
        "DENY_RUN\t\($used)\t\($run_used)"
      else
        (.events += [{
          provider: $provider,
          units: $units,
          run_id: $run_id,
          recorded_at: $recorded_at,
          day: $day,
          month: $month,
          note: $note
        }]) | "OK\t\($used)\t\($run_used)\n\(. | tojson)"
      end
    ' "${LEDGER_FILE}")"

  local verdict
  verdict="$(head -1 <<<"${consume_result}")"
  local v_status v_used v_run_used
  IFS=$'\t' read -r v_status v_used v_run_used <<<"${verdict}"
  used="${v_used}"
  run_used="${v_run_used}"

  case "${v_status}" in
    DENY_PERIOD)
      release_lock
      printf 'deny %s: %s cap exceeded (%s + %s > %s)\n' "${provider}" "${period_type}" "${used}" "${units}" "${cap}"
      return 1
      ;;
    DENY_RUN)
      release_lock
      printf 'deny %s: run cap exceeded (%s + %s > %s) [run_id=%s]\n' "${provider}" "${run_used}" "${units}" "${run_cap}" "${RUN_ID}"
      return 1
      ;;
    OK)
      # Second line onward is the updated JSON
      local tmp_file="${LEDGER_FILE}.tmp.$$.$RANDOM"
      tail -n +2 <<<"${consume_result}" >"${tmp_file}"
      mv "${tmp_file}" "${LEDGER_FILE}"
      release_lock
      printf 'consumed %s: %s %s/%s after request, run %s/%s [run_id=%s]\n' \
        "${provider}" \
        "${period_type}" "$((used + units))" "${cap}" \
        "$((run_used + units))" "${run_cap}" \
        "${RUN_ID}"
      ;;
  esac
}

cmd_refund() {
  ensure_ledger

  local provider units note period_type cap run_cap key used run_used
  provider="$(canonical_provider "${1:-}")"
  units="${2:-1}"
  note="${3:-refund}"

  acquire_lock "budget ledger"

  period_type="$(provider_cap_period "${provider}")"
  cap="$(provider_soft_cap "${provider}")"
  run_cap="$(provider_run_cap "${provider}")"
  if [[ "${period_type}" == "day" ]]; then
    key="$(today_key)"
  else
    key="$(month_key)"
  fi

  used="$(provider_period_usage "${provider}" "${period_type}" "${key}")"
  run_used="$(provider_run_usage "${provider}" "${RUN_ID}")"
  if (( used < units || run_used < units )); then
    release_lock
    printf 'deny refund %s: insufficient recorded usage (%s, run %s, refund %s) [run_id=%s]\n' \
      "${provider}" "${used}" "${run_used}" "${units}" "${RUN_ID}"
    return 1
  fi

  local tmp_file="${LEDGER_FILE}.tmp.$$.$RANDOM"
  jq \
    --arg provider "${provider}" \
    --arg run_id "${RUN_ID}" \
    --arg recorded_at "$(utc_timestamp)" \
    --arg day "$(today_key)" \
    --arg month "$(month_key)" \
    --arg note "${note}" \
    --argjson units "${units}" \
    '
      .events += [{
        provider: $provider,
        units: (-$units),
        run_id: $run_id,
        recorded_at: $recorded_at,
        day: $day,
        month: $month,
        note: $note
      }]
    ' "${LEDGER_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${LEDGER_FILE}"
  release_lock

  printf 'refunded %s: %s %s/%s after refund, run %s/%s [run_id=%s]\n' \
    "${provider}" \
    "${period_type}" "$((used - units))" "${cap}" \
    "$((run_used - units))" "${run_cap}" \
    "${RUN_ID}"
}

cmd="${1:-status}"
case "${cmd}" in
  status)
    shift || true
    cmd_status "$@"
    ;;
  can-use)
    shift || true
    cmd_can_use "$@"
    ;;
  record)
    shift || true
    cmd_record "$@"
    ;;
  consume)
    shift || true
    cmd_consume "$@"
    ;;
  refund)
    shift || true
    cmd_refund "$@"
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
