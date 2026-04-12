#!/usr/bin/env bash
set -euo pipefail

event_name="${GITHUB_EVENT_NAME:-schedule}"
force_line_alert="false"
line_alert_message=""
github_repository="${GITHUB_REPOSITORY:-unknown}"
openai_ok="false"
zai_ok="false"
gemini_ok="skipped"
xai_ok="skipped"
anthropic_ok="skipped"
claude_state="ok"
claude_recovered="false"
claude_recover_reason="not-required"
claude_state_age_hours="0"
claude_fallback_mentions_24h="0"
claude_can_manage_variables="false"
claude_max_plan="false"
router_stale="false"
mainframe_stale="false"
failover_state="healthy"
failover_reason="gha-full-mode"
gha_execution_mode="full"
runner_online_count="0"
heartbeat_status="missing"
heartbeat_age_minutes="999999"
router_hours="0"
router_minutes="0"
router_last_success_at=""
mainframe_hours="0"
mainframe_minutes="0"
mainframe_last_success_at=""
pending_count="0"
mainframe_pending_count="0"
persist_state="false"
previous_state_json='{}'
now_epoch=""
tick_seconds="300"
format="json"

usage() {
  cat <<'EOF'
Usage:
  scripts/lib/watchdog-alert-policy.sh [options]

Options:
  --event-name <schedule|workflow_dispatch|...>
  --force-line-alert <true|false>
  --line-alert-message <text>
  --github-repository <owner/repo>
  --openai-ok <true|false>
  --zai-ok <true|false>
  --gemini-ok <true|false|skipped>
  --xai-ok <true|false|skipped>
  --anthropic-ok <true|false|proxy|skipped>
  --claude-state <ok|degraded|exhausted>
  --claude-recovered <true|false>
  --claude-recover-reason <text>
  --claude-state-age-hours <n>
  --claude-fallback-mentions-24h <n>
  --claude-can-manage-variables <true|false>
  --claude-max-plan <true|false>
  --router-stale <true|false>
  --mainframe-stale <true|false>
  --failover-state <healthy|degraded|offline|recovered>
  --failover-reason <text>
  --gha-execution-mode <full|record-only>
  --runner-online-count <n>
  --heartbeat-status <fresh|late|missing|invalid>
  --heartbeat-age-minutes <n>
  --router-hours <n>
  --router-minutes <n>
  --router-last-success-at <iso8601>
  --mainframe-hours <n>
  --mainframe-minutes <n>
  --mainframe-last-success-at <iso8601>
  --pending-count <n>
  --mainframe-pending-count <n>
  --persist-state <true|false>
  --previous-state-json <json>
  --now-epoch <unix-seconds>
  --format <json|env>
  -h, --help
EOF
}

