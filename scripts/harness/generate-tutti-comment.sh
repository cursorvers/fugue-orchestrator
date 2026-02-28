#!/usr/bin/env bash
set -euo pipefail

# generate-tutti-comment.sh — Format integrated review comment markdown.
#
# Reads all-results.json, integrated.json, integration-vars.sh and
# env vars from resolve-orchestrator, then writes integrated-comment.md.
#
# Required env vars: MAIN_PROVIDER, ASSIST_PROVIDER, MAIN_PROVIDER_REQUESTED,
#   ASSIST_PROVIDER_REQUESTED, MAIN_SIGNAL_LANE, MAIN_SIGNAL_LANES,
#   MULTI_AGENT_MODE, MULTI_AGENT_MODE_SOURCE, GLM_SUBAGENT_MODE,
#   GLM_SUBAGENT_MODE_SOURCE, CI_EXECUTION_ENGINE, SUBSCRIPTION_OFFLINE_POLICY,
#   RUN_AGENTS_RUNNER, RUN_AGENTS_RUNNER_JSON, EXECUTION_PROFILE,
#   EXECUTION_PROFILE_REASON, CONTINUITY_ACTIVE, SELF_HOSTED_ONLINE_COUNT,
#   SUBSCRIPTION_RUNNER_LABEL, STRICT_MAIN_CODEX_MODEL_EFFECTIVE,
#   STRICT_OPUS_ASSIST_DIRECT_EFFECTIVE, ASSIST_ADJUSTED_BY_EXECUTION_PROFILE,
#   ASSIST_ADJUSTMENT_REASON, EXPECTED_LANES, ISSUE_NUMBER,
#   MAIN_CLAUDE_FALLBACK_APPLIED, MAIN_CLAUDE_FALLBACK_REASON,
#   ASSIST_CLAUDE_FALLBACK_APPLIED, ASSIST_CLAUDE_FALLBACK_REASON,
#   CLAUDE_PRESSURE_GUARD_APPLIED, CLAUDE_PRESSURE_GUARD_REASON
#
# Usage: bash scripts/harness/generate-tutti-comment.sh

# Load intermediate variables from aggregation step.
# shellcheck source=/dev/null
source integration-vars.sh

approve_agents="$(jq -r '[.[] | select(.skipped != true and .approve == true) | .name] | join(", ")' all-results.json)"
reject_agents="$(jq -r '[.[] | select(.skipped != true and .approve != true) | .name] | join(", ")' all-results.json)"

security_block="$(jq -r '
  [.adopted_security_criticism[]? |
    "- **\(.agent)**\n  - findings: \(.findings | join(" | "))\n  - recommendation: \(.recommendation)"
  ] | if length==0 then "- none" else join("\n") end
' integrated.json)"

one_agent_points="$(jq -r '
  .considerations | if length==0 then "- none" else map("- " + .) | join("\n") end
' integrated.json)"

contradiction_flag="$(jq -r '.contradictions' integrated.json)"
contradiction_section="- none"
if [[ "${contradiction_flag}" == "true" ]]; then
  contradiction_section="Approve side: ${approve_agents}
Reject side: ${reject_agents}"
fi

skipped_agents="$(jq -r '
  [ .[] | select(.skipped == true) |
    "- \(.name) [\(.provider)/\(.execution_engine // "api")] (http=\(.http_code)): \((.findings | join(" | ")))"
  ] | if length==0 then "- none" else join("\n") end
' all-results.json)"

# --- Fallback / pressure guard sections ---
main_fallback_section="- main fallback: none"
if [[ "${MAIN_CLAUDE_FALLBACK_APPLIED}" == "true" ]]; then
  main_fallback_section="- main fallback: claude -> codex (\`${MAIN_CLAUDE_FALLBACK_REASON}\`)"
fi

