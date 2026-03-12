#!/usr/bin/env bash
set -euo pipefail

# run-canary.sh — Canary verification for FUGUE orchestration pipeline.
#
# Creates canary issues, dispatches tutti-caller, waits for integrated review,
# and verifies that resolved orchestrator/profile/runner match expectations.
#
# Required env vars:
#   GH_TOKEN, GITHUB_REPOSITORY,
#   CLAUDE_RATE_LIMIT_STATE, CLAUDE_ROLE_POLICY,
#   CLAUDE_DEGRADED_ASSIST_POLICY, CLAUDE_MAIN_ASSIST_POLICY,
#   CI_EXECUTION_ENGINE, SUBSCRIPTION_OFFLINE_POLICY,
#   CANARY_OFFLINE_POLICY_OVERRIDE, EMERGENCY_CONTINUITY_MODE,
#   SUBSCRIPTION_RUNNER_LABEL, EMERGENCY_ASSIST_POLICY,
#   API_STRICT_MODE, HAS_ANTHROPIC_API_KEY, HAS_OPENAI_API_KEY,
#   DEFAULT_MAIN_ORCHESTRATOR_PROVIDER, EXECUTION_PROVIDER_DEFAULT,
#   CANARY_ALTERNATE_PROVIDER, CANARY_PRIMARY_HANDOFF_TARGET,
#   CANARY_VERIFY_ROLLBACK, LEGACY_MAIN_ORCHESTRATOR_PROVIDER,
#   LEGACY_ASSIST_ORCHESTRATOR_PROVIDER, LEGACY_FORCE_CLAUDE,
#   CANARY_LABEL_WAIT_ATTEMPTS, CANARY_LABEL_WAIT_SLEEP_SEC,
#   CANARY_WAIT_FAST_ATTEMPTS, CANARY_WAIT_FAST_SLEEP_SEC,
#   CANARY_WAIT_SLOW_ATTEMPTS, CANARY_WAIT_SLOW_SLEEP_SEC
#
# Optional env vars:
#   OPS_TOKEN            — preferred over GH_TOKEN for issue operations
#   CANARY_MODE_INPUT    — full (default) or lite
#   CANARY_EXECUTION_MODE_OVERRIDE — canary dispatch override (default: primary)
#   CANARY_PLAN_ONLY     — true to print resolved cases without touching GitHub
#
# Usage: bash scripts/harness/run-canary.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common-utils.sh"

# --- Helper functions ---

gh_timeout_cmd() {
  local duration="${1:-30s}"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout --preserve-status "${duration}" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout --preserve-status "${duration}" "$@"
    return $?
  fi
  "$@"
}

gh_api_retry() {
  local endpoint="$1"
  local attempts="${2:-5}"
  local sleep_sec=2
  local i out
  for ((i=1; i<=attempts; i++)); do
    if out="$(GH_TOKEN="${gh_readonly_token:-${GH_TOKEN:-}}" gh_timeout_cmd 20s gh api "${endpoint}" 2>/dev/null)"; then
      printf '%s\n' "${out}"
      return 0
    fi
    if (( i == attempts )); then
      return 1
    fi
    sleep "${sleep_sec}"
    if (( sleep_sec < 16 )); then
      sleep_sec=$((sleep_sec * 2))
    fi
  done
  return 1
}

gh_var_default() {
  local repo_name="$1"
  local env_value="${2:-}"
  local gh_var_name="$3"
  local fallback="$4"
  local resolved="${env_value}"

  if [[ "${CANARY_PLAN_ONLY:-false}" == "true" ]]; then
    if [[ -n "${resolved}" ]]; then
      printf '%s\n' "${resolved}"
    else
      printf '%s\n' "${fallback}"
    fi
    return 0
  fi
  if [[ -n "${resolved}" ]]; then
    printf '%s\n' "${resolved}"
    return 0
  fi
  if [[ -n "${repo_name}" ]]; then
    resolved="$(GH_TOKEN="${gh_readonly_token:-${GH_TOKEN:-}}" gh_timeout_cmd 20s gh variable get "${gh_var_name}" --repo "${repo_name}" --json value -q '.value' 2>/dev/null || true)"
    if [[ -n "${resolved}" ]]; then
      printf '%s\n' "${resolved}"
      return 0
    fi
  fi
  printf '%s\n' "${fallback}"
}

gh_secret_present_default() {
  local repo_name="$1"
  local env_value="${2:-}"
  local secret_name="$3"

  if [[ "${CANARY_PLAN_ONLY:-false}" == "true" ]]; then
    if [[ -n "${env_value}" ]]; then
      printf '%s\n' "${env_value}"
    else
      printf 'false\n'
    fi
    return 0
  fi
  if [[ -n "${env_value}" ]]; then
    printf '%s\n' "${env_value}"
    return 0
  fi
  if [[ -n "${repo_name}" ]] && GH_TOKEN="${gh_readonly_token:-${GH_TOKEN:-}}" gh_timeout_cmd 20s gh secret list --repo "${repo_name}" 2>/dev/null | awk '{print $1}' | grep -Fxq "${secret_name}"; then
    printf 'true\n'
    return 0
  fi
  printf 'false\n'
}

clamp_num() {
  local value="$1"
  local min="$2"
  local max="$3"
  if (( value < min )); then
    value="${min}"
  elif (( value > max )); then
    value="${max}"
  fi
  echo "${value}"
}

# --- Input normalization ---

repo="${GITHUB_REPOSITORY}"
gh_readonly_token="${GH_TOKEN:-}"
gh_ops_token="${gh_readonly_token:-${OPS_TOKEN:-}}"
ts="$(date -u +%Y%m%d%H%M%S)"
failures=0
online_count=0
self_hosted_online="false"
canary_mode="full"
run_force_case="true"
verify_rollback_case="false"
plan_only="$(normalize_bool "${CANARY_PLAN_ONLY:-false}")"
primary_handoff_target="kernel"
rollback_handoff_target="fugue-bridge"

claude_state="$(lower_trim "$(gh_var_default "${repo}" "${CLAUDE_RATE_LIMIT_STATE:-}" "FUGUE_CLAUDE_RATE_LIMIT_STATE" "ok")")"
canary_mode="$(lower_trim "${CANARY_MODE_INPUT:-full}")"
if [[ "${canary_mode}" != "full" && "${canary_mode}" != "lite" ]]; then
  canary_mode="full"
fi
if [[ "${canary_mode}" == "lite" ]]; then
  run_force_case="false"
fi
verify_rollback_case="$(normalize_bool "${CANARY_VERIFY_ROLLBACK:-$([[ "${canary_mode}" == "full" ]] && echo "true" || echo "false")}")"
primary_handoff_target="$(lower_trim "${CANARY_PRIMARY_HANDOFF_TARGET:-kernel}")"
if [[ "${primary_handoff_target}" != "kernel" && "${primary_handoff_target}" != "fugue-bridge" ]]; then
  primary_handoff_target="kernel"