to_bool() {
  local value
  value="$(printf '%s' "${1:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${value}" == "true" || "${value}" == "1" || "${value}" == "yes" || "${value}" == "on" ]]; then
    printf '%s' "true"
  else
    printf '%s' "false"
  fi
}

normalize_int() {
  local value="${1:-}"
  local fallback="${2:-0}"
  if [[ "${value}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${value}"
  else
    printf '%s' "${fallback}"
  fi
}

normalize_state() {
  local value
  value="$(printf '%s' "${1:-ok}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  case "${value}" in
    ok|degraded|exhausted) printf '%s' "${value}" ;;
    *) printf '%s' "ok" ;;
  esac
}

reason_key() {
  local reason="$1"
  printf '%s' "${reason}" | sed 's/[^A-Za-z0-9._-]/_/g'
}

crossed_wall_clock_bucket() {
  local interval_minutes="$1"
  local interval_seconds current_bucket previous_bucket

  if [[ "${event_name}" != "schedule" ]]; then
    return 0
  fi
  if ! [[ "${interval_minutes}" =~ ^[0-9]+$ ]] || (( interval_minutes <= 0 )); then
    return 1
  fi

  interval_seconds=$(( interval_minutes * 60 ))
  current_bucket=$(( now_epoch / interval_seconds ))
  previous_bucket=$(( prev_epoch / interval_seconds ))
  if (( current_bucket != previous_bucket )); then
    return 0
  fi
  return 1
}

is_initial_or_repeat_window() {
  local minutes="$1"
  local initial_minutes="$2"
  local repeat_minutes="$3"
  local window_minutes offset

  window_minutes=$(( tick_seconds / 60 ))
  if (( window_minutes < 5 )); then
    window_minutes=5
  fi

  if ! [[ "${minutes}" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if (( minutes < initial_minutes )); then
    return 1
  fi
  if (( minutes < initial_minutes + window_minutes )); then
    return 0
  fi
  if (( repeat_minutes <= 0 )); then
    return 1
  fi

  offset=$(( minutes - initial_minutes ))
  if (( offset % repeat_minutes < window_minutes )); then
    return 0
  fi
  return 1
}

wall_bucket_key() {
  local interval_minutes="$1"
  printf 'wall:%s:%s' "${interval_minutes}" "$((now_epoch / (interval_minutes * 60)))"
}

stale_bucket_key() {
  local minutes="$1"
  printf 'stale:180:360:%s' "$(((minutes - 180) / 360))"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event-name) event_name="${2:-}"; shift 2 ;;
    --force-line-alert) force_line_alert="${2:-}"; shift 2 ;;
    --line-alert-message) line_alert_message="${2:-}"; shift 2 ;;
    --github-repository) github_repository="${2:-}"; shift 2 ;;
    --openai-ok) openai_ok="${2:-}"; shift 2 ;;
    --zai-ok) zai_ok="${2:-}"; shift 2 ;;
    --gemini-ok) gemini_ok="${2:-}"; shift 2 ;;
    --xai-ok) xai_ok="${2:-}"; shift 2 ;;
    --anthropic-ok) anthropic_ok="${2:-}"; shift 2 ;;
    --claude-state) claude_state="${2:-}"; shift 2 ;;
    --claude-recovered) claude_recovered="${2:-}"; shift 2 ;;
    --claude-recover-reason) claude_recover_reason="${2:-}"; shift 2 ;;
    --claude-state-age-hours) claude_state_age_hours="${2:-}"; shift 2 ;;
    --claude-fallback-mentions-24h) claude_fallback_mentions_24h="${2:-}"; shift 2 ;;
    --claude-can-manage-variables) claude_can_manage_variables="${2:-}"; shift 2 ;;
    --claude-max-plan) claude_max_plan="${2:-}"; shift 2 ;;
    --router-stale) router_stale="${2:-}"; shift 2 ;;
    --mainframe-stale) mainframe_stale="${2:-}"; shift 2 ;;
    --failover-state) failover_state="${2:-}"; shift 2 ;;
    --failover-reason) failover_reason="${2:-}"; shift 2 ;;
    --gha-execution-mode) gha_execution_mode="${2:-}"; shift 2 ;;
    --runner-online-count) runner_online_count="${2:-}"; shift 2 ;;
    --heartbeat-status) heartbeat_status="${2:-}"; shift 2 ;;
    --heartbeat-age-minutes) heartbeat_age_minutes="${2:-}"; shift 2 ;;
    --router-hours) router_hours="${2:-}"; shift 2 ;;
    --router-minutes) router_minutes="${2:-}"; shift 2 ;;
    --router-last-success-at) router_last_success_at="${2:-}"; shift 2 ;;
    --mainframe-hours) mainframe_hours="${2:-}"; shift 2 ;;
    --mainframe-minutes) mainframe_minutes="${2:-}"; shift 2 ;;
    --mainframe-last-success-at) mainframe_last_success_at="${2:-}"; shift 2 ;;
    --pending-count) pending_count="${2:-}"; shift 2 ;;
    --mainframe-pending-count) mainframe_pending_count="${2:-}"; shift 2 ;;
    --persist-state) persist_state="${2:-}"; shift 2 ;;
    --previous-state-json) previous_state_json="${2:-}"; shift 2 ;;
    --now-epoch) now_epoch="${2:-}"; shift 2 ;;
    --format) format="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

