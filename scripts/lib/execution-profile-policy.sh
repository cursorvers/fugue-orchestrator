#!/usr/bin/env bash
set -euo pipefail

# Resolve effective execution profile:
# - Primary: subscription-strict (self-hosted runner + subscription CLI)
# - Continuity fallback: api-continuity (GitHub-hosted + harness/API)

requested_engine="subscription"
main_provider="codex"
assist_provider="claude"
force_claude="false"
self_hosted_online="false"
claude_state="ok"
strict_main_requested="false"
strict_opus_requested="false"
claude_direct_available="true"
codex_api_available="true"
api_strict_mode="false"
emergency_continuity_mode="false"
emergency_assist_policy="none"
subscription_offline_policy="continuity"
format="env"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --requested-engine)
      requested_engine="${2:-subscription}"
      shift 2
      ;;
    --main-provider)
      main_provider="${2:-codex}"
      shift 2
      ;;
    --assist-provider)
      assist_provider="${2:-claude}"
      shift 2
      ;;
    --force-claude)
      force_claude="${2:-false}"
      shift 2
      ;;
    --self-hosted-online)
      self_hosted_online="${2:-false}"
      shift 2
      ;;
    --claude-state)
      claude_state="${2:-ok}"
      shift 2
      ;;
    --strict-main-requested)
      strict_main_requested="${2:-false}"
      shift 2
      ;;
    --strict-opus-requested)
      strict_opus_requested="${2:-false}"
      shift 2
      ;;
    --claude-direct-available)
      claude_direct_available="${2:-true}"
      shift 2
      ;;
    --codex-api-available)
      codex_api_available="${2:-true}"
      shift 2
      ;;
    --api-strict-mode)
      api_strict_mode="${2:-false}"
      shift 2
      ;;
    --emergency-continuity-mode)
      emergency_continuity_mode="${2:-false}"
      shift 2
      ;;
    --emergency-assist-policy)
      emergency_assist_policy="${2:-none}"
      shift 2
      ;;
    --subscription-offline-policy)
      subscription_offline_policy="${2:-continuity}"
      shift 2
      ;;
    --format)
      format="${2:-env}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: execution-profile-policy.sh [options]

Options:
  --requested-engine VALUE            Requested execution engine (subscription|harness|api)
  --main-provider VALUE               Resolved main provider (codex|claude)
  --assist-provider VALUE             Resolved assist provider (claude|codex|none)
  --force-claude VALUE                true to bypass assist auto-demotion during continuity fallback
  --self-hosted-online VALUE          true when an online self-hosted runner is available
  --claude-state VALUE                Claude rate-limit state (ok|degraded|exhausted)
  --strict-main-requested VALUE       Requested strict guard for codex main lane
  --strict-opus-requested VALUE       Requested strict guard for claude opus assist lane
  --claude-direct-available VALUE     true when Claude direct execution credential is available
  --codex-api-available VALUE         true when Codex API credential is available for proxy fallback
  --api-strict-mode VALUE             true to keep strict guards active even on api/harness engines
  --emergency-continuity-mode VALUE   true to run inflight-only continuity mode
  --emergency-assist-policy VALUE     Assist policy under continuity fallback (none|codex|claude)
  --subscription-offline-policy VALUE Subscription mode fallback policy when self-hosted is offline (hold|continuity; default continuity)
  --format VALUE                      env (default) or json
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

lower_trim() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

normalize_bool() {
  local v
  v="$(lower_trim "$1")"
  if [[ "${v}" == "true" || "${v}" == "1" || "${v}" == "yes" || "${v}" == "on" ]]; then
    printf '%s' "true"
  else
    printf '%s' "false"
  fi
}

normalize_engine() {
  local v
  v="$(lower_trim "$1")"
  if [[ "${v}" != "subscription" && "${v}" != "harness" && "${v}" != "api" ]]; then
    v="subscription"
  fi
  printf '%s' "${v}"
}

normalize_assist() {
  local v
  v="$(lower_trim "$1")"
  if [[ "${v}" != "claude" && "${v}" != "codex" && "${v}" != "none" ]]; then
    v="none"
  fi
  printf '%s' "${v}"
}