assist_fallback_section="- assist fallback: none"
if [[ "${ASSIST_CLAUDE_FALLBACK_APPLIED}" == "true" ]]; then
  assist_fallback_reason="${ASSIST_CLAUDE_FALLBACK_REASON}"
  assist_fallback_target="none"
  if [[ "${assist_fallback_reason}" == *"->"* ]]; then
    assist_fallback_target="${assist_fallback_reason##*->}"
  fi
  assist_fallback_target="$(echo "${assist_fallback_target}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-].*$//g')"
  if [[ -z "${assist_fallback_target}" ]]; then
    assist_fallback_target="none"
  fi
  assist_fallback_section="- assist fallback: claude -> ${assist_fallback_target} (\`${assist_fallback_reason}\`)"
fi

claude_pressure_section="- claude pressure guard: none"
if [[ "${CLAUDE_PRESSURE_GUARD_APPLIED}" == "true" ]]; then
  claude_pressure_section="- claude pressure guard: applied (\`${CLAUDE_PRESSURE_GUARD_REASON}\`)"
fi

# --- Gate sections ---
required_assist_section="- required claude assist gate: not-required"
if [[ "${required_claude_assist_gate}" == "pass" ]]; then
  required_assist_section="- required claude assist gate: pass (\`${required_claude_assist_reason}\`)"
elif [[ "${required_claude_assist_gate}" == "fail" ]]; then
  required_assist_section="- required claude assist gate: fail (\`${required_claude_assist_reason}\`)"
fi

baseline_trio_section="- baseline trio gate (codex+claude+glm): not-required"
if [[ "${baseline_trio_gate}" == "pass" ]]; then
  baseline_trio_section="- baseline trio gate (codex+claude+glm): pass (\`${baseline_trio_reason}\`, codex=${codex_baseline_success}, claude=${claude_baseline_success}, glm=${glm_baseline_success})"
elif [[ "${baseline_trio_gate}" == "fail" ]]; then
  baseline_trio_section="- baseline trio gate (codex+claude+glm): fail (\`${baseline_trio_reason}\`, codex=${codex_baseline_success}, claude=${claude_baseline_success}, glm=${glm_baseline_success})"
fi

complex_assist_section="- complex claude-sub requirement: ${complex_claude_sub_required} (\`${complex_claude_sub_reason}\`)"

