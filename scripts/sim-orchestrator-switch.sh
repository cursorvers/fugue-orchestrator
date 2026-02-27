#!/usr/bin/env bash
set -euo pipefail

# Deterministic orchestration simulation.
# This does not call external APIs or mutate GitHub.

refinement_cycles="${FUGUE_IMPLEMENT_REFINEMENT_CYCLES:-3}"
refinement_cycles="$(echo "${refinement_cycles}" | tr -cd '0-9')"
if [[ -z "${refinement_cycles}" ]]; then
  refinement_cycles="3"
fi
dialogue_rounds_default="${FUGUE_IMPLEMENT_DIALOGUE_ROUNDS:-2}"
dialogue_rounds_default="$(echo "${dialogue_rounds_default}" | tr -cd '0-9')"
if [[ -z "${dialogue_rounds_default}" ]]; then
  dialogue_rounds_default="2"
fi
dialogue_rounds_claude="${FUGUE_IMPLEMENT_DIALOGUE_ROUNDS_CLAUDE:-1}"
dialogue_rounds_claude="$(echo "${dialogue_rounds_claude}" | tr -cd '0-9')"
if [[ -z "${dialogue_rounds_claude}" ]]; then
  dialogue_rounds_claude="1"
fi
claude_main_assist_policy="$(echo "${FUGUE_CLAUDE_MAIN_ASSIST_POLICY:-codex}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_main_assist_policy}" != "codex" && "${claude_main_assist_policy}" != "none" ]]; then
  claude_main_assist_policy="codex"
fi
claude_role_policy="$(echo "${FUGUE_CLAUDE_ROLE_POLICY:-flex}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_role_policy}" != "sub-only" && "${claude_role_policy}" != "flex" ]]; then
  claude_role_policy="flex"
fi
claude_degraded_assist_policy="$(echo "${FUGUE_CLAUDE_DEGRADED_ASSIST_POLICY:-claude}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_degraded_assist_policy}" != "codex" && "${claude_degraded_assist_policy}" != "none" && "${claude_degraded_assist_policy}" != "claude" ]]; then
  claude_degraded_assist_policy="claude"
fi
requested_engine_default="$(echo "${FUGUE_CI_EXECUTION_ENGINE:-subscription}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${requested_engine_default}" != "subscription" && "${requested_engine_default}" != "harness" && "${requested_engine_default}" != "api" ]]; then
  requested_engine_default="subscription"
fi
multi_agent_mode_default="$(echo "${FUGUE_MULTI_AGENT_MODE:-enhanced}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${multi_agent_mode_default}" != "standard" && "${multi_agent_mode_default}" != "enhanced" && "${multi_agent_mode_default}" != "max" ]]; then
  multi_agent_mode_default="enhanced"
fi
glm_subagent_mode_default="$(echo "${FUGUE_GLM_SUBAGENT_MODE:-paired}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${glm_subagent_mode_default}" != "off" && "${glm_subagent_mode_default}" != "paired" && "${glm_subagent_mode_default}" != "symphony" ]]; then
  glm_subagent_mode_default="paired"