fi
role_policy="$(lower_trim "$(gh_var_default "${repo}" "${CLAUDE_ROLE_POLICY:-}" "FUGUE_CLAUDE_ROLE_POLICY" "flex")")"
degraded_assist_policy="$(lower_trim "$(gh_var_default "${repo}" "${CLAUDE_DEGRADED_ASSIST_POLICY:-}" "FUGUE_CLAUDE_DEGRADED_ASSIST_POLICY" "claude")")"
main_assist_policy="$(lower_trim "$(gh_var_default "${repo}" "${CLAUDE_MAIN_ASSIST_POLICY:-}" "FUGUE_CLAUDE_MAIN_ASSIST_POLICY" "codex")")"
ci_execution_engine="$(lower_trim "$(gh_var_default "${repo}" "${CI_EXECUTION_ENGINE:-}" "FUGUE_CI_EXECUTION_ENGINE" "subscription")")"
if [[ "${ci_execution_engine}" != "subscription" && "${ci_execution_engine}" != "harness" && "${ci_execution_engine}" != "api" ]]; then
  ci_execution_engine="subscription"
fi
subscription_offline_policy="$(lower_trim "$(gh_var_default "${repo}" "${SUBSCRIPTION_OFFLINE_POLICY:-}" "FUGUE_SUBSCRIPTION_OFFLINE_POLICY" "continuity")")"
if [[ "${subscription_offline_policy}" != "hold" && "${subscription_offline_policy}" != "continuity" ]]; then
  subscription_offline_policy="continuity"
fi
canary_offline_policy_override="$(lower_trim "$(gh_var_default "${repo}" "${CANARY_OFFLINE_POLICY_OVERRIDE:-}" "FUGUE_CANARY_OFFLINE_POLICY_OVERRIDE" "continuity")")"
if [[ "${canary_offline_policy_override}" != "inherit" && "${canary_offline_policy_override}" != "hold" && "${canary_offline_policy_override}" != "continuity" ]]; then
  canary_offline_policy_override="continuity"
fi
canary_execution_mode_override="$(lower_trim "$(gh_var_default "${repo}" "${CANARY_EXECUTION_MODE_OVERRIDE:-}" "FUGUE_CANARY_EXECUTION_MODE_OVERRIDE" "primary")")"
case "${canary_execution_mode_override}" in
  auto|primary|backup-safe|backup-heavy) ;;
  *) canary_execution_mode_override="primary" ;;
esac
emergency_continuity_mode="$(normalize_bool "$(gh_var_default "${repo}" "${EMERGENCY_CONTINUITY_MODE:-}" "FUGUE_EMERGENCY_CONTINUITY_MODE" "false")")"
subscription_runner_label="$(echo "$(gh_var_default "${repo}" "${SUBSCRIPTION_RUNNER_LABEL:-}" "FUGUE_SUBSCRIPTION_RUNNER_LABEL" "fugue-subscription")" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -z "${subscription_runner_label}" ]]; then
  subscription_runner_label="fugue-subscription"
fi
canary_label_wait_attempts="$(echo "${CANARY_LABEL_WAIT_ATTEMPTS:-10}" | tr -cd '0-9')"
if [[ -z "${canary_label_wait_attempts}" || "${canary_label_wait_attempts}" == "0" ]]; then
  canary_label_wait_attempts="10"
fi
canary_label_wait_attempts="$(clamp_num "${canary_label_wait_attempts}" 1 60)"
canary_label_wait_sleep_sec="$(echo "${CANARY_LABEL_WAIT_SLEEP_SEC:-2}" | tr -cd '0-9')"
if [[ -z "${canary_label_wait_sleep_sec}" ]]; then
  canary_label_wait_sleep_sec="2"
fi
canary_label_wait_sleep_sec="$(clamp_num "${canary_label_wait_sleep_sec}" 1 30)"
canary_wait_fast_attempts="$(echo "${CANARY_WAIT_FAST_ATTEMPTS:-12}" | tr -cd '0-9')"
if [[ -z "${canary_wait_fast_attempts}" || "${canary_wait_fast_attempts}" == "0" ]]; then
  canary_wait_fast_attempts="12"
fi
canary_wait_fast_attempts="$(clamp_num "${canary_wait_fast_attempts}" 1 60)"
canary_wait_fast_sleep_sec="$(echo "${CANARY_WAIT_FAST_SLEEP_SEC:-10}" | tr -cd '0-9')"
if [[ -z "${canary_wait_fast_sleep_sec}" ]]; then
  canary_wait_fast_sleep_sec="10"
fi
canary_wait_fast_sleep_sec="$(clamp_num "${canary_wait_fast_sleep_sec}" 1 60)"
canary_wait_slow_attempts="$(echo "${CANARY_WAIT_SLOW_ATTEMPTS:-9}" | tr -cd '0-9')"
if [[ -z "${canary_wait_slow_attempts}" ]]; then
  canary_wait_slow_attempts="9"
fi
canary_wait_slow_attempts="$(clamp_num "${canary_wait_slow_attempts}" 0 60)"
canary_wait_slow_sleep_sec="$(echo "${CANARY_WAIT_SLOW_SLEEP_SEC:-20}" | tr -cd '0-9')"
if [[ -z "${canary_wait_slow_sleep_sec}" ]]; then
  canary_wait_slow_sleep_sec="20"
fi
canary_wait_slow_sleep_sec="$(clamp_num "${canary_wait_slow_sleep_sec}" 1 120)"

default_main_provider="$(lower_trim "$(gh_var_default "${repo}" "${DEFAULT_MAIN_ORCHESTRATOR_PROVIDER:-}" "FUGUE_MAIN_ORCHESTRATOR_PROVIDER" "codex")")"
if [[ "${default_main_provider}" != "codex" && "${default_main_provider}" != "claude" ]]; then
  default_main_provider="codex"
fi
execution_provider_default="$(lower_trim "$(gh_var_default "${repo}" "${EXECUTION_PROVIDER_DEFAULT:-}" "FUGUE_EXECUTION_PROVIDER" "")")"
if [[ "${execution_provider_default}" != "codex" && "${execution_provider_default}" != "claude" ]]; then
  execution_provider_default=""
fi
canary_alternate_main="$(lower_trim "${CANARY_ALTERNATE_PROVIDER:-}")"
if [[ "${canary_alternate_main}" != "codex" && "${canary_alternate_main}" != "claude" ]]; then
  if [[ "${default_main_provider}" == "claude" ]]; then
    canary_alternate_main="codex"
  else
    canary_alternate_main="claude"
  fi
fi
canary_alternate_force="false"
if [[ "${canary_alternate_main}" == "claude" && "${default_main_provider}" != "claude" ]]; then
  canary_alternate_force="true"
fi
legacy_main_provider="$(lower_trim "$(gh_var_default "${repo}" "${LEGACY_MAIN_ORCHESTRATOR_PROVIDER:-}" "FUGUE_LEGACY_MAIN_ORCHESTRATOR_PROVIDER" "claude")")"
if [[ "${legacy_main_provider}" != "codex" && "${legacy_main_provider}" != "claude" ]]; then
  legacy_main_provider="claude"