normalize_offline_policy() {
  local v
  v="$(lower_trim "$1")"
  if [[ "${v}" != "hold" && "${v}" != "continuity" ]]; then
    v="continuity"
  fi
  printf '%s' "${v}"
}

resolve_unavailable_claude_fallback() {
  local requested
  requested="$(normalize_assist "$1")"
  if [[ "${requested}" == "none" ]]; then
    printf 'none'
    return
  fi
  # In non-force fallback paths, avoid keeping Claude when direct execution
  # is unavailable in the selected engine/profile.
  if [[ "${requested}" == "claude" ]]; then
    printf 'codex'
    return
  fi
  printf '%s' "${requested}"
}

# Engine-layer guard: claude assist unavailable when rate-limited or direct
# path not reachable.  Separate from orchestrator-policy.sh which handles
# provider selection; this checks engine-specific execution capability.
should_demote_claude_assist() {
  [[ "${assist_provider_effective}" == "claude" \
    && "${force_claude}" != "true" \
    && ( "${claude_state}" != "ok" || "${claude_direct_available}" != "true" ) ]]
}

requested_engine="$(normalize_engine "${requested_engine}")"
assist_provider="$(normalize_assist "${assist_provider}")"
force_claude="$(normalize_bool "${force_claude}")"
self_hosted_online="$(normalize_bool "${self_hosted_online}")"
claude_state="$(lower_trim "${claude_state}")"
if [[ "${claude_state}" != "ok" && "${claude_state}" != "degraded" && "${claude_state}" != "exhausted" ]]; then
  claude_state="ok"
fi
strict_main_requested="$(normalize_bool "${strict_main_requested}")"
strict_opus_requested="$(normalize_bool "${strict_opus_requested}")"
claude_direct_available="$(normalize_bool "${claude_direct_available}")"
codex_api_available="$(normalize_bool "${codex_api_available}")"
api_strict_mode="$(normalize_bool "${api_strict_mode}")"
emergency_continuity_mode="$(normalize_bool "${emergency_continuity_mode}")"
emergency_assist_policy="$(normalize_assist "${emergency_assist_policy}")"
subscription_offline_policy="$(normalize_offline_policy "${subscription_offline_policy}")"

effective_engine="${requested_engine}"
run_agents_runner="ubuntu-latest"
execution_profile="api-standard"
execution_profile_reason="api-engine-explicit"
continuity_active="false"
strict_main_effective="false"
strict_opus_effective="false"
assist_provider_effective="${assist_provider}"
assist_adjusted_by_profile="false"
assist_adjustment_reason=""

if [[ "${requested_engine}" == "subscription" ]]; then
  if [[ "${self_hosted_online}" == "true" ]]; then
    effective_engine="subscription"
    run_agents_runner="self-hosted"
    execution_profile="subscription-strict"
    execution_profile_reason="subscription-self-hosted-online"
    continuity_active="false"
    strict_main_effective="${strict_main_requested}"
    strict_opus_effective="${strict_opus_requested}"
  else
    if [[ "${emergency_continuity_mode}" == "true" || "${subscription_offline_policy}" == "continuity" ]]; then
      effective_engine="harness"
      run_agents_runner="ubuntu-latest"
      execution_profile="api-continuity"
      if [[ "${emergency_continuity_mode}" == "true" ]]; then
        execution_profile_reason="subscription-no-self-hosted-online-emergency-continuity"
      else
        execution_profile_reason="subscription-no-self-hosted-online-continuity-policy"
      fi
      continuity_active="true"
      strict_main_effective="false"
      strict_opus_effective="false"
      if should_demote_claude_assist; then
        assist_provider_effective="$(resolve_unavailable_claude_fallback "${emergency_assist_policy}")"
        assist_adjusted_by_profile="true"
        assist_adjustment_reason="subscription-fallback-assist-claude->${assist_provider_effective}"
      fi
    else
      effective_engine="subscription"
      run_agents_runner="self-hosted"
      execution_profile="subscription-paused"
      execution_profile_reason="subscription-no-self-hosted-online-hold"
      continuity_active="false"
      strict_main_effective="${strict_main_requested}"
      strict_opus_effective="${strict_opus_requested}"
    fi
  fi
