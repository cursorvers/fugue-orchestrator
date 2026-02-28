#!/usr/bin/env bash
set -euo pipefail

# aggregate-tutti-votes.sh — Aggregate agent results and compute weighted vote.
#
# Reads agent-results/*.json, computes approval counts, weighted scores,
# gate requirements, and outputs to GITHUB_OUTPUT + integration-vars.sh.
#
# Required env vars:
#   ASSIST_PROVIDER_RESOLVED, CLAUDE_RATE_LIMIT_STATE,
#   REQUIRE_DIRECT_CLAUDE_ASSIST, REQUIRE_CLAUDE_SUB_ON_COMPLEX,
#   REQUIRE_BASELINE_TRIO, INPUT_RISK_TIER,
#   INPUT_AMBIGUITY_TRANSLATION_GATE, INPUT_AMBIGUITY_TRANSLATION_SCORE,
#   INPUT_CLAUDE_SUB_TRIGGER, GITHUB_OUTPUT
#
# Usage: bash scripts/harness/aggregate-tutti-votes.sh

# --- Input normalization ---
lower_trim() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}
normalize_bool() {
  local v; v="$(lower_trim "$1")"
  [[ "${v}" == "true" ]] && printf 'true' || printf 'false'
}

jq -s '.' agent-results/*.json > all-results.json

total_count="$(jq '[.[] | select(.skipped != true)] | length' all-results.json)"
approve_count="$(jq '[.[] | select(.skipped != true and .approve == true)] | length' all-results.json)"
high_risk_count="$(jq '[.[] | select(.skipped != true and (.risk|ascii_upcase) == "HIGH")] | length' all-results.json)"
high_risk="false"
if [[ "${high_risk_count}" -gt 0 ]]; then
  high_risk="true"
fi

assist_provider_resolved="$(lower_trim "${ASSIST_PROVIDER_RESOLVED:-none}")"
if [[ "${assist_provider_resolved}" != "claude" && "${assist_provider_resolved}" != "codex" && "${assist_provider_resolved}" != "none" ]]; then
  assist_provider_resolved="none"
fi
claude_state="$(lower_trim "${CLAUDE_RATE_LIMIT_STATE:-ok}")"
if [[ "${claude_state}" != "ok" && "${claude_state}" != "degraded" && "${claude_state}" != "exhausted" ]]; then
  claude_state="ok"
fi
require_direct_claude_assist="$(normalize_bool "${REQUIRE_DIRECT_CLAUDE_ASSIST:-false}")"
require_claude_sub_on_complex="$(lower_trim "${REQUIRE_CLAUDE_SUB_ON_COMPLEX:-true}")"
if [[ "${require_claude_sub_on_complex}" != "false" ]]; then
  require_claude_sub_on_complex="true"
fi
require_baseline_trio="$(lower_trim "${REQUIRE_BASELINE_TRIO:-true}")"
if [[ "${require_baseline_trio}" != "false" ]]; then
  require_baseline_trio="true"
fi
input_risk_tier="$(lower_trim "${INPUT_RISK_TIER:-}")"
if [[ "${input_risk_tier}" != "low" && "${input_risk_tier}" != "medium" && "${input_risk_tier}" != "high" ]]; then
  input_risk_tier=""
fi
ambiguity_translation_gate="$(normalize_bool "${INPUT_AMBIGUITY_TRANSLATION_GATE:-false}")"
ambiguity_translation_score="$(echo "${INPUT_AMBIGUITY_TRANSLATION_SCORE:-0}" | tr -cd '0-9')"
if [[ -z "${ambiguity_translation_score}" ]]; then
  ambiguity_translation_score="0"
fi
claude_sub_trigger="$(echo "${INPUT_CLAUDE_SUB_TRIGGER:-none}" | tr '\n\r' ' ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -z "${claude_sub_trigger}" ]]; then
  claude_sub_trigger="none"
fi

# --- Complex Claude sub requirement ---
complex_claude_sub_required="false"
complex_claude_sub_reason="not-required"
if [[ "${require_claude_sub_on_complex}" == "true" ]]; then
  if [[ "${assist_provider_resolved}" != "claude" ]]; then
    complex_claude_sub_reason="complex-policy-assist-${assist_provider_resolved}"
  elif [[ "${input_risk_tier}" == "high" ]]; then
    complex_claude_sub_required="true"
    complex_claude_sub_reason="risk-high"
  elif [[ "${ambiguity_translation_gate}" == "true" ]]; then
    complex_claude_sub_required="true"
    complex_claude_sub_reason="ambiguity-translation-gate(score=${ambiguity_translation_score},trigger=${claude_sub_trigger})"
  else
    complex_claude_sub_reason="complex-not-required"
  fi
else
  complex_claude_sub_reason="complex-policy-disabled"
fi

# --- Claude lane health ---
claude_opus_lane_total="$(jq '[.[] | select(.name == "claude-opus-assist")] | length' all-results.json)"
claude_opus_lane_success="$(jq '[
  .[] | select(
    .name == "claude-opus-assist"
    and .skipped != true
    and ((.provider // "" | ascii_downcase) == "claude")
    and (
      ((.http_code // "" | tostring) == "200")
      or
      ((.http_code // "" | tostring | startswith("cli:0")))
    )
  )
] | length' all-results.json)"
claude_lane_http_error_count="$(jq '[
  .[] | select(
    ((.provider // "" | ascii_downcase) == "claude")
    and (
      ((.http_code // "" | tostring) | test("^[45][0-9][0-9]$"))
    )
  )
] | length' all-results.json)"

claude_state_effective="${claude_state}"
claude_state_adjustment="none"
if [[ "${claude_state}" == "ok" && "${claude_opus_lane_total}" -gt 0 && "${claude_opus_lane_success}" -eq 0 && "${claude_lane_http_error_count}" -gt 0 ]]; then
  claude_state_effective="degraded"
  claude_state_adjustment="auto-degraded-claude-http-errors"
fi

# --- Gate evaluation ---
gate_required="false"
gate_requirement_kind="none"
if [[ "${complex_claude_sub_required}" == "true" ]]; then
  gate_required="true"
  gate_requirement_kind="complex"
fi
if [[ "${assist_provider_resolved}" == "claude" && "${claude_state_effective}" == "ok" && "${require_direct_claude_assist}" == "true" ]]; then
  gate_required="true"
  if [[ "${gate_requirement_kind}" == "complex" ]]; then
    gate_requirement_kind="complex+direct"
  else
    gate_requirement_kind="direct"
  fi
fi

required_claude_assist_gate="not-required"
required_claude_assist_reason="none"
if [[ "${gate_required}" == "true" ]]; then
  required_claude_assist_gate="pass"
  required_claude_assist_reason="${gate_requirement_kind}-ok"
  if [[ "${assist_provider_resolved}" != "claude" ]]; then
    required_claude_assist_gate="fail"
    required_claude_assist_reason="${gate_requirement_kind}-assist-${assist_provider_resolved}"
  elif [[ "${claude_state_effective}" == "exhausted" ]]; then
    required_claude_assist_gate="fail"
    required_claude_assist_reason="${gate_requirement_kind}-claude-rate-limit-exhausted"
  elif [[ "${claude_opus_lane_total}" -eq 0 ]]; then
    required_claude_assist_gate="fail"
    required_claude_assist_reason="${gate_requirement_kind}-missing-claude-opus-assist-lane"
  elif [[ "${claude_opus_lane_success}" -eq 0 ]]; then
    required_claude_assist_gate="fail"
    required_claude_assist_reason="${gate_requirement_kind}-claude-opus-assist-not-success"
  fi
  if [[ "${required_claude_assist_gate}" == "fail" ]]; then
    high_risk="true"
    high_risk_count="$((high_risk_count + 1))"
  fi
else
  if [[ "${assist_provider_resolved}" == "claude" && "${claude_state_effective}" != "ok" ]]; then
    required_claude_assist_reason="claude-rate-limit-${claude_state_effective}"
    if [[ "${claude_state_adjustment}" != "none" ]]; then
      required_claude_assist_reason="${required_claude_assist_reason}+${claude_state_adjustment}"
    fi
  elif [[ "${complex_claude_sub_required}" != "true" && "${require_claude_sub_on_complex}" == "true" ]]; then
    required_claude_assist_reason="${complex_claude_sub_reason}"
  elif [[ "${require_direct_claude_assist}" != "true" ]]; then
    required_claude_assist_reason="direct-policy-disabled"
  else
    required_claude_assist_reason="policy-disabled"
  fi
fi

# --- Baseline trio gate ---
baseline_trio_gate="not-required"
baseline_trio_reason="policy-disabled"

# Reusable jq filter for provider success count.
provider_success_filter='[
  .[] | select(
    .skipped != true
    and ((.provider // "" | ascii_downcase) == $provider)
    and (
      ((.http_code // "" | tostring) == "200")
      or
      ((.http_code // "" | tostring | startswith("cli:0")))
    )
  )
] | length'

codex_baseline_success="$(jq -r --arg provider "codex" "${provider_success_filter}" all-results.json)"
claude_baseline_success="$(jq -r --arg provider "claude" "${provider_success_filter}" all-results.json)"
glm_baseline_success="$(jq -r '[
  .[] | select(
    .skipped != true
    and ((.provider // "" | ascii_downcase) == "glm")
    and ((.name // "") | test("^glm-.*-subagent$") | not)
    and (
      ((.http_code // "" | tostring) == "200")
      or
      ((.http_code // "" | tostring | startswith("cli:0")))
    )
  )
] | length' all-results.json)"

if [[ "${require_baseline_trio}" == "true" ]]; then
  baseline_trio_gate="pass"
  baseline_missing=()
  require_claude_baseline="true"
  if [[ "${assist_provider_resolved}" == "claude" && "${claude_state_effective}" != "ok" ]]; then
    require_claude_baseline="false"
  fi
  if [[ "${codex_baseline_success}" -eq 0 ]]; then
    baseline_missing+=("codex")
  fi
  if [[ "${require_claude_baseline}" == "true" && "${claude_baseline_success}" -eq 0 ]]; then
    baseline_missing+=("claude")
  fi
  if [[ "${glm_baseline_success}" -eq 0 ]]; then
    baseline_missing+=("glm")
  fi
  if (( ${#baseline_missing[@]} > 0 )); then
    baseline_trio_gate="fail"
    baseline_trio_reason="missing-$(IFS=,; echo "${baseline_missing[*]}")"
    high_risk="true"
    high_risk_count="$((high_risk_count + 1))"
  else
    if [[ "${require_claude_baseline}" == "true" ]]; then
      baseline_trio_reason="codex+claude+glm-ok"
    else
      baseline_trio_reason="codex+glm-ok(claude-waived-${claude_state_effective})"
    fi
  fi
fi

# --- Weighted vote calculation ---
# Role weight table (shared between total and approve).
WEIGHT_TABLE='
  (if (.agent_role|test("security-analyst";"i")) then 1.4
   elif (.agent_role|test("code-reviewer";"i")) then 1.2
   elif (.agent_role|test("architect";"i")) then 1.1
   elif (.agent_role|test("reliability-engineer|invariants-checker";"i")) then 1.1
   elif (.agent_role|test("general-reviewer|plan-reviewer|general-critic";"i")) then 1.0
   elif (.agent_role|test("refactor-advisor";"i")) then 0.9
   elif (.agent_role|test("math-reasoning|orchestration-assistant|main-orchestrator|ui-reviewer";"i")) then 0.8
   elif (.agent_role|test("realtime-info";"i")) then 0.7
   else 1.0 end)
'

if [[ "${total_count}" -eq 0 ]]; then
  threshold=1
else
  threshold=$(( (total_count * 2 + 2) / 3 ))
fi
weighted_total_score="$(jq -r "[ .[] | select(.skipped != true) | ${WEIGHT_TABLE} ] | add // 0" all-results.json)"
weighted_approve_score="$(jq -r "[ .[] | select(.skipped != true and .approve == true) | ${WEIGHT_TABLE} ] | add // 0" all-results.json)"
weighted_threshold="$(awk -v total="${weighted_total_score}" 'BEGIN {printf "%.3f", (2*total)/3}')"
weighted_vote_passed="$(awk -v approve="${weighted_approve_score}" -v threshold="${weighted_threshold}" 'BEGIN { if (approve + 1e-9 >= threshold) print "true"; else print "false" }')"

ok_to_execute="false"
if [[ "${required_claude_assist_gate}" == "fail" || "${baseline_trio_gate}" == "fail" ]]; then
  weighted_vote_passed="false"
fi
if [[ "${weighted_vote_passed}" == "true" && "${high_risk}" != "true" ]]; then
  ok_to_execute="true"
fi

# --- Generate integrated analysis JSON ---
jq '
  {
    adopted_security_criticism: [
      .[] | select(.skipped != true and (.agent_role|test("security";"i")) and ((.findings|length) > 0)) |
      {agent: .name, findings: .findings, recommendation: .recommendation}
    ],
    high_confidence: {
      approve_agreement: (([.[] | select(.skipped != true and .approve == true)] | length) >= 3),
      reject_agreement: (([.[] | select(.skipped != true and .approve != true)] | length) >= 3)
    },
    considerations: (
      [ .[] | select(.skipped != true) | .findings[] ] | group_by(.) | map(select(length == 1) | .[0])
    ),
    contradictions: (
      ([.[] | select(.skipped != true and .approve == true)] | length) > 0 and
      ([.[] | select(.skipped != true and .approve != true)] | length) > 0
    ),
    by_agent: [ .[] | select(.skipped != true) | {name, provider, execution_engine, agent_role, risk, approve, findings, recommendation, rationale} ]
  }
' all-results.json > integrated.json

# --- Write GITHUB_OUTPUT ---
{
  echo "high_risk=${high_risk}"
  echo "approve_count=${approve_count}"
  echo "total_count=${total_count}"
  echo "threshold=${threshold}"
  echo "weighted_approve_score=${weighted_approve_score}"
  echo "weighted_total_score=${weighted_total_score}"
  echo "weighted_threshold=${weighted_threshold}"
  echo "weighted_vote_passed=${weighted_vote_passed}"
  echo "vote_passed=${weighted_vote_passed}"
  echo "ok_to_execute=${ok_to_execute}"
} >> "${GITHUB_OUTPUT}"

# --- Save intermediate variables for comment generation ---
_esc() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }
{
  echo "approve_count='$(_esc "${approve_count}")'"
  echo "total_count='$(_esc "${total_count}")'"
  echo "high_risk_count='$(_esc "${high_risk_count}")'"
  echo "high_risk='$(_esc "${high_risk}")'"
  echo "weighted_approve_score='$(_esc "${weighted_approve_score}")'"
  echo "weighted_total_score='$(_esc "${weighted_total_score}")'"
  echo "weighted_threshold='$(_esc "${weighted_threshold}")'"
  echo "weighted_vote_passed='$(_esc "${weighted_vote_passed}")'"
  echo "required_claude_assist_gate='$(_esc "${required_claude_assist_gate}")'"
  echo "required_claude_assist_reason='$(_esc "${required_claude_assist_reason}")'"
  echo "baseline_trio_gate='$(_esc "${baseline_trio_gate}")'"
  echo "baseline_trio_reason='$(_esc "${baseline_trio_reason}")'"
  echo "codex_baseline_success='$(_esc "${codex_baseline_success}")'"
  echo "claude_baseline_success='$(_esc "${claude_baseline_success}")'"
  echo "glm_baseline_success='$(_esc "${glm_baseline_success}")'"
  echo "complex_claude_sub_required='$(_esc "${complex_claude_sub_required}")'"
  echo "complex_claude_sub_reason='$(_esc "${complex_claude_sub_reason}")'"
} > integration-vars.sh