fi
legacy_assist_provider="$(lower_trim "$(gh_var_default "${repo}" "${LEGACY_ASSIST_ORCHESTRATOR_PROVIDER:-}" "FUGUE_LEGACY_ASSIST_ORCHESTRATOR_PROVIDER" "claude")")"
if [[ "${legacy_assist_provider}" != "claude" && "${legacy_assist_provider}" != "codex" && "${legacy_assist_provider}" != "none" ]]; then
  legacy_assist_provider="claude"
fi
legacy_force_claude="$(normalize_bool "$(gh_var_default "${repo}" "${LEGACY_FORCE_CLAUDE:-}" "FUGUE_LEGACY_FORCE_CLAUDE" "true")")"
HAS_ANTHROPIC_API_KEY="$(gh_secret_present_default "${repo}" "${HAS_ANTHROPIC_API_KEY:-}" "ANTHROPIC_API_KEY")"
HAS_OPENAI_API_KEY="$(gh_secret_present_default "${repo}" "${HAS_OPENAI_API_KEY:-}" "OPENAI_API_KEY")"

# --- Token resolution ---

if [[ "${plan_only}" != "true" ]]; then
  if [[ -z "${gh_ops_token}" ]]; then
    echo "Skip canary: no GitHub token available for same-repo issue and workflow operations."
    exit 0
  fi
fi

# --- Runner availability check ---

if [[ "${plan_only}" == "true" ]]; then
  online_count="$(printf '%s' "${CANARY_PLAN_ONLINE_COUNT:-1}" | tr -cd '0-9')"
  if [[ -z "${online_count}" ]]; then
    online_count="1"
  else
    online_count="$((10#${online_count}))"
  fi
elif [[ "${ci_execution_engine}" == "subscription" ]]; then
  if [[ "${canary_offline_policy_override}" == "continuity" ]]; then
    online_count="0"
    echo "Canary override: continuity verification skips self-hosted runner probe for label ${subscription_runner_label}."
    subscription_offline_policy="continuity"
  else
    runners_json="$(gh_api_retry "repos/${repo}/actions/runners?per_page=100" 5 || echo '{}')"
    online_count="$(echo "${runners_json}" | jq -r --arg label "${subscription_runner_label}" '[.runners[]? | select(.status=="online" and .busy != true and ([.labels[]?.name] | index("self-hosted") != null) and ([.labels[]?.name] | index($label) != null))] | length' 2>/dev/null || echo "0")"
    online_count="$(echo "${online_count}" | tr -cd '0-9')"
    if [[ -z "${online_count}" ]]; then
      online_count="0"
    else
      online_count="$((10#${online_count}))"
    fi
    if [[ "${subscription_offline_policy}" == "hold" ]] && (( online_count == 0 )); then
      if [[ "${canary_offline_policy_override}" == "continuity" ]]; then
        echo "Canary override: no online self-hosted runner for label ${subscription_runner_label}; forcing continuity mode for verification."
        subscription_offline_policy="continuity"
      elif [[ "${canary_offline_policy_override}" == "inherit" || "${canary_offline_policy_override}" == "hold" ]]; then
        echo "Canary skipped: subscription strict hold policy active and no online self-hosted runner for label ${subscription_runner_label}."
        exit 0
      fi
    fi
  fi
fi
if (( online_count > 0 )); then
  self_hosted_online="true"
fi

# --- Policy resolution (regular case) ---

eval "$(
  ./scripts/lib/orchestrator-policy.sh \
    --main "${default_main_provider}" \
    --assist "claude" \
    --default-main "${default_main_provider}" \
    --default-assist "claude" \
    --claude-state "${claude_state}" \
    --force-claude "false" \
    --assist-policy "${main_assist_policy}" \
    --claude-role-policy "${role_policy}" \
    --degraded-assist-policy "${degraded_assist_policy}"
)"
expected_regular_main="${resolved_main}"
expected_regular_assist="${resolved_assist}"
eval "$(
  ./scripts/lib/execution-profile-policy.sh \
    --requested-engine "${ci_execution_engine}" \
    --main-provider "${expected_regular_main}" \
    --assist-provider "${expected_regular_assist}" \
    --force-claude "false" \
    --self-hosted-online "${self_hosted_online}" \
    --claude-state "${claude_state}" \
    --strict-main-requested "true" \
    --strict-opus-requested "true" \
    --claude-direct-available "${HAS_ANTHROPIC_API_KEY}" \
    --codex-api-available "${HAS_OPENAI_API_KEY}" \
    --subscription-offline-policy "${subscription_offline_policy}" \
    --api-strict-mode "${API_STRICT_MODE:-false}" \
    --emergency-continuity-mode "${emergency_continuity_mode}" \
    --emergency-assist-policy "${EMERGENCY_ASSIST_POLICY:-none}"
)"
expected_regular_assist_effective="${assist_provider_effective}"
expected_regular_profile="${execution_profile}"
expected_regular_runner="${run_agents_runner}"
expected_regular_handoff_target="${primary_handoff_target}"
expected_regular_mode_source=""
expected_regular_task_size_tier=""

# --- Policy resolution (alternate/force case) ---

eval "$(
  ./scripts/lib/orchestrator-policy.sh \
    --main "${canary_alternate_main}" \
    --assist "claude" \
    --default-main "${default_main_provider}" \
    --default-assist "claude" \
    --claude-state "${claude_state}" \
    --force-claude "${canary_alternate_force}" \
    --assist-policy "${main_assist_policy}" \
    --claude-role-policy "${role_policy}" \
    --degraded-assist-policy "${degraded_assist_policy}"
)"
expected_force_main="${resolved_main}"
expected_force_assist="${resolved_assist}"
eval "$(
  ./scripts/lib/execution-profile-policy.sh \
    --requested-engine "${ci_execution_engine}" \
    --main-provider "${expected_force_main}" \
    --assist-provider "${expected_force_assist}" \
    --force-claude "true" \
    --self-hosted-online "${self_hosted_online}" \
    --claude-state "${claude_state}" \
    --strict-main-requested "true" \
    --strict-opus-requested "true" \
    --claude-direct-available "${HAS_ANTHROPIC_API_KEY}" \
    --codex-api-available "${HAS_OPENAI_API_KEY}" \
    --subscription-offline-policy "${subscription_offline_policy}" \
    --api-strict-mode "${API_STRICT_MODE:-false}" \
    --emergency-continuity-mode "${emergency_continuity_mode}" \
    --emergency-assist-policy "${EMERGENCY_ASSIST_POLICY:-none}"
)"
expected_force_assist_effective="${assist_provider_effective}"
expected_force_profile="${execution_profile}"
expected_force_runner="${run_agents_runner}"
expected_force_handoff_target="${primary_handoff_target}"
expected_force_mode_source=""
expected_force_task_size_tier=""

