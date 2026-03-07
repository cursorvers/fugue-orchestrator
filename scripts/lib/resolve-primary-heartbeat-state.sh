#!/usr/bin/env bash
set -euo pipefail

gha_execution_mode="full"
current_state="healthy"
runner_online_count="0"
pending_count="0"
mainframe_pending_count="0"
router_stale="false"
mainframe_stale="false"
heartbeat_at=""
heartbeat_ttl_minutes="8"
heartbeat_grace_multiplier="3"
heartbeat_future_skew_seconds="300"
format="env"

usage() {
  cat <<'EOF'
Usage:
  scripts/lib/resolve-primary-heartbeat-state.sh [options]

Options:
  --gha-execution-mode <full|record-only>
  --current-state <healthy|degraded|offline|recovered>
  --runner-online-count <n>
  --pending-count <n>
  --mainframe-pending-count <n>
  --router-stale <true|false>
  --mainframe-stale <true|false>
  --heartbeat-at <ISO8601>
  --heartbeat-ttl-minutes <n>
  --heartbeat-grace-multiplier <n>
  --heartbeat-future-skew-seconds <n>
  --format <env|json>
  -h, --help
EOF
}

normalize_bool() {
  local value
  value="$(echo "${1:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${value}" == "true" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

epoch_now_utc() {
  date -u +%s
}

iso_to_epoch_utc() {
  local iso="$1"
  if date -u -d "${iso}" +%s >/dev/null 2>&1; then
    date -u -d "${iso}" +%s
  elif date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${iso}" +%s >/dev/null 2>&1; then
    date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${iso}" +%s
  else
    return 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gha-execution-mode)
      gha_execution_mode="${2:-}"
      shift 2
      ;;
    --current-state)
      current_state="${2:-}"
      shift 2
      ;;
    --runner-online-count)
      runner_online_count="${2:-}"
      shift 2
      ;;
    --pending-count)
      pending_count="${2:-}"
      shift 2
      ;;
    --mainframe-pending-count)
      mainframe_pending_count="${2:-}"
      shift 2
      ;;
    --router-stale)
      router_stale="${2:-}"
      shift 2
      ;;
    --mainframe-stale)
      mainframe_stale="${2:-}"
      shift 2
      ;;
    --heartbeat-at)
      heartbeat_at="${2:-}"
      shift 2
      ;;
    --heartbeat-ttl-minutes)
      heartbeat_ttl_minutes="${2:-}"
      shift 2
      ;;
    --heartbeat-grace-multiplier)
      heartbeat_grace_multiplier="${2:-}"
      shift 2
      ;;
    --heartbeat-future-skew-seconds)
      heartbeat_future_skew_seconds="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

gha_execution_mode="$(echo "${gha_execution_mode}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${gha_execution_mode}" != "record-only" ]]; then
  gha_execution_mode="full"
fi

current_state="$(echo "${current_state}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
case "${current_state}" in
  healthy|degraded|offline|recovered) ;;
  *) current_state="healthy" ;;
esac

if ! [[ "${runner_online_count}" =~ ^[0-9]+$ ]]; then
  runner_online_count="0"
fi
if ! [[ "${pending_count}" =~ ^[0-9]+$ ]]; then
  pending_count="0"
fi
if ! [[ "${mainframe_pending_count}" =~ ^[0-9]+$ ]]; then
  mainframe_pending_count="0"
fi
if ! [[ "${heartbeat_ttl_minutes}" =~ ^[0-9]+$ ]] || [[ "${heartbeat_ttl_minutes}" == "0" ]]; then
  heartbeat_ttl_minutes="8"
fi
if ! [[ "${heartbeat_grace_multiplier}" =~ ^[0-9]+$ ]] || [[ "${heartbeat_grace_multiplier}" == "0" ]]; then
  heartbeat_grace_multiplier="3"
fi
if ! [[ "${heartbeat_future_skew_seconds}" =~ ^[0-9]+$ ]]; then
  heartbeat_future_skew_seconds="300"
fi

router_stale="$(normalize_bool "${router_stale}")"
mainframe_stale="$(normalize_bool "${mainframe_stale}")"

heartbeat_status="missing"
heartbeat_age_minutes="999999"
heartbeat_epoch=""
now_epoch="$(epoch_now_utc)"