fi
codex_main_model_default="$(echo "${FUGUE_CODEX_MAIN_MODEL:-gpt-5-codex}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
codex_multi_agent_model_default="$(echo "${FUGUE_CODEX_MULTI_AGENT_MODEL:-gpt-5.3-codex-spark}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
claude_opus_model_default="$(echo "${FUGUE_CLAUDE_OPUS_MODEL:-claude-sonnet-4-6}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
sim_codex_spark_only="$(echo "${FUGUE_SIM_CODEX_SPARK_ONLY:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${sim_codex_spark_only}" != "false" ]]; then
  sim_codex_spark_only="true"
fi
sim_codex_spark_model="$(echo "${FUGUE_SIM_CODEX_SPARK_MODEL:-gpt-5.3-codex-spark}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if ! [[ "${sim_codex_spark_model}" =~ ^gpt-5(\.[0-9]+)?-codex-spark$ ]]; then
  sim_codex_spark_model="gpt-5.3-codex-spark"
fi
model_policy_script="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)/model-policy.sh"
if [[ -x "${model_policy_script}" ]]; then
  eval "$("${model_policy_script}" \
    --codex-main-model "${codex_main_model_default}" \
    --codex-multi-agent-model "${codex_multi_agent_model_default}" \
    --claude-model "${claude_opus_model_default}" \
    --glm-model "glm-5.0" \
    --gemini-model "gemini-3.1-pro" \
    --gemini-fallback-model "gemini-3-flash" \
    --xai-model "grok-4" \
    --format env)"
  codex_main_model_default="${codex_main_model}"
  codex_multi_agent_model_default="${codex_multi_agent_model}"
  claude_opus_model_default="${claude_model}"
fi
# Simulation common rule: keep simulation iterations fast by using codex-spark only
# unless explicitly disabled.
if [[ "${sim_codex_spark_only}" == "true" ]]; then
  codex_main_model_default="${sim_codex_spark_model}"
  codex_multi_agent_model_default="${sim_codex_spark_model}"
fi
claude_sonnet4_model_default="${claude_opus_model_default}"
claude_sonnet6_model_default="${claude_opus_model_default}"
sim_claude_direct_available="$(echo "${FUGUE_SIM_CLAUDE_DIRECT_AVAILABLE:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${sim_claude_direct_available}" != "true" ]]; then
  sim_claude_direct_available="false"
fi
sim_codex_api_available="$(echo "${FUGUE_SIM_CODEX_API_AVAILABLE:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${sim_codex_api_available}" != "true" ]]; then
  sim_codex_api_available="false"
fi
strict_main_requested="$(echo "${FUGUE_STRICT_MAIN_CODEX_MODEL:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${strict_main_requested}" != "true" ]]; then
  strict_main_requested="false"
fi
strict_opus_requested="$(echo "${FUGUE_STRICT_OPUS_ASSIST_DIRECT:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${strict_opus_requested}" != "true" ]]; then
  strict_opus_requested="false"
fi
api_strict_mode="$(echo "${FUGUE_API_STRICT_MODE:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${api_strict_mode}" != "true" ]]; then
  api_strict_mode="false"
fi
emergency_assist_policy="$(echo "${FUGUE_EMERGENCY_ASSIST_POLICY:-none}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${emergency_assist_policy}" != "none" && "${emergency_assist_policy}" != "codex" && "${emergency_assist_policy}" != "claude" ]]; then
  emergency_assist_policy="none"
fi
subscription_offline_policy_default="$(echo "${FUGUE_SUBSCRIPTION_OFFLINE_POLICY:-hold}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${subscription_offline_policy_default}" != "hold" && "${subscription_offline_policy_default}" != "continuity" ]]; then
  subscription_offline_policy_default="hold"
fi

printf "scenario\trequested_main\trequested_assist\tclaude_state\tforce_claude\trequested_engine\tself_hosted_online\temergency_mode\tsubscription_offline_policy\tresolved_main\tresolved_assist\teffective_assist\texecution_profile\teffective_engine\trunner\tcontinuity\tstrict_main\tstrict_opus\tmain_signal_lane\texpected_lanes\tweighted_vote\timpl_gate\trefinement_cycles\timplementation_dialogue_rounds\tpreflight_gate\tnote\n"

run_case() {
  local scenario="$1"
  local requested_main="$2"
  local requested_assist="$3"
  local claude_state="$4"
  local force_claude="$5"
  local mode="$6"
  local weighted_vote="$7"
  local high_risk="$8"
  local requested_engine="${9:-${requested_engine_default}}"
  local self_hosted_online="${10:-false}"
  local emergency_mode="${11:-false}"
  local subscription_offline_policy="${12:-${subscription_offline_policy_default}}"

  eval "$(
    scripts/lib/orchestrator-policy.sh \
      --main "${requested_main}" \
      --assist "${requested_assist}" \
      --default-main "codex" \
      --default-assist "claude" \
      --claude-state "${claude_state}" \
      --force-claude "${force_claude}" \
      --assist-policy "${claude_main_assist_policy}" \
      --claude-role-policy "${claude_role_policy}" \
      --degraded-assist-policy "${claude_degraded_assist_policy}"
  )"
  local resolved_main="${resolved_main}"
  local resolved_assist="${resolved_assist}"
  local note_parts=()
  if [[ "${main_fallback_applied}" == "true" && -n "${main_fallback_reason}" ]]; then
    note_parts+=("main:${main_fallback_reason}")
  fi
  if [[ "${assist_fallback_applied}" == "true" && -n "${assist_fallback_reason}" ]]; then
    note_parts+=("assist:${assist_fallback_reason}")
  fi
  if [[ "${pressure_guard_applied}" == "true" && -n "${pressure_guard_reason}" ]]; then
    note_parts+=("pressure:${pressure_guard_reason}")
  fi

  eval "$(
    scripts/lib/execution-profile-policy.sh \
      --requested-engine "${requested_engine}" \
      --main-provider "${resolved_main}" \
      --assist-provider "${resolved_assist}" \
      --force-claude "${force_claude}" \
      --self-hosted-online "${self_hosted_online}" \
      --strict-main-requested "${strict_main_requested}" \
      --strict-opus-requested "${strict_opus_requested}" \
      --claude-direct-available "${sim_claude_direct_available}" \
      --codex-api-available "${sim_codex_api_available}" \
      --subscription-offline-policy "${subscription_offline_policy}" \
      --api-strict-mode "${api_strict_mode}" \
      --emergency-continuity-mode "${emergency_mode}" \
      --emergency-assist-policy "${emergency_assist_policy}"
  )"
  local effective_assist="${assist_provider_effective}"
  if [[ "${assist_adjusted_by_profile}" == "true" && -n "${assist_adjustment_reason}" ]]; then
    note_parts+=("profile:${assist_adjustment_reason}")
  fi

  local effective_glm_subagent_mode="${glm_subagent_mode_default}"
  if [[ "${effective_engine}" == "subscription" ]]; then
    effective_glm_subagent_mode="off"
  elif [[ "${multi_agent_mode_default}" == "max" && "${effective_glm_subagent_mode}" == "paired" ]]; then
    effective_glm_subagent_mode="symphony"
  fi

  local matrix_payload
  matrix_payload="$(scripts/lib/build-agent-matrix.sh \
    --engine "${effective_engine}" \
    --main-provider "${resolved_main}" \
    --assist-provider "${effective_assist}" \
    --multi-agent-mode "${multi_agent_mode_default}" \
    --glm-subagent-mode "${effective_glm_subagent_mode}" \
    --wants-gemini "false" \
    --wants-xai "false" \
    --allow-glm-in-subscription "false" \
    --codex-main-model "${codex_main_model_default}" \
    --codex-multi-agent-model "${codex_multi_agent_model_default}" \
    --claude-opus-model "${claude_opus_model_default}" \
    --claude-sonnet4-model "${claude_sonnet4_model_default}" \
    --claude-sonnet6-model "${claude_sonnet6_model_default}" \
    --format "json")"
  local expected_lanes
  expected_lanes="$(echo "${matrix_payload}" | jq -r '.lanes')"
  local main_signal_lane
  main_signal_lane="$(echo "${matrix_payload}" | jq -r '.main_signal_lane')"

  local impl_gate="no-implement"
  if [[ "${mode}" == "implement" && "${weighted_vote}" == "pass" && "${high_risk}" == "false" ]]; then
    impl_gate="codex-implement"
  fi
  local preflight_gate="n/a"
  local implementation_dialogue_rounds="${dialogue_rounds_default}"
  if [[ "${resolved_main}" == "claude" ]]; then
    implementation_dialogue_rounds="${dialogue_rounds_claude}"
  fi
  if [[ "${impl_gate}" == "codex-implement" ]]; then
    preflight_gate="required(${refinement_cycles}x)"
  fi
  note_parts+=("exec:${execution_profile_reason}")
  local note="none"
  if [[ "${#note_parts[@]}" -gt 0 ]]; then
    note="$(IFS=';'; echo "${note_parts[*]}")"
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "${scenario}" \
    "${requested_main}" \
    "${requested_assist}" \
    "${claude_state}" \
    "${force_claude}" \
    "${requested_engine}" \
    "${self_hosted_online}" \
    "${emergency_mode}" \
    "${subscription_offline_policy}" \
    "${resolved_main}" \
    "${resolved_assist}" \
    "${effective_assist}" \
    "${execution_profile}" \
    "${effective_engine}" \
    "${run_agents_runner}" \
    "${continuity_active}" \
    "${strict_main_effective}" \
    "${strict_opus_effective}" \
    "${main_signal_lane}" \
    "${expected_lanes}" \
    "${weighted_vote}" \
    "${impl_gate}" \
    "${refinement_cycles}" \
    "${implementation_dialogue_rounds}" \
    "${preflight_gate}" \
    "${note}"
}

run_case "S1"  "codex"  "claude" "ok"        "false" "review"    "pass"   "false" "subscription" "true"  "false" "hold"
run_case "S2"  "claude" "claude" "ok"        "false" "implement" "pass"   "false" "subscription" "true"  "false" "hold"
run_case "S3"  "claude" "claude" "degraded"  "false" "review"    "pass"   "false" "subscription" "true"  "false" "hold"
run_case "S4"  "codex"  "claude" "ok"        "false" "implement" "pass"   "false" "subscription" "false" "false" "hold"
run_case "S5"  "codex"  "claude" "ok"        "false" "implement" "pass"   "false" "subscription" "false" "false" "continuity"
run_case "S6"  "codex"  "claude" "ok"        "false" "implement" "pass"   "false" "harness"      "false" "false" "hold"
run_case "S7"  "codex"  "claude" "ok"        "false" "implement" "pass"   "false" "harness"      "false" "true"  "hold"
run_case "S8"  "codex"  "codex"  "ok"        "false" "implement" "reject" "false" "api"          "false" "false" "hold"
run_case "S9"  "claude" "none"   "ok"        "false" "implement" "pass"   "true"  "subscription" "true"  "false" "hold"
run_case "S10" "claude" "claude" "exhausted" "true"  "review"    "pass"   "false" "subscription" "false" "false" "hold"