# --- Policy resolution (rollback / fugue-bridge case) ---

expected_rollback_main=""
expected_rollback_assist=""
expected_rollback_assist_effective=""
expected_rollback_profile=""
expected_rollback_runner=""
expected_rollback_handoff_target="${rollback_handoff_target}"
expected_rollback_mode_source="legacy-bridge"
expected_rollback_task_size_tier="small"
if [[ "${verify_rollback_case}" == "true" ]]; then
  eval "$(
    ./scripts/lib/orchestrator-policy.sh \
      --main "${legacy_main_provider}" \
      --assist "${legacy_assist_provider}" \
      --default-main "${legacy_main_provider}" \
      --default-assist "${legacy_assist_provider}" \
      --claude-state "${claude_state}" \
      --force-claude "${legacy_force_claude}" \
      --assist-policy "${main_assist_policy}" \
      --claude-role-policy "${role_policy}" \
      --degraded-assist-policy "${degraded_assist_policy}"
  )"
  expected_rollback_main="${resolved_main}"
  expected_rollback_assist="${resolved_assist}"
  eval "$(
    ./scripts/lib/execution-profile-policy.sh \
      --requested-engine "${ci_execution_engine}" \
      --main-provider "${expected_rollback_main}" \
      --assist-provider "${expected_rollback_assist}" \
      --force-claude "${legacy_force_claude}" \
      --self-hosted-online "${self_hosted_online}" \
      --claude-state "${claude_state}" \
      --strict-main-requested "true" \
      --strict-opus-requested "true" \
      --claude-direct-available "${HAS_ANTHROPIC_API_KEY}" \
      --codex-api-available "${HAS_OPENAI_API_KEY}" \
      --subscription-offline-policy "${subscription_offline_policy}" \
      --api-strict-mode "${API_STRICT_MODE:-false}" \
      --emergency-continuity-mode "${emergency_continuity_mode}" \
      --emergency-assist-policy "${EMERGENCY_ASSIST_POLICY:-none}"
  )"
  expected_rollback_assist_effective="${assist_provider_effective}"
  expected_rollback_profile="${execution_profile}"
  expected_rollback_runner="${run_agents_runner}"
fi

if [[ "${primary_handoff_target}" == "fugue-bridge" && "${verify_rollback_case}" == "true" ]]; then
  expected_regular_main="${expected_rollback_main}"
  expected_regular_assist_effective="${expected_rollback_assist_effective}"
  expected_regular_profile="${expected_rollback_profile}"
  expected_regular_runner="${expected_rollback_runner}"
  expected_regular_mode_source="${expected_rollback_mode_source}"
  expected_regular_task_size_tier="${expected_rollback_task_size_tier}"
  expected_force_main="${expected_rollback_main}"
  expected_force_assist_effective="${expected_rollback_assist_effective}"
  expected_force_profile="${expected_rollback_profile}"
  expected_force_runner="${expected_rollback_runner}"
  expected_force_mode_source="${expected_rollback_mode_source}"
  expected_force_task_size_tier="${expected_rollback_task_size_tier}"
fi

print_plan_case() {
  local case_name="$1"
  local requested_main="$2"
  local resolved_main="$3"
  local resolved_assist="$4"
  local resolved_profile="$5"
  local resolved_runner="$6"
  local handoff_target="$7"
  local mode_source="$8"
  local task_size_tier="$9"
  jq -cn \
    --arg case_name "${case_name}" \
    --arg requested_main "${requested_main}" \
    --arg resolved_main "${resolved_main}" \
    --arg resolved_assist "${resolved_assist}" \
    --arg resolved_profile "${resolved_profile}" \
    --arg resolved_runner "${resolved_runner}" \
    --arg handoff_target "${handoff_target}" \
    --arg mode_source "${mode_source}" \
    --arg task_size_tier "${task_size_tier}" \
    '{
      case:$case_name,
      requested_main:$requested_main,
      resolved_main:$resolved_main,
      resolved_assist:$resolved_assist,
      resolved_profile:$resolved_profile,
      resolved_runner:$resolved_runner,
      handoff_target:$handoff_target,
      multi_agent_mode_source:$mode_source,
      task_size_tier:$task_size_tier
    }'
}

if [[ "${plan_only}" == "true" ]]; then
  print_plan_case "regular" "${default_main_provider}" "${expected_regular_main}" "${expected_regular_assist_effective}" "${expected_regular_profile}" "${expected_regular_runner}" "${expected_regular_handoff_target}" "${expected_regular_mode_source}" "${expected_regular_task_size_tier}"
  if [[ "${run_force_case}" == "true" ]]; then
    print_plan_case "alternate" "${canary_alternate_main}" "${expected_force_main}" "${expected_force_assist_effective}" "${expected_force_profile}" "${expected_force_runner}" "${expected_force_handoff_target}" "${expected_force_mode_source}" "${expected_force_task_size_tier}"
  fi
  if [[ "${verify_rollback_case}" == "true" ]]; then
    print_plan_case "rollback" "${legacy_main_provider}" "${expected_rollback_main}" "${expected_rollback_assist_effective}" "${expected_rollback_profile}" "${expected_rollback_runner}" "${expected_rollback_handoff_target}" "${expected_rollback_mode_source}" "${expected_rollback_task_size_tier}"
  fi
  exit 0
fi

# --- Ensure labels exist ---

echo "Canary: reusing existing orchestration labels on ${repo}"

# --- Issue creation ---

create_issue() {
  local title="$1"
  local force_label="$2"
  local orch_provider="${3:-claude}"
  local handoff_target="${4:-kernel}"
  local assist_provider="${5:-claude}"
  local body
  body="$(printf '## Canary\nAutomated orchestration canary.\n\n- orchestrator: %s main\n- assist orchestrator provider: %s\n- handoff target: %s\n- case: %s\n- created_at_utc: %s\n- cleanup: auto-close on pass, keep open on failure\n' \
    "${orch_provider}" \
    "${assist_provider}" \
    "${handoff_target}" \
    "${title}" \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")"

  local cmd=(gh issue create --repo "${repo}" --title "${title}" --body "${body}" \
    --label "fugue-task" \
    --label "orchestrator:${orch_provider}" \
    --label "orchestrator-assist:${assist_provider}")
  if [[ -n "${force_label}" ]]; then
    cmd+=(--label "${force_label}")
  fi
  local url
  echo "Canary: creating issue '${title}'" >&2
  url="$(GH_TOKEN="${gh_ops_token}" gh_timeout_cmd 30s "${cmd[@]}")"
  local issue_num="${url##*/}"
  local dispatch_offline_policy=""
  local caller_ref="${GITHUB_REF_NAME:-main}"
  if [[ "${canary_offline_policy_override}" == "hold" || "${canary_offline_policy_override}" == "continuity" ]]; then
    dispatch_offline_policy="${canary_offline_policy_override}"
  fi
  local run_cmd=(gh workflow run fugue-tutti-caller.yml \
    --repo "${repo}" \
    --ref "${caller_ref}" \
    -f issue_number="${issue_num}" \
    -f handoff_target="${handoff_target}")
  if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
    run_cmd+=(-f canary_dispatch_run_id="${GITHUB_RUN_ID}")
  fi
  if [[ -n "${GITHUB_ACTOR:-}" ]]; then
    run_cmd+=(-f trust_subject="${GITHUB_ACTOR}")
  fi
  if [[ -n "${dispatch_offline_policy}" ]]; then
    run_cmd+=(-f subscription_offline_policy_override="${dispatch_offline_policy}")
  fi
  if [[ -n "${canary_execution_mode_override}" && "${canary_execution_mode_override}" != "auto" ]]; then
    run_cmd+=(-f execution_mode_override="${canary_execution_mode_override}")
  fi
  echo "Canary: dispatching tutti caller for issue #${issue_num} handoff=${handoff_target}" >&2
  GH_TOKEN="${gh_ops_token}" gh_timeout_cmd 30s "${run_cmd[@]}" >/dev/null
  echo "${issue_num}"
}