force_line_alert="$(to_bool "${force_line_alert}")"
claude_recovered="$(to_bool "${claude_recovered}")"
claude_can_manage_variables="$(to_bool "${claude_can_manage_variables}")"
claude_max_plan="$(to_bool "${claude_max_plan}")"
router_stale="$(to_bool "${router_stale}")"
mainframe_stale="$(to_bool "${mainframe_stale}")"
persist_state="$(to_bool "${persist_state}")"
claude_state="$(normalize_state "${claude_state}")"
runner_online_count="$(normalize_int "${runner_online_count}" "0")"
heartbeat_age_minutes="$(normalize_int "${heartbeat_age_minutes}" "999999")"
router_hours="$(normalize_int "${router_hours}" "0")"
router_minutes="$(normalize_int "${router_minutes}" "0")"
mainframe_hours="$(normalize_int "${mainframe_hours}" "0")"
mainframe_minutes="$(normalize_int "${mainframe_minutes}" "0")"
pending_count="$(normalize_int "${pending_count}" "0")"
mainframe_pending_count="$(normalize_int "${mainframe_pending_count}" "0")"
claude_state_age_hours="$(normalize_int "${claude_state_age_hours}" "0")"
claude_fallback_mentions_24h="$(normalize_int "${claude_fallback_mentions_24h}" "0")"

if [[ -z "${now_epoch}" ]]; then
  now_epoch="$(date -u +%s)"
fi
now_epoch="$(normalize_int "${now_epoch}" "$(date -u +%s)")"
prev_epoch="$((now_epoch - tick_seconds))"

if ! jq -e . >/dev/null 2>&1 <<<"${previous_state_json}"; then
  previous_state_json='{}'
fi
if ! jq -e '.reason_buckets? // {} | type == "object"' >/dev/null 2>&1 <<<"${previous_state_json}"; then
  previous_state_json='{}'
fi

state_json="$(jq -c '.reason_buckets = (.reason_buckets // {})' <<<"${previous_state_json}")"
updated_state_json="${state_json}"
state_update_required="false"

active_reasons=()
due_reasons=()

mark_reason_due() {
  local reason="$1"
  local state_key last_bucket

  active_reasons+=("${reason}")
  if [[ "${persist_state}" == "true" ]]; then
    state_key="$(reason_key "${reason}")"
    last_bucket="$(jq -r --arg key "${state_key}" '.reason_buckets[$key] // ""' <<<"${updated_state_json}")"
    if [[ -z "${last_bucket}" ]]; then
      due_reasons+=("${reason}")
    fi
    if [[ "${last_bucket}" != "active" ]]; then
      updated_state_json="$(jq -c --arg key "${state_key}" --arg value "active" '.reason_buckets[$key] = $value' <<<"${updated_state_json}")"
      state_update_required="true"
    fi
  else
    due_reasons+=("${reason}")
  fi
}

maybe_mark_periodic_reason() {
  local reason="$1"
  local interval_minutes="$2"

  if [[ "${persist_state}" == "true" ]]; then
    mark_reason_due "${reason}"
    return
  fi

  active_reasons+=("${reason}")
  if crossed_wall_clock_bucket "${interval_minutes}"; then
    due_reasons+=("${reason}")
  fi
}

maybe_mark_stale_reason() {
  local reason="$1"
  local hours="$2"
  local minutes="$3"

  if [[ "${hours}" == "9999" ]]; then
    maybe_mark_periodic_reason "${reason}" 360
    return
  fi

  active_reasons+=("${reason}")
  if (( minutes < 180 )); then
    return
  fi

  if [[ "${persist_state}" == "true" ]]; then
    mark_reason_due "${reason}"
    return
  fi

  if is_initial_or_repeat_window "${minutes}" 180 360; then
    due_reasons+=("${reason}")
  fi
}

if [[ "${force_line_alert}" == "true" ]]; then
  active_reasons=("manual-force-line")
  due_reasons=("manual-force-line")
