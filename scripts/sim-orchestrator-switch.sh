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
claude_role_policy="$(echo "${FUGUE_CLAUDE_ROLE_POLICY:-sub-only}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_role_policy}" != "sub-only" && "${claude_role_policy}" != "flex" ]]; then
  claude_role_policy="sub-only"
fi
claude_degraded_assist_policy="$(echo "${FUGUE_CLAUDE_DEGRADED_ASSIST_POLICY:-none}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_degraded_assist_policy}" != "codex" && "${claude_degraded_assist_policy}" != "none" ]]; then
  claude_degraded_assist_policy="none"
fi

printf "scenario\trequested_main\trequested_assist\tclaude_state\tforce_claude\tresolved_main\tresolved_assist\tmain_signal_lane\texpected_lanes\tweighted_vote\timpl_gate\trefinement_cycles\timplementation_dialogue_rounds\tpreflight_gate\tnote\n"

run_case() {
  local scenario="$1"
  local requested_main="$2"
  local requested_assist="$3"
  local claude_state="$4"
  local force_claude="$5"
  local mode="$6"
  local weighted_vote="$7"
  local high_risk="$8"

  local resolved_main="${requested_main}"
  if [[ "${resolved_main}" == "claude" && "${claude_role_policy}" == "sub-only" && "${force_claude}" != "true" ]]; then
    resolved_main="codex"
  fi
  if [[ "${resolved_main}" == "claude" && "${claude_state}" != "ok" && "${force_claude}" != "true" ]]; then
    resolved_main="codex"
  fi

  local resolved_assist="${requested_assist}"
  if [[ "${resolved_assist}" == "claude" && "${claude_state}" == "degraded" && "${force_claude}" != "true" ]]; then
    resolved_assist="${claude_degraded_assist_policy}"
  fi
  if [[ "${resolved_assist}" == "claude" && "${claude_state}" == "exhausted" && "${force_claude}" != "true" ]]; then
    resolved_assist="none"
  fi
  if [[ "${resolved_main}" == "claude" && "${resolved_assist}" == "claude" && "${force_claude}" != "true" ]]; then
    resolved_assist="${claude_main_assist_policy}"
  fi
  local main_signal_lane
  if [[ "${resolved_main}" == "claude" ]]; then
    main_signal_lane="claude-main-orchestrator"
  else
    main_signal_lane="codex-main-orchestrator"
  fi
  local assist_lane_count=0
  if [[ "${resolved_assist}" == "claude" ]]; then
    assist_lane_count=3
  elif [[ "${resolved_assist}" == "codex" ]]; then
    assist_lane_count=1
  fi
  local expected_lanes=$((6 + 1 + assist_lane_count))

  local impl_gate="no-implement"
  local note=""

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

  if [[ "${requested_main}" == "claude" && "${resolved_main}" == "codex" ]]; then
    if [[ "${claude_role_policy}" == "sub-only" && "${claude_state}" == "ok" && "${force_claude}" != "true" ]]; then
      note="main-sub-only-guard-claude-to-codex"
    else
      note="main-fallback-claude-to-codex"
    fi
  fi
  if [[ "${requested_assist}" == "claude" && "${claude_state}" == "degraded" && "${resolved_assist}" != "claude" && "${force_claude}" != "true" ]]; then
    if [[ -n "${note}" ]]; then
      note="${note};"
    fi
    note="${note}assist-fallback-claude-degraded->${resolved_assist}"
  fi
  if [[ "${requested_assist}" == "claude" && "${resolved_assist}" == "none" && "${claude_state}" == "exhausted" ]]; then
    if [[ -n "${note}" ]]; then
      note="${note};"
    fi
    note="${note}assist-fallback-claude-to-none"
  fi
  if [[ "${resolved_main}" == "claude" && "${requested_assist}" == "claude" && "${resolved_assist}" != "claude" && "${claude_state}" != "exhausted" && "${force_claude}" != "true" ]]; then
    if [[ -n "${note}" ]]; then
      note="${note};"
    fi
    note="${note}claude-pressure-guard-assist->${resolved_assist}"
  fi
  if [[ "${force_claude}" == "true" && "${claude_state}" != "ok" ]]; then
    if [[ -n "${note}" ]]; then
      note="${note};"
    fi
    note="${note}forced-claude-under-throttle"
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "${scenario}" \
    "${requested_main}" \
    "${requested_assist}" \
    "${claude_state}" \
    "${force_claude}" \
    "${resolved_main}" \
    "${resolved_assist}" \
    "${main_signal_lane}" \
    "${expected_lanes}" \
    "${weighted_vote}" \
    "${impl_gate}" \
    "${refinement_cycles}" \
    "${implementation_dialogue_rounds}" \
    "${preflight_gate}" \
    "${note}"
}

run_case "S1"  "codex"  "claude" "ok"        "false" "review"    "pass"   "false"
run_case "S2"  "claude" "claude" "ok"        "false" "implement" "pass"   "false"
run_case "S3"  "claude" "claude" "degraded"  "false" "review"    "pass"   "false"
run_case "S4"  "claude" "claude" "exhausted" "false" "implement" "pass"   "false"
run_case "S5"  "claude" "claude" "exhausted" "true"  "review"    "pass"   "false"
run_case "S6"  "claude" "none"   "ok"        "false" "implement" "pass"   "true"
run_case "S7"  "codex"  "codex"  "ok"        "false" "implement" "reject" "false"
run_case "S8"  "codex"  "claude" "ok"        "false" "implement" "pass"   "false"