# --- Wait for integrated review ---

wait_for_resolved_orchestrators() {
  local issue_num="$1"
  local phase="fast"
  local max_attempts="${canary_wait_fast_attempts}"
  local sleep_sec="${canary_wait_fast_sleep_sec}"
  local attempt=1
  local comments_json meta_json comment resolved_main resolved_assist resolved_profile
  local resolved_runner resolved_runner_labels resolved_lanes resolved_handoff_target
  local resolved_mode_source resolved_task_size_tier
  echo "Canary: waiting for integrated review on issue #${issue_num}" >&2
  while true; do
    comments_json="$(gh_api_retry "repos/${repo}/issues/${issue_num}/comments?per_page=100" 4 || echo '[]')"
    meta_json="$(echo "${comments_json}" | jq -r '
      [ .[]?.body
        | select(contains("FUGUE_INTEGRATED_META:"))
        | capture("FUGUE_INTEGRATED_META:(?<json>\\{.*\\})").json
      ] | last // ""
    ' 2>/dev/null || echo "")"
    if [[ -n "${meta_json}" ]] && echo "${meta_json}" | jq -e . >/dev/null 2>&1; then
      resolved_main="$(echo "${meta_json}" | jq -r '.main_orchestrator_resolved // ""' | tr '[:upper:]' '[:lower:]')"
      resolved_assist="$(echo "${meta_json}" | jq -r '.assist_orchestrator_resolved // ""' | tr '[:upper:]' '[:lower:]')"
      resolved_profile="$(echo "${meta_json}" | jq -r '.execution_profile // ""' | tr '[:upper:]' '[:lower:]')"
      resolved_runner="$(echo "${meta_json}" | jq -r '.run_agents_runner // ""' | tr '[:upper:]' '[:lower:]')"
      resolved_runner_labels="$(echo "${meta_json}" | jq -c '.run_agents_runner_labels // []')"
      resolved_lanes="$(echo "${meta_json}" | jq -r '.lanes_configured // ""' | tr -cd '0-9')"
      resolved_handoff_target="$(echo "${meta_json}" | jq -r '.handoff_target // "kernel"' | tr '[:upper:]' '[:lower:]')"
      resolved_mode_source="$(echo "${meta_json}" | jq -r '.multi_agent_mode_source // ""' | tr '[:upper:]' '[:lower:]')"
      resolved_task_size_tier="$(echo "${meta_json}" | jq -r '.task_size_tier // ""' | tr '[:upper:]' '[:lower:]')"
      if [[ -n "${resolved_main}" && -n "${resolved_assist}" && -n "${resolved_profile}" ]]; then
        echo "${resolved_main}|${resolved_assist}|${resolved_profile}|${resolved_runner}|${resolved_runner_labels}|${resolved_lanes}|${resolved_handoff_target}|${resolved_mode_source}|${resolved_task_size_tier}"
        return 0
      fi
    fi
    comment="$(echo "${comments_json}" | jq -r '[.[].body | select(contains("## Tutti Integrated Review"))] | last // ""')"
    if [[ -n "${comment}" ]]; then
      resolved_main="$(printf '%s\n' "${comment}" | sed -n 's/^- main orchestrator resolved: //p' | head -n1 | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
      resolved_assist="$(printf '%s\n' "${comment}" | sed -n 's/^- assist orchestrator resolved: //p' | head -n1 | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
      resolved_profile="$(printf '%s\n' "${comment}" | sed -n 's/^- execution profile: \([^ ]*\).*/\1/p' | head -n1 | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
      resolved_runner="$(printf '%s\n' "${comment}" | sed -n 's/^- run-agents runner: //p' | head -n1 | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
      resolved_runner_labels="$(printf '%s\n' "${comment}" | sed -n 's/^- run-agents runner labels: //p' | head -n1 | tr -d '\r')"
      resolved_lanes="$(printf '%s\n' "${comment}" | sed -n 's/^- lanes configured: //p' | head -n1 | tr -cd '0-9')"
      resolved_handoff_target="$(printf '%s\n' "${comment}" | sed -n 's/^- handoff target: //p' | head -n1 | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
      resolved_mode_source="$(printf '%s\n' "${comment}" | sed -n 's/^- multi-agent mode source: //p' | head -n1 | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
      resolved_task_size_tier="$(printf '%s\n' "${comment}" | sed -n 's/^- task size tier: //p' | head -n1 | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
      if [[ -n "${resolved_main}" && -n "${resolved_assist}" && -n "${resolved_profile}" ]]; then
        echo "${resolved_main}|${resolved_assist}|${resolved_profile}|${resolved_runner}|${resolved_runner_labels}|${resolved_lanes}|${resolved_handoff_target}|${resolved_mode_source}|${resolved_task_size_tier}"
        return 0
      fi
    fi
    if [[ "${attempt}" -ge "${max_attempts}" ]]; then
      if [[ "${phase}" == "fast" && "${canary_wait_slow_attempts}" != "0" ]]; then
        phase="slow"
        max_attempts="${canary_wait_slow_attempts}"
        sleep_sec="${canary_wait_slow_sleep_sec}"
        attempt=1
        continue
      fi
      break
    fi
    sleep "${sleep_sec}"
    attempt="$((attempt + 1))"
  done
  return 1
}

# --- Issue conclusion ---