else
  if [[ "${event_name}" == "schedule" ]]; then
    if [[ "${openai_ok}" != "true" || "${zai_ok}" != "true" || ( "${gemini_ok}" != "true" && "${gemini_ok}" != "skipped" ) || ( "${xai_ok}" != "true" && "${xai_ok}" != "skipped" ) ]]; then
      if [[ "${pending_count}" != "0" || "${mainframe_pending_count}" != "0" ]]; then
        maybe_mark_periodic_reason "connectivity" 180
      else
        maybe_mark_periodic_reason "connectivity" 360
      fi
    fi

    if [[ "${claude_state}" != "exhausted" && "${anthropic_ok}" == "false" && "${claude_max_plan}" != "true" ]]; then
      if [[ "${pending_count}" != "0" || "${mainframe_pending_count}" != "0" ]]; then
        maybe_mark_periodic_reason "claude-assist-unavailable" 180
      fi
    fi

    if [[ "${claude_state}" != "ok" && ( "${pending_count}" != "0" || "${mainframe_pending_count}" != "0" ) ]]; then
      maybe_mark_periodic_reason "claude-rate-limit-${claude_state}" 180
    fi

    if [[ "${failover_state}" == "offline" && ( "${pending_count}" != "0" || "${mainframe_pending_count}" != "0" ) ]]; then
      maybe_mark_periodic_reason "primary-offline" 180
    elif [[ "${failover_state}" == "degraded" && ( "${pending_count}" != "0" || "${mainframe_pending_count}" != "0" ) ]]; then
      maybe_mark_periodic_reason "primary-degraded" 360
    fi

    if [[ "${router_stale}" == "true" ]]; then
      maybe_mark_stale_reason "router-stale" "${router_hours}" "${router_minutes}"
    fi

    if [[ "${mainframe_stale}" == "true" ]]; then
      maybe_mark_stale_reason "mainframe-stale" "${mainframe_hours}" "${mainframe_minutes}"
    fi
  fi
fi