if [[ -n "${heartbeat_at}" ]]; then
  if heartbeat_epoch="$(iso_to_epoch_utc "${heartbeat_at}" 2>/dev/null)"; then
    age_seconds=$((now_epoch - heartbeat_epoch))
    if (( age_seconds < 0 - heartbeat_future_skew_seconds )); then
      heartbeat_status="invalid"
    elif (( age_seconds < 0 )); then
      age_seconds=0
    fi
    if [[ "${heartbeat_status}" != "invalid" ]]; then
      heartbeat_age_minutes="$(((age_seconds + 59) / 60))"
      heartbeat_status="missing"
      if (( heartbeat_age_minutes <= heartbeat_ttl_minutes )); then
        heartbeat_status="fresh"
      elif (( heartbeat_age_minutes <= heartbeat_ttl_minutes * heartbeat_grace_multiplier )); then
        heartbeat_status="late"
      fi
    fi
  else
    heartbeat_status="invalid"
  fi
fi

has_pressure="false"
if [[ "${pending_count}" != "0" || "${mainframe_pending_count}" != "0" || "${router_stale}" == "true" || "${mainframe_stale}" == "true" ]]; then
  has_pressure="true"
fi

failover_state="healthy"
failover_reason="gha-full-mode"
backup_router_execution_mode="auto"

if [[ "${gha_execution_mode}" == "record-only" ]]; then
  case "${heartbeat_status}" in
    fresh)
      if [[ "${current_state}" == "offline" || "${current_state}" == "degraded" ]]; then
        failover_state="recovered"
        failover_reason="primary-heartbeat-fresh-after-failover"
      else
        failover_state="healthy"
        failover_reason="primary-heartbeat-fresh"
      fi
      ;;
    late)
      failover_state="degraded"
      failover_reason="primary-heartbeat-late"
      ;;
    missing|invalid)
      if (( runner_online_count > 0 )); then
        failover_state="degraded"
        failover_reason="primary-runner-online-heartbeat-${heartbeat_status}"
      elif [[ "${has_pressure}" == "true" ]]; then
        failover_state="offline"
        failover_reason="primary-heartbeat-${heartbeat_status}-no-runner-pending-work"
        backup_router_execution_mode="backup-safe"
      else
        failover_state="degraded"
        failover_reason="primary-heartbeat-${heartbeat_status}-no-runner-no-pending-work"
      fi
      ;;
  esac
fi

if [[ "${format}" == "json" ]]; then
  jq -cn \
    --arg gha_execution_mode "${gha_execution_mode}" \
    --arg current_state "${current_state}" \
    --arg failover_state "${failover_state}" \
    --arg failover_reason "${failover_reason}" \
    --arg backup_router_execution_mode "${backup_router_execution_mode}" \
    --arg heartbeat_status "${heartbeat_status}" \
    --arg heartbeat_age_minutes "${heartbeat_age_minutes}" \
    --arg runner_online_count "${runner_online_count}" \
    --arg pending_count "${pending_count}" \
    --arg mainframe_pending_count "${mainframe_pending_count}" \
    --arg has_pressure "${has_pressure}" \
    '{
      gha_execution_mode: $gha_execution_mode,
      current_state: $current_state,
      failover_state: $failover_state,
      failover_reason: $failover_reason,
      backup_router_execution_mode: $backup_router_execution_mode,
      heartbeat_status: $heartbeat_status,
      heartbeat_age_minutes: ($heartbeat_age_minutes | tonumber),
      runner_online_count: ($runner_online_count | tonumber),
      pending_count: ($pending_count | tonumber),
      mainframe_pending_count: ($mainframe_pending_count | tonumber),
      has_pressure: ($has_pressure == "true")
    }'
else
  cat <<EOF
gha_execution_mode=${gha_execution_mode}
current_state=${current_state}
failover_state=${failover_state}
failover_reason=${failover_reason}
backup_router_execution_mode=${backup_router_execution_mode}
heartbeat_status=${heartbeat_status}
heartbeat_age_minutes=${heartbeat_age_minutes}
runner_online_count=${runner_online_count}
pending_count=${pending_count}
mainframe_pending_count=${mainframe_pending_count}
has_pressure=${has_pressure}
EOF
fi