conclude_issue() {
  local issue_num="$1"
  local expected_main="$2"
  local expected_assist="$3"
  local expected_profile="$4"
  local expected_runner="$5"
  local expected_handoff_target="$6"
  local expected_mode_source="$7"
  local expected_task_size_tier="$8"
  local actual_main="$9"
  local actual_assist="${10}"
  local actual_profile="${11}"
  local actual_runner="${12}"
  local actual_lanes="${13}"
  local actual_handoff_target="${14}"
  local actual_mode_source="${15}"
  local actual_task_size_tier="${16}"
  local pass="${17}"
  local case_name="${18}"
  local reason="${19}"
  local issue_state=""
  local issue_state_after=""
  local label_json=""
  local cleanup_labels=()
  local cleanup_cmd=()
  if [[ "${pass}" == "true" ]]; then
    gh issue comment "${issue_num}" --repo "${repo}" --body "Canary pass (${case_name}): expected main=\`${expected_main}\` assist=\`${expected_assist}\` profile=\`${expected_profile}\` runner=\`${expected_runner}\` handoff=\`${expected_handoff_target:-n/a}\` mode_source=\`${expected_mode_source:-n/a}\` task_size=\`${expected_task_size_tier:-n/a}\`, actual main=\`${actual_main}\` assist=\`${actual_assist}\` profile=\`${actual_profile}\` runner=\`${actual_runner}\` handoff=\`${actual_handoff_target:-n/a}\` mode_source=\`${actual_mode_source:-n/a}\` task_size=\`${actual_task_size_tier:-n/a}\`, lanes=\`${actual_lanes}\`."
    if ! gh issue edit "${issue_num}" --repo "${repo}" --add-label "completed" >/dev/null 2>&1; then
      echo "Warning: failed to add completed label to issue #${issue_num}" >&2
    fi
    label_json="$(gh issue view "${issue_num}" --repo "${repo}" --json labels -q '.labels[].name' 2>/dev/null || true)"
    if [[ -n "${label_json}" ]]; then
      while IFS= read -r label_name; do
        case "${label_name}" in
          needs-human|needs-review|processing)
            cleanup_labels+=("${label_name}")
            ;;
        esac
      done <<< "${label_json}"
    fi
    if [[ "${#cleanup_labels[@]}" -gt 0 ]]; then
      cleanup_cmd=(gh issue edit "${issue_num}" --repo "${repo}")
      local cleanup_label=""
      for cleanup_label in "${cleanup_labels[@]}"; do
        cleanup_cmd+=(--remove-label "${cleanup_label}")
      done
      if ! "${cleanup_cmd[@]}" >/dev/null 2>&1; then
        echo "Warning: failed to remove transient canary labels from issue #${issue_num}" >&2
      fi
    fi
    issue_state="$(gh issue view "${issue_num}" --repo "${repo}" --json state -q '.state' 2>/dev/null || true)"
    if [[ "${issue_state}" == "OPEN" ]]; then
      if ! gh issue close "${issue_num}" --repo "${repo}" --comment "Canary cleanup: closed automatically after successful verification." >/dev/null 2>&1; then
        issue_state_after="$(gh issue view "${issue_num}" --repo "${repo}" --json state -q '.state' 2>/dev/null || true)"
        if [[ "${issue_state_after}" != "CLOSED" ]]; then
          echo "Warning: failed to close issue #${issue_num} during canary cleanup." >&2
        fi
      fi
    fi
  else
    gh issue comment "${issue_num}" --repo "${repo}" --body "Canary fail (${case_name}): expected main=\`${expected_main}\` assist=\`${expected_assist}\` profile=\`${expected_profile}\` runner=\`${expected_runner}\` handoff=\`${expected_handoff_target:-n/a}\` mode_source=\`${expected_mode_source:-n/a}\` task_size=\`${expected_task_size_tier:-n/a}\`, actual main=\`${actual_main:-timeout}\` assist=\`${actual_assist:-timeout}\` profile=\`${actual_profile:-timeout}\` runner=\`${actual_runner:-timeout}\` handoff=\`${actual_handoff_target:-timeout}\` mode_source=\`${actual_mode_source:-timeout}\` task_size=\`${actual_task_size_tier:-timeout}\`, lanes=\`${actual_lanes:-timeout}\`, reason=\`${reason}\`. Investigate router/caller policy."
    if ! gh issue edit "${issue_num}" --repo "${repo}" --add-label "needs-human" >/dev/null 2>&1; then
      echo "Warning: failed to add needs-human label to issue #${issue_num}" >&2
    fi
  fi
}

# --- Run canary cases ---

strict_expected="false"
if [[ "${ci_execution_engine}" == "subscription" && "${online_count}" -gt 0 ]]; then
  strict_expected="true"
fi

issue_prefix="[canary]"
if [[ "${canary_mode}" == "lite" ]]; then
  issue_prefix="[canary-lite]"
fi
regular_issue="$(create_issue "${issue_prefix} regular ${default_main_provider}-main request ${ts}" "" "${default_main_provider}" "${primary_handoff_target}" "claude")"
force_issue=""
rollback_issue=""
if [[ "${run_force_case}" == "true" ]]; then
  if [[ "${canary_alternate_force}" == "true" ]]; then
    force_issue="$(create_issue "${issue_prefix} alternate ${canary_alternate_main}-main request ${ts}" "orchestrator-force:claude" "${canary_alternate_main}" "${primary_handoff_target}" "claude")"
  else
    force_issue="$(create_issue "${issue_prefix} alternate ${canary_alternate_main}-main request ${ts}" "" "${canary_alternate_main}" "${primary_handoff_target}" "claude")"
  fi
fi
if [[ "${verify_rollback_case}" == "true" ]]; then
  rollback_force_label=""
  if [[ "${legacy_force_claude}" == "true" ]]; then
    rollback_force_label="orchestrator-force:claude"
  fi
  rollback_issue="$(create_issue "${issue_prefix} rollback legacy ${legacy_main_provider}-main request ${ts}" "${rollback_force_label}" "${legacy_main_provider}" "${rollback_handoff_target}" "${legacy_assist_provider}")"
fi

regular_pair_file="$(mktemp)"
force_pair_file="$(mktemp)"
rollback_pair_file="$(mktemp)"
cleanup_wait_files() {
  rm -f "${regular_pair_file}" "${force_pair_file}" "${rollback_pair_file}"
}
trap cleanup_wait_files EXIT

wait_for_resolved_orchestrators "${regular_issue}" >"${regular_pair_file}" &
regular_wait_pid="$!"
force_wait_pid=""
if [[ "${run_force_case}" == "true" ]]; then
  wait_for_resolved_orchestrators "${force_issue}" >"${force_pair_file}" &
  force_wait_pid="$!"
fi
rollback_wait_pid=""
if [[ "${verify_rollback_case}" == "true" ]]; then
  wait_for_resolved_orchestrators "${rollback_issue}" >"${rollback_pair_file}" &
  rollback_wait_pid="$!"
fi

regular_pair=""
regular_wait_ok="false"
if wait "${regular_wait_pid}"; then
  regular_pair="$(tail -n1 "${regular_pair_file}" | tr -d '\r')"
  regular_wait_ok="true"
  echo "Canary: regular issue #${regular_issue} resolved -> ${regular_pair}"
fi

force_pair=""
force_wait_ok="false"
if [[ "${run_force_case}" != "true" ]]; then
  force_wait_ok="false"