should_alert="false"
if (( ${#due_reasons[@]} > 0 )); then
  should_alert="true"
fi

if [[ "${persist_state}" == "true" ]]; then
  if (( ${#active_reasons[@]} > 0 )); then
    active_reason_keys_json="$(jq -cn '$ARGS.positional' --args "${active_reasons[@]}")"
  else
    active_reason_keys_json='[]'
  fi
  pruned_state_json="$(jq -c --argjson active_keys "${active_reason_keys_json}" '
    .reason_buckets |= with_entries(select(.key as $key | ($active_keys | index($key)) != null))
  ' <<<"${updated_state_json}")"
  if [[ "${pruned_state_json}" != "${updated_state_json}" ]]; then
    updated_state_json="${pruned_state_json}"
    state_update_required="true"
  fi
fi

active_reasons_text="none"
active_reasons_csv=""
if (( ${#active_reasons[@]} > 0 )); then
  active_reasons_text="${active_reasons[*]}"
  active_reasons_csv="$(IFS=,; printf '%s' "${active_reasons[*]}")"
fi

due_reasons_text="none"
due_reasons_csv=""
if (( ${#due_reasons[@]} > 0 )); then
  due_reasons_text="${due_reasons[*]}"
  due_reasons_csv="$(IFS=,; printf '%s' "${due_reasons[*]}")"
fi

message="fugue-watchdog alert
repo: ${github_repository}
reasons: ${active_reasons_text}
claude_rate_limit_state: ${claude_state}
claude_rate_limit_auto_recovered: ${claude_recovered}
claude_rate_limit_recover_reason: ${claude_recover_reason}
claude_rate_limit_manage_variables_enabled: ${claude_can_manage_variables}
claude_rate_limit_state_age_hours: ${claude_state_age_hours}
claude_fallback_mentions_24h: ${claude_fallback_mentions_24h}
claude_max_plan_mode: ${claude_max_plan}
gha_execution_mode: ${gha_execution_mode}
failover_state: ${failover_state}
failover_reason: ${failover_reason}
primary_runner_online_count: ${runner_online_count}
primary_heartbeat_status: ${heartbeat_status}
primary_heartbeat_age_minutes: ${heartbeat_age_minutes}
openai_ok: ${openai_ok}
zai_ok: ${zai_ok}
gemini_ok: ${gemini_ok}
xai_ok: ${xai_ok}
anthropic_ok: ${anthropic_ok}
pending_count: ${pending_count}
mainframe_pending_count: ${mainframe_pending_count}
watchdog_alert_state_persist: ${persist_state}
watchdog_alert_due_reasons: ${due_reasons_text}
router_hours_since_success: ${router_hours}
router_minutes_since_success: ${router_minutes}
router_last_success_at: ${router_last_success_at}
mainframe_hours_since_success: ${mainframe_hours}
mainframe_minutes_since_success: ${mainframe_minutes}
mainframe_last_success_at: ${mainframe_last_success_at}"

if [[ "${force_line_alert}" == "true" && -n "${line_alert_message}" ]]; then
  message="${line_alert_message}"
fi

bucket_180_now="$((now_epoch / 10800))"
bucket_180_prev="$((prev_epoch / 10800))"
bucket_360_now="$((now_epoch / 21600))"
bucket_360_prev="$((prev_epoch / 21600))"

if [[ "${format}" == "env" ]]; then
  message_base64="$(printf '%s' "${message}" | base64 | tr -d '\n')"
  cat <<EOF
should_alert=${should_alert}
force_line_alert=${force_line_alert}
persist_state=${persist_state}
active_reasons_csv=${active_reasons_csv}
due_reasons_csv=${due_reasons_csv}
state_update_required=${state_update_required}
bucket_180_now=${bucket_180_now}
bucket_180_prev=${bucket_180_prev}
bucket_360_now=${bucket_360_now}
bucket_360_prev=${bucket_360_prev}
message_base64=${message_base64}
next_state_json=$(printf '%s' "${updated_state_json}" | jq -c .)
EOF
  exit 0
fi

jq -cn \
  --arg should_alert "${should_alert}" \
  --arg force_line_alert "${force_line_alert}" \
  --arg persist_state "${persist_state}" \
  --arg active_reasons_csv "${active_reasons_csv}" \
  --arg due_reasons_csv "${due_reasons_csv}" \
  --arg state_update_required "${state_update_required}" \
  --arg message "${message}" \
  --arg claude_state "${claude_state}" \
  --arg failover_state "${failover_state}" \
  --arg gha_execution_mode "${gha_execution_mode}" \
  --arg router_stale "${router_stale}" \
  --arg mainframe_stale "${mainframe_stale}" \
  --arg router_minutes "${router_minutes}" \
  --arg mainframe_minutes "${mainframe_minutes}" \
  --arg bucket_180_now "${bucket_180_now}" \
  --arg bucket_180_prev "${bucket_180_prev}" \
  --arg bucket_360_now "${bucket_360_now}" \
  --arg bucket_360_prev "${bucket_360_prev}" \
  --argjson next_state "${updated_state_json}" \
  '{
    should_alert: ($should_alert == "true"),
    force_line_alert: ($force_line_alert == "true"),
    persist_state: ($persist_state == "true"),
    active_reasons: (if $active_reasons_csv == "" then [] else ($active_reasons_csv | split(",")) end),
    due_reasons: (if $due_reasons_csv == "" then [] else ($due_reasons_csv | split(",")) end),
    state_update_required: ($state_update_required == "true"),
    next_state: $next_state,
    message: $message,
    claude_state: $claude_state,
    failover_state: $failover_state,
    gha_execution_mode: $gha_execution_mode,
    router_stale: ($router_stale == "true"),
    mainframe_stale: ($mainframe_stale == "true"),
    router_minutes: ($router_minutes | tonumber),
    mainframe_minutes: ($mainframe_minutes | tonumber),
    bucket_180_now: ($bucket_180_now | tonumber),
    bucket_180_prev: ($bucket_180_prev | tonumber),
    bucket_360_now: ($bucket_360_now | tonumber),
    bucket_360_prev: ($bucket_360_prev | tonumber)
  }'