# --- Integrated meta JSON ---
integrated_meta="$(jq -cn \
  --arg schema "fugue-integrated-meta/v1" \
  --arg run_id "${GITHUB_RUN_ID}" \
  --arg issue_number "${ISSUE_NUMBER}" \
  --arg main "${MAIN_PROVIDER}" \
  --arg assist "${ASSIST_PROVIDER}" \
  --arg multi_agent_mode "${MULTI_AGENT_MODE}" \
  --arg glm_subagent_mode "${GLM_SUBAGENT_MODE}" \
  --arg profile "${EXECUTION_PROFILE}" \
  --arg runner "${RUN_AGENTS_RUNNER}" \
  --arg runner_labels "${RUN_AGENTS_RUNNER_JSON}" \
  --arg lanes "${EXPECTED_LANES}" \
  --arg weighted_vote "${weighted_vote_passed}" \
  --arg high_risk "${high_risk}" \
  --arg required_claude_assist_gate "${required_claude_assist_gate}" \
  --arg required_claude_assist_reason "${required_claude_assist_reason}" \
  --arg baseline_trio_gate "${baseline_trio_gate}" \
  --arg baseline_trio_reason "${baseline_trio_reason}" \
  --arg codex_baseline_success "${codex_baseline_success}" \
  --arg claude_baseline_success "${claude_baseline_success}" \
  --arg glm_baseline_success "${glm_baseline_success}" \
  --arg complex_claude_sub_required "${complex_claude_sub_required}" \
  --arg complex_claude_sub_reason "${complex_claude_sub_reason}" \
  '{
    schema:$schema,
    run_id:$run_id,
    issue_number:$issue_number,
    main_orchestrator_resolved:$main,
    assist_orchestrator_resolved:$assist,
    multi_agent_mode:$multi_agent_mode,
    glm_subagent_mode:$glm_subagent_mode,
    execution_profile:$profile,
    run_agents_runner:$runner,
    run_agents_runner_labels:(try ($runner_labels | fromjson) catch []),
    lanes_configured:($lanes | tonumber? // 0),
    weighted_vote_passed:($weighted_vote == "true"),
    high_risk:($high_risk == "true"),
    required_claude_assist_gate:$required_claude_assist_gate,
    required_claude_assist_reason:$required_claude_assist_reason,
    baseline_trio_gate:$baseline_trio_gate,
    baseline_trio_reason:$baseline_trio_reason,
    codex_baseline_success:($codex_baseline_success | tonumber? // 0),
    claude_baseline_success:($claude_baseline_success | tonumber? // 0),
    glm_baseline_success:($glm_baseline_success | tonumber? // 0),
    complex_claude_sub_required:($complex_claude_sub_required == "true"),
    complex_claude_sub_reason:$complex_claude_sub_reason
  }'
)"

# --- Write comment markdown ---
cat > integrated-comment.md <<COMMENT_EOF
## Tutti Integrated Review

- main orchestrator requested: ${MAIN_PROVIDER_REQUESTED}
- main orchestrator resolved: ${MAIN_PROVIDER}
- main orchestrator signal lane: ${MAIN_SIGNAL_LANE}
- main orchestrator signal lanes: ${MAIN_SIGNAL_LANES}
- assist orchestrator requested: ${ASSIST_PROVIDER_REQUESTED}
- assist orchestrator resolved: ${ASSIST_PROVIDER}
- multi-agent mode: ${MULTI_AGENT_MODE}
- multi-agent mode source: ${MULTI_AGENT_MODE_SOURCE}
- glm subagent mode: ${GLM_SUBAGENT_MODE}
- glm subagent mode source: ${GLM_SUBAGENT_MODE_SOURCE}
- ci execution engine: ${CI_EXECUTION_ENGINE}
- subscription offline policy: ${SUBSCRIPTION_OFFLINE_POLICY}
- run-agents runner: ${RUN_AGENTS_RUNNER}
- run-agents runner labels: ${RUN_AGENTS_RUNNER_JSON}
- execution profile: ${EXECUTION_PROFILE} (\`${EXECUTION_PROFILE_REASON}\`)
- continuity active: ${CONTINUITY_ACTIVE}
- self-hosted online count: ${SELF_HOSTED_ONLINE_COUNT}
- required subscription runner label: ${SUBSCRIPTION_RUNNER_LABEL}
- strict main codex model effective: ${STRICT_MAIN_CODEX_MODEL_EFFECTIVE}
- strict opus assist direct effective: ${STRICT_OPUS_ASSIST_DIRECT_EFFECTIVE}
- assist adjusted by execution profile: ${ASSIST_ADJUSTED_BY_EXECUTION_PROFILE} (\`${ASSIST_ADJUSTMENT_REASON}\`)
${main_fallback_section}
${assist_fallback_section}
${claude_pressure_section}
${complex_assist_section}
${required_assist_section}
${baseline_trio_section}
- lanes configured: ${EXPECTED_LANES}

**Rule a: Security criticism (unconditionally adopted)**
${security_block}

**Rule b: 3+ agents agree (high confidence)**
- approve agreement (>=3): $(jq -r '.high_confidence.approve_agreement' integrated.json)
- reject agreement (>=3): $(jq -r '.high_confidence.reject_agreement' integrated.json)

**Rule c: Single-agent points (consideration)**
${one_agent_points}

**Rule d: Contradictions (present both sides)**
${contradiction_section}

**Optional lanes skipped**
${skipped_agents}

**Consensus summary**
- approvals: ${approve_count}/${total_count}
- weighted approvals: ${weighted_approve_score}/${weighted_total_score} (threshold: ${weighted_threshold})
- weighted vote passed: ${weighted_vote_passed}
- high-risk findings: ${high_risk_count}
- approving agents: ${approve_agents}
- non-approving agents: ${reject_agents}

<!-- FUGUE_INTEGRATED_META:${integrated_meta} -->
COMMENT_EOF