elif wait "${force_wait_pid}"; then
  force_pair="$(tail -n1 "${force_pair_file}" | tr -d '\r')"
  force_wait_ok="true"
  echo "Canary: alternate issue #${force_issue} resolved -> ${force_pair}"
fi

rollback_pair=""
rollback_wait_ok="false"
if [[ "${verify_rollback_case}" != "true" ]]; then
  rollback_wait_ok="false"
elif wait "${rollback_wait_pid}"; then
  rollback_pair="$(tail -n1 "${rollback_pair_file}" | tr -d '\r')"
  rollback_wait_ok="true"
  echo "Canary: rollback issue #${rollback_issue} resolved -> ${rollback_pair}"
fi

# --- Verify regular case ---

if [[ "${regular_wait_ok}" == "true" && -n "${regular_pair}" ]]; then
  regular_main="${regular_pair%%|*}"
  regular_rest="${regular_pair#*|}"
  regular_assist="${regular_rest%%|*}"
  regular_rest="${regular_rest#*|}"
  regular_profile="${regular_rest%%|*}"
  regular_rest="${regular_rest#*|}"
  regular_runner="${regular_rest%%|*}"
  regular_rest="${regular_rest#*|}"
  regular_runner_labels="${regular_rest%%|*}"
  regular_rest="${regular_rest#*|}"
  regular_lanes="${regular_rest%%|*}"
  regular_rest="${regular_rest#*|}"
  regular_handoff_target="${regular_rest%%|*}"
  regular_rest="${regular_rest#*|}"
  regular_mode_source="${regular_rest%%|*}"
  regular_task_size_tier="${regular_rest#*|}"
  regular_ok="true"
  regular_reason="ok"
  if [[ "${regular_main}" != "${expected_regular_main}" || "${regular_assist}" != "${expected_regular_assist_effective}" ]]; then
    regular_ok="false"
    regular_reason="resolved-provider-mismatch"
  elif [[ "${regular_profile}" != "${expected_regular_profile}" ]]; then
    regular_ok="false"
    regular_reason="execution-profile-mismatch"
  elif [[ "${regular_runner}" != "${expected_regular_runner}" ]]; then
    regular_ok="false"
    regular_reason="runner-mismatch"
  elif [[ "${expected_regular_runner}" == "self-hosted" && "${regular_runner_labels}" != *"\"${subscription_runner_label}\""* ]]; then
    regular_ok="false"
    regular_reason="required-runner-label-missing"
  elif [[ "${regular_handoff_target}" != "${expected_regular_handoff_target}" ]]; then
    regular_ok="false"
    regular_reason="handoff-target-mismatch"
  elif [[ -z "${regular_lanes}" || "${regular_lanes}" == "0" ]]; then
    regular_ok="false"
    regular_reason="lanes-not-materialized"
  fi
  if [[ "${regular_ok}" == "true" ]]; then
    conclude_issue "${regular_issue}" "${expected_regular_main}" "${expected_regular_assist_effective}" "${expected_regular_profile}" "${expected_regular_runner}" "${expected_regular_handoff_target}" "${expected_regular_mode_source}" "${expected_regular_task_size_tier}" "${regular_main}" "${regular_assist}" "${regular_profile}" "${regular_runner}" "${regular_lanes}" "${regular_handoff_target}" "${regular_mode_source}" "${regular_task_size_tier}" "true" "regular" "ok"
  else
    conclude_issue "${regular_issue}" "${expected_regular_main}" "${expected_regular_assist_effective}" "${expected_regular_profile}" "${expected_regular_runner}" "${expected_regular_handoff_target}" "${expected_regular_mode_source}" "${expected_regular_task_size_tier}" "${regular_main}" "${regular_assist}" "${regular_profile}" "${regular_runner}" "${regular_lanes}" "${regular_handoff_target}" "${regular_mode_source}" "${regular_task_size_tier}" "false" "regular" "${regular_reason}"
    failures="$((failures + 1))"
  fi
else
  conclude_issue "${regular_issue}" "${expected_regular_main}" "${expected_regular_assist_effective}" "${expected_regular_profile}" "${expected_regular_runner}" "${expected_regular_handoff_target}" "${expected_regular_mode_source}" "${expected_regular_task_size_tier}" "" "" "" "" "" "" "" "" "false" "regular" "timeout-no-integrated-review"
  failures="$((failures + 1))"
fi

# --- Verify alternate/force case ---

if [[ "${run_force_case}" != "true" ]]; then
  echo "Canary lite mode: skipped forced-claude case."
elif [[ "${force_wait_ok}" == "true" && -n "${force_pair}" ]]; then
  force_main="${force_pair%%|*}"
  force_rest="${force_pair#*|}"
  force_assist="${force_rest%%|*}"
  force_rest="${force_rest#*|}"
  force_profile="${force_rest%%|*}"
  force_rest="${force_rest#*|}"
  force_runner="${force_rest%%|*}"
  force_rest="${force_rest#*|}"
  force_runner_labels="${force_rest%%|*}"
  force_rest="${force_rest#*|}"
  force_lanes="${force_rest%%|*}"
  force_rest="${force_rest#*|}"
  force_handoff_target="${force_rest%%|*}"
  force_rest="${force_rest#*|}"
  force_mode_source="${force_rest%%|*}"
  force_task_size_tier="${force_rest#*|}"
  force_ok="true"
  force_reason="ok"
  if [[ "${force_main}" != "${expected_force_main}" || "${force_assist}" != "${expected_force_assist_effective}" ]]; then
    force_ok="false"
    force_reason="resolved-provider-mismatch"
  elif [[ "${force_profile}" != "${expected_force_profile}" ]]; then
    force_ok="false"
    force_reason="execution-profile-mismatch"
  elif [[ "${force_runner}" != "${expected_force_runner}" ]]; then
    force_ok="false"
    force_reason="runner-mismatch"
  elif [[ "${expected_force_runner}" == "self-hosted" && "${force_runner_labels}" != *"\"${subscription_runner_label}\""* ]]; then
    force_ok="false"
    force_reason="required-runner-label-missing"
  elif [[ "${force_handoff_target}" != "${expected_force_handoff_target}" ]]; then
    force_ok="false"
    force_reason="handoff-target-mismatch"
  elif [[ -z "${force_lanes}" || "${force_lanes}" == "0" ]]; then
    force_ok="false"
    force_reason="lanes-not-materialized"
  fi
  if [[ "${force_ok}" == "true" ]]; then
    conclude_issue "${force_issue}" "${expected_force_main}" "${expected_force_assist_effective}" "${expected_force_profile}" "${expected_force_runner}" "${expected_force_handoff_target}" "${expected_force_mode_source}" "${expected_force_task_size_tier}" "${force_main}" "${force_assist}" "${force_profile}" "${force_runner}" "${force_lanes}" "${force_handoff_target}" "${force_mode_source}" "${force_task_size_tier}" "true" "force" "ok"
  else
    conclude_issue "${force_issue}" "${expected_force_main}" "${expected_force_assist_effective}" "${expected_force_profile}" "${expected_force_runner}" "${expected_force_handoff_target}" "${expected_force_mode_source}" "${expected_force_task_size_tier}" "${force_main}" "${force_assist}" "${force_profile}" "${force_runner}" "${force_lanes}" "${force_handoff_target}" "${force_mode_source}" "${force_task_size_tier}" "false" "force" "${force_reason}"
    failures="$((failures + 1))"
  fi
