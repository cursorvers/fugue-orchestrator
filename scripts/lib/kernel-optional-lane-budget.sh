#!/usr/bin/env bash
set -euo pipefail

LEDGER_FILE="${KERNEL_OPTIONAL_LANE_LEDGER_FILE:-$HOME/.config/kernel/optional-lane-usage.json}"

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
      echo "budget ledger lock timeout: ${LOCK_DIR}" >&2
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

  local provider period_type cap run_cap used run_used key
  for provider in gemini-cli cursor-cli copilot-cli; do
    period_type="$(provider_cap_period "${provider}")"
    cap="$(provider_soft_cap "${provider}")"
    run_cap="$(provider_run_cap "${provider}")"
    if [[ "${period_type}" == "day" ]]; then
      key="${day}"
    else
      key="${month}"
    fi
    used="$(provider_period_usage "${provider}" "${period_type}" "${key}")"
    run_used="$(provider_run_usage "${provider}" "${RUN_ID}")"
    printf '  - %s: %s %s/%s, run %s/%s\n' "${provider}" "${period_type}" "${used}" "${cap}" "${run_used}" "${run_cap}"
  done
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

  local provider units note
  provider="$(canonical_provider "${1:-}")"
  units="${2:-1}"
  note="${3:-manual}"

  acquire_lock
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
    ' "${LEDGER_FILE}" >"${LEDGER_FILE}.tmp"
  mv "${LEDGER_FILE}.tmp" "${LEDGER_FILE}"
  release_lock

  cmd_status
}

cmd_consume() {
  ensure_ledger

  local provider units note period_type cap run_cap key used run_used
  provider="$(canonical_provider "${1:-}")"
  units="${2:-1}"
  note="${3:-consume}"

  acquire_lock

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
    release_lock
    printf 'deny %s: %s cap exceeded (%s + %s > %s)\n' "${provider}" "${period_type}" "${used}" "${units}" "${cap}"
    return 1
  fi
  if (( run_used + units > run_cap )); then
    release_lock
    printf 'deny %s: run cap exceeded (%s + %s > %s) [run_id=%s]\n' "${provider}" "${run_used}" "${units}" "${run_cap}" "${RUN_ID}"
    return 1
  fi

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
    ' "${LEDGER_FILE}" >"${LEDGER_FILE}.tmp"
  mv "${LEDGER_FILE}.tmp" "${LEDGER_FILE}"
  release_lock

  printf 'consumed %s: %s %s/%s after request, run %s/%s [run_id=%s]\n' \
    "${provider}" \
    "${period_type}" "$((used + units))" "${cap}" \
    "$((run_used + units))" "${run_cap}" \
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
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown subcommand: ${cmd}" >&2
    usage >&2
    exit 2
    ;;
esac