else
  run_agents_runner="ubuntu-latest"
  effective_engine="${requested_engine}"
  if [[ "${emergency_continuity_mode}" == "true" ]]; then
    execution_profile="api-continuity"
    execution_profile_reason="emergency-continuity-enabled"
    continuity_active="true"
    if should_demote_claude_assist; then
      assist_provider_effective="$(resolve_unavailable_claude_fallback "${emergency_assist_policy}")"
      assist_adjusted_by_profile="true"
      assist_adjustment_reason="emergency-mode-assist-claude->${assist_provider_effective}"
    fi
  else
    execution_profile="api-standard"
    execution_profile_reason="api-engine-explicit"
    continuity_active="false"
  fi

  if [[ "${api_strict_mode}" == "true" ]]; then
    strict_main_effective="${strict_main_requested}"
    strict_opus_effective="${strict_opus_requested}"
  else
    strict_main_effective="false"
    strict_opus_effective="false"
  fi
fi

# Capability guard for api/harness profiles:
# when assist=claude cannot execute directly, demote to codex (or none) to
# keep resolved assist and executable lanes aligned.
if [[ "${effective_engine}" != "subscription" && "${assist_provider_effective}" == "claude" && "${force_claude}" != "true" && "${claude_direct_available}" != "true" ]]; then
  fallback_target="$(resolve_unavailable_claude_fallback "${emergency_assist_policy}")"
  if [[ "${assist_provider_effective}" != "${fallback_target}" ]]; then
    assist_provider_effective="${fallback_target}"
    assist_adjusted_by_profile="true"
    assist_adjustment_reason="api-capability-assist-claude-unavailable->${assist_provider_effective}"
  fi
fi

if [[ "${format}" == "json" ]]; then
  jq -cn \
    --arg requested_engine "${requested_engine}" \
    --arg subscription_offline_policy "${subscription_offline_policy}" \
    --arg effective_engine "${effective_engine}" \
    --arg run_agents_runner "${run_agents_runner}" \
    --arg execution_profile "${execution_profile}" \
    --arg execution_profile_reason "${execution_profile_reason}" \
    --arg continuity_active "${continuity_active}" \
    --arg strict_main_effective "${strict_main_effective}" \
    --arg strict_opus_effective "${strict_opus_effective}" \
    --arg assist_provider_effective "${assist_provider_effective}" \
    --arg assist_adjusted_by_profile "${assist_adjusted_by_profile}" \
    --arg assist_adjustment_reason "${assist_adjustment_reason}" \
    '{
      requested_engine:$requested_engine,
      subscription_offline_policy:$subscription_offline_policy,
      effective_engine:$effective_engine,
      run_agents_runner:$run_agents_runner,
      execution_profile:$execution_profile,
      execution_profile_reason:$execution_profile_reason,
      continuity_active:($continuity_active == "true"),
      strict_main_effective:($strict_main_effective == "true"),
      strict_opus_effective:($strict_opus_effective == "true"),
      assist_provider_effective:$assist_provider_effective,
      assist_adjusted_by_profile:($assist_adjusted_by_profile == "true"),
      assist_adjustment_reason:$assist_adjustment_reason
    }'
  exit 0
fi

emit_kv() {
  local key="$1"
  local value="$2"
  printf '%s=%q\n' "${key}" "${value}"
}

emit_kv "requested_engine" "${requested_engine}"
emit_kv "subscription_offline_policy" "${subscription_offline_policy}"
emit_kv "effective_engine" "${effective_engine}"
emit_kv "run_agents_runner" "${run_agents_runner}"
emit_kv "execution_profile" "${execution_profile}"
emit_kv "execution_profile_reason" "${execution_profile_reason}"
emit_kv "continuity_active" "${continuity_active}"
emit_kv "strict_main_effective" "${strict_main_effective}"
emit_kv "strict_opus_effective" "${strict_opus_effective}"
emit_kv "assist_provider_effective" "${assist_provider_effective}"
emit_kv "assist_adjusted_by_profile" "${assist_adjusted_by_profile}"
emit_kv "assist_adjustment_reason" "${assist_adjustment_reason}"