else
  conclude_issue "${force_issue}" "${expected_force_main}" "${expected_force_assist_effective}" "${expected_force_profile}" "${expected_force_runner}" "${expected_force_handoff_target}" "${expected_force_mode_source}" "${expected_force_task_size_tier}" "" "" "" "" "" "" "" "" "false" "force" "timeout-no-integrated-review"
  failures="$((failures + 1))"
fi

# --- Verify rollback / fugue-bridge case ---

if [[ "${verify_rollback_case}" != "true" ]]; then
  echo "Canary rollback verification: skipped."
elif [[ "${rollback_wait_ok}" == "true" && -n "${rollback_pair}" ]]; then
  rollback_main="${rollback_pair%%|*}"
  rollback_rest="${rollback_pair#*|}"
  rollback_assist="${rollback_rest%%|*}"
  rollback_rest="${rollback_rest#*|}"
  rollback_profile="${rollback_rest%%|*}"
  rollback_rest="${rollback_rest#*|}"
  rollback_runner="${rollback_rest%%|*}"
  rollback_rest="${rollback_rest#*|}"
  rollback_runner_labels="${rollback_rest%%|*}"
  rollback_rest="${rollback_rest#*|}"
  rollback_lanes="${rollback_rest%%|*}"
  rollback_rest="${rollback_rest#*|}"
  rollback_handoff_target_actual="${rollback_rest%%|*}"
  rollback_rest="${rollback_rest#*|}"
  rollback_mode_source_actual="${rollback_rest%%|*}"
  rollback_task_size_tier_actual="${rollback_rest#*|}"
  rollback_ok="true"
  rollback_reason="ok"
  if [[ "${rollback_main}" != "${expected_rollback_main}" || "${rollback_assist}" != "${expected_rollback_assist_effective}" ]]; then
    rollback_ok="false"
    rollback_reason="resolved-provider-mismatch"
  elif [[ "${rollback_profile}" != "${expected_rollback_profile}" ]]; then
    rollback_ok="false"
    rollback_reason="execution-profile-mismatch"
  elif [[ "${rollback_runner}" != "${expected_rollback_runner}" ]]; then
    rollback_ok="false"
    rollback_reason="runner-mismatch"
  elif [[ "${expected_rollback_runner}" == "self-hosted" && "${rollback_runner_labels}" != *"\"${subscription_runner_label}\""* ]]; then
    rollback_ok="false"
    rollback_reason="required-runner-label-missing"
  elif [[ "${rollback_handoff_target_actual}" != "${expected_rollback_handoff_target}" ]]; then
    rollback_ok="false"
    rollback_reason="handoff-target-mismatch"
  elif [[ "${rollback_mode_source_actual}" != "${expected_rollback_mode_source}" ]]; then
    rollback_ok="false"
    rollback_reason="mode-source-mismatch"
  elif [[ "${rollback_task_size_tier_actual}" != "${expected_rollback_task_size_tier}" ]]; then
    rollback_ok="false"
    rollback_reason="task-size-tier-mismatch"
  elif [[ -z "${rollback_lanes}" || "${rollback_lanes}" == "0" ]]; then
    rollback_ok="false"
    rollback_reason="lanes-not-materialized"
  fi
  if [[ "${rollback_ok}" == "true" ]]; then
    conclude_issue "${rollback_issue}" "${expected_rollback_main}" "${expected_rollback_assist_effective}" "${expected_rollback_profile}" "${expected_rollback_runner}" "${expected_rollback_handoff_target}" "${expected_rollback_mode_source}" "${expected_rollback_task_size_tier}" "${rollback_main}" "${rollback_assist}" "${rollback_profile}" "${rollback_runner}" "${rollback_lanes}" "${rollback_handoff_target_actual}" "${rollback_mode_source_actual}" "${rollback_task_size_tier_actual}" "true" "rollback" "ok"
  else
    conclude_issue "${rollback_issue}" "${expected_rollback_main}" "${expected_rollback_assist_effective}" "${expected_rollback_profile}" "${expected_rollback_runner}" "${expected_rollback_handoff_target}" "${expected_rollback_mode_source}" "${expected_rollback_task_size_tier}" "${rollback_main}" "${rollback_assist}" "${rollback_profile}" "${rollback_runner}" "${rollback_lanes}" "${rollback_handoff_target_actual}" "${rollback_mode_source_actual}" "${rollback_task_size_tier_actual}" "false" "rollback" "${rollback_reason}"
    failures="$((failures + 1))"
  fi
else
  conclude_issue "${rollback_issue}" "${expected_rollback_main}" "${expected_rollback_assist_effective}" "${expected_rollback_profile}" "${expected_rollback_runner}" "${expected_rollback_handoff_target}" "${expected_rollback_mode_source}" "${expected_rollback_task_size_tier}" "" "" "" "" "" "" "" "" "false" "rollback" "timeout-no-integrated-review"
  failures="$((failures + 1))"
fi

# --- Final result ---

if [[ "${failures}" -gt 0 ]]; then
  echo "Canary failed: ${failures} case(s)"
  exit 1
fi

rollback_summary="rollback=skipped"
if [[ "${verify_rollback_case}" == "true" ]]; then
  rollback_summary="rollback(main=${expected_rollback_main},assist_effective=${expected_rollback_assist_effective},profile=${expected_rollback_profile},runner=${expected_rollback_runner},handoff=${expected_rollback_handoff_target},mode_source=${expected_rollback_mode_source},task_size=${expected_rollback_task_size_tier})"
fi

if [[ "${run_force_case}" == "true" ]]; then
  echo "Canary passed (${canary_mode}): regular(main=${expected_regular_main},assist_effective=${expected_regular_assist_effective},profile=${expected_regular_profile},runner=${expected_regular_runner},handoff=${expected_regular_handoff_target}), alternate(main=${expected_force_main},assist_effective=${expected_force_assist_effective},profile=${expected_force_profile},runner=${expected_force_runner},handoff=${expected_force_handoff_target}), ${rollback_summary}, default_main=${default_main_provider}, alternate_main=${canary_alternate_main}, strict_expected=${strict_expected}"
else
  echo "Canary passed (${canary_mode}): regular(main=${expected_regular_main},assist_effective=${expected_regular_assist_effective},profile=${expected_regular_profile},runner=${expected_regular_runner},handoff=${expected_regular_handoff_target}), alternate=skipped, ${rollback_summary}, default_main=${default_main_provider}, strict_expected=${strict_expected}"
fi
