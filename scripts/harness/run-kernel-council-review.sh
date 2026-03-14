#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root_dir="$(cd "${script_dir}/../.." && pwd)"

build_matrix_script="${FUGUE_BUILD_MATRIX_SCRIPT:-${root_dir}/scripts/lib/build-agent-matrix.sh}"
subscription_runner_script="${FUGUE_SUBSCRIPTION_RUNNER_SCRIPT:-${root_dir}/scripts/harness/subscription-agent-runner.sh}"
aggregate_script="${FUGUE_AGGREGATE_VOTES_SCRIPT:-${root_dir}/scripts/harness/aggregate-tutti-votes.sh}"

stage="$(echo "${COUNCIL_STAGE:-review}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -z "${stage}" ]]; then
  stage="review"
fi

issue_number="$(echo "${ISSUE_NUMBER:-0}" | tr -cd '0-9')"
if [[ -z "${issue_number}" ]]; then
  issue_number="0"
fi

run_dir_input="${COUNCIL_RUN_DIR:-.fugue/kernel-council/${stage}}"
case "${run_dir_input}" in
  /*) run_dir="${run_dir_input}" ;;
  *) run_dir="${PWD}/${run_dir_input}" ;;
esac
agent_dir="${run_dir}/agent-results"
mkdir -p "${agent_dir}"
step_output_file="${GITHUB_OUTPUT:-${run_dir}/step-output.txt}"
council_status_file="${COUNCIL_STATUS_FILE:-${run_dir}/council-status.json}"
baseline_trio_gate="fail"
baseline_trio_reason="aggregate-not-run"
required_claude_assist_gate="not-evaluated"
required_claude_assist_reason="aggregate-not-run"
weighted_vote_value="false"
ok_to_execute_value="false"
council_failure_stage=""
council_failure_reason=""
recovery_attempted_value="false"
recovery_failure_reason=""
council_force_missing_provider="none"

main_provider="$(echo "${COUNCIL_MAIN_PROVIDER:-codex}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
assist_provider="$(echo "${COUNCIL_ASSIST_PROVIDER:-claude}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
multi_agent_mode="$(echo "${COUNCIL_MULTI_AGENT_MODE:-standard}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
glm_subagent_mode="$(echo "${COUNCIL_GLM_SUBAGENT_MODE:-off}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
council_execution_profile="$(echo "${COUNCIL_EXECUTION_PROFILE:-subscription-strict}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${council_execution_profile}" != "subscription-strict" && "${council_execution_profile}" != "local-direct" ]]; then
  council_execution_profile="subscription-strict"
fi
force_copilot_continuity="$(echo "${COUNCIL_FORCE_COPILOT_CONTINUITY:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${force_copilot_continuity}" != "true" ]]; then
  force_copilot_continuity="false"
fi
council_recovery_attempted="$(echo "${COUNCIL_RECOVERY_ATTEMPTED:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${council_recovery_attempted}" != "true" ]]; then
  council_recovery_attempted="false"
fi
recovery_attempted_value="${council_recovery_attempted}"
council_wants_gemini="$(echo "${COUNCIL_WANTS_GEMINI:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${council_wants_gemini}" != "true" ]]; then
  council_wants_gemini="false"
fi
council_wants_xai="$(echo "${COUNCIL_WANTS_XAI:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${council_wants_xai}" != "true" ]]; then
  council_wants_xai="false"
fi
council_metered_reason_override="$(echo "${COUNCIL_METERED_REASON_OVERRIDE:-none}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${council_metered_reason_override}" != "overflow" && "${council_metered_reason_override}" != "tie-break" ]]; then
  council_metered_reason_override="none"
fi
claude_assist_execution_policy="$(echo "${CLAUDE_ASSIST_EXECUTION_POLICY:-hybrid}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_assist_execution_policy}" != "direct" && "${claude_assist_execution_policy}" != "hybrid" && "${claude_assist_execution_policy}" != "proxy" ]]; then
  claude_assist_execution_policy="hybrid"
fi
strict_opus_assist_direct="$(echo "${STRICT_OPUS_ASSIST_DIRECT:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${strict_opus_assist_direct}" != "true" ]]; then
  strict_opus_assist_direct="false"
fi
council_force_missing_provider="$(echo "${COUNCIL_FORCE_MISSING_PROVIDER:-none}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${council_force_missing_provider}" != "glm" ]]; then
  council_force_missing_provider="none"
fi
max_parallel="$(echo "${COUNCIL_MAX_PARALLEL:-6}" | tr -cd '0-9')"
if [[ -z "${max_parallel}" ]]; then
  max_parallel="6"
fi
if (( max_parallel < 2 )); then
  max_parallel=2
elif (( max_parallel > 12 )); then
  max_parallel=12
fi

write_council_status_snapshot() {
  local tmp_council_status_file=""
  tmp_council_status_file="$(mktemp "${run_dir}/council-status.XXXXXX.json")"
  jq -n \
    --arg stage "${stage}" \
    --arg run_dir "${run_dir}" \
    --arg issue_number "${issue_number}" \
    --arg execution_profile "${council_execution_profile}" \
    --arg main_provider "${main_provider}" \
    --arg assist_provider "${assist_provider}" \
    --arg force_copilot_continuity "${force_copilot_continuity}" \
    --arg max_parallel "${max_parallel}" \
    --arg weighted_vote_passed "${weighted_vote_value}" \
    --arg ok_to_execute "${ok_to_execute_value}" \
    --arg baseline_trio_gate "${baseline_trio_gate}" \
    --arg baseline_trio_reason "${baseline_trio_reason}" \
    --arg required_claude_assist_gate "${required_claude_assist_gate}" \
    --arg required_claude_assist_reason "${required_claude_assist_reason}" \
    --arg council_status_file "${council_status_file}" \
    --arg failure_stage "${council_failure_stage}" \
    --arg failure_reason "${council_failure_reason}" \
    --arg recovery_attempted "${recovery_attempted_value}" \
    --arg recovery_failure_reason "${recovery_failure_reason}" \
    --arg force_missing_provider "${council_force_missing_provider}" \
    '{
      stage:$stage,
      run_dir:$run_dir,
      issue_number:($issue_number | tonumber? // 0),
      execution_engine:"kernel-council",
      execution_profile:$execution_profile,
      main_provider:$main_provider,
      assist_provider:$assist_provider,
      force_copilot_continuity:($force_copilot_continuity == "true"),
      max_parallel:($max_parallel | tonumber? // 0),
      weighted_vote_passed:($weighted_vote_passed == "true"),
      ok_to_execute:($ok_to_execute == "true"),
      baseline_trio_gate:$baseline_trio_gate,
      baseline_trio_reason:$baseline_trio_reason,
      required_claude_assist_gate:$required_claude_assist_gate,
      required_claude_assist_reason:$required_claude_assist_reason,
      council_status_file:$council_status_file,
      recovery_attempted:($recovery_attempted == "true"),
      recovery_failure_reason:(if ($recovery_failure_reason | length) > 0 then $recovery_failure_reason else null end),
      force_missing_provider:(if ($force_missing_provider | length) > 0 and $force_missing_provider != "none" then $force_missing_provider else null end),
      status:(
        if ($failure_stage | length) > 0 then "error"
        elif ($ok_to_execute == "true") then "pass"
        else "fail"
        end
      ),
      failure_stage:(if ($failure_stage | length) > 0 then $failure_stage else null end),
      failure_reason:(if ($failure_reason | length) > 0 then $failure_reason else null end)
    }' > "${tmp_council_status_file}"
  mv "${tmp_council_status_file}" "${council_status_file}"
}

emit_council_step_outputs() {
  {
    echo "council_stage=${stage}"
    echo "council_run_dir=${run_dir}"
    echo "council_ok=${ok_to_execute_value}"
    echo "council_weighted_vote_passed=${weighted_vote_value}"
    echo "council_baseline_trio_gate=${baseline_trio_gate}"
    echo "council_baseline_trio_reason=${baseline_trio_reason}"
    echo "council_required_claude_assist_gate=${required_claude_assist_gate}"
    echo "council_required_claude_assist_reason=${required_claude_assist_reason}"
    echo "council_failure_stage=${council_failure_stage}"
    echo "council_failure_reason=${council_failure_reason}"
    echo "council_recovery_attempted=${recovery_attempted_value}"
    echo "council_recovery_failure_reason=${recovery_failure_reason}"
    echo "council_force_missing_provider=${council_force_missing_provider}"
  } >> "${step_output_file}"
}

attempt_recovery_matrix() {
  local reason="$1"
  local recovery_run_dir="${run_dir}/recovery-attempt-1"
  local recovery_stdout="${recovery_run_dir}/stdout.log"
  local recovery_stderr="${recovery_run_dir}/stderr.log"
  local nested_failure_stage=""
  local nested_failure_reason=""
  local rc=0

  if [[ "${council_recovery_attempted}" == "true" ]]; then
    return 1
  fi

  echo "Kernel council ${stage} attempting recovery matrix: ${reason}" >&2
  mkdir -p "${recovery_run_dir}"
  recovery_attempted_value="true"

  set +e
  env \
    COUNCIL_RECOVERY_ATTEMPTED="true" \
    COUNCIL_FORCE_COPILOT_CONTINUITY="true" \
    COUNCIL_WANTS_GEMINI="true" \
    COUNCIL_WANTS_XAI="true" \
    COUNCIL_METERED_REASON_OVERRIDE="${COUNCIL_RECOVERY_METERED_REASON:-overflow}" \
    COUNCIL_RUN_DIR="${recovery_run_dir}" \
    bash "$0" > "${recovery_stdout}" 2> "${recovery_stderr}"
  rc=$?
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    recovery_failure_reason=""
    if [[ -f "${recovery_run_dir}/council-status.json" ]]; then
      cp "${recovery_run_dir}/council-status.json" "${run_dir}/council-status.json"
    fi
    if [[ -f "${recovery_run_dir}/aggregate-output.txt" ]]; then
      cp "${recovery_run_dir}/aggregate-output.txt" "${run_dir}/aggregate-output.txt"
    fi
    if [[ -f "${recovery_run_dir}/integration-vars.sh" ]]; then
      cp "${recovery_run_dir}/integration-vars.sh" "${run_dir}/integration-vars.sh"
    fi
    return 0
  fi

  if [[ -f "${recovery_run_dir}/council-status.json" ]]; then
    nested_failure_stage="$(jq -r '.failure_stage // empty' "${recovery_run_dir}/council-status.json" 2>/dev/null || true)"
    nested_failure_reason="$(jq -r '.failure_reason // empty' "${recovery_run_dir}/council-status.json" 2>/dev/null || true)"
  fi
  if [[ -z "${nested_failure_reason}" && -f "${recovery_stderr}" ]]; then
    nested_failure_reason="$(tail -n 20 "${recovery_stderr}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+|[[:space:]]+$//g')"
  fi
  if [[ -n "${nested_failure_stage}" || -n "${nested_failure_reason}" ]]; then
    recovery_failure_reason="rc=${rc};stage=${nested_failure_stage:-unknown};reason=${nested_failure_reason:-unknown}"
  else
    recovery_failure_reason="rc=${rc};reason=unknown"
  fi
  return 1
}

issue_title="${ISSUE_TITLE:-Kernel council review}"
issue_body="${ISSUE_BODY:-}"
extra_context="$(printf '%s' "${COUNCIL_EXTRA_CONTEXT:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
composed_body="${issue_body}"
if [[ -n "${extra_context}" ]]; then
  composed_body="$(printf '%s\n\n## Kernel Council Context\n%s\n' "${issue_body}" "${extra_context}")"
fi

matrix_build_stdout="${run_dir}/matrix-build.stdout.log"
matrix_build_stderr="${run_dir}/matrix-build.stderr.log"
set +e
bash "${build_matrix_script}" \
  --engine subscription \
  --main-provider "${main_provider}" \
  --assist-provider "${assist_provider}" \
  --multi-agent-mode "${multi_agent_mode}" \
  --glm-subagent-mode "${glm_subagent_mode}" \
  --allow-glm-in-subscription true \
  --wants-gemini "${council_wants_gemini}" \
  --wants-xai "${council_wants_xai}" \
  --metered-reason "${council_metered_reason_override}" \
  --codex-main-model "${CODEX_MAIN_MODEL:-gpt-5.4}" \
  --codex-multi-agent-model "${CODEX_MULTI_AGENT_MODEL:-gpt-5-codex}" \
  --glm-model "${GLM_MODEL:-glm-5}" \
  --claude-opus-model "${CLAUDE_OPUS_MODEL:-claude-opus-4-6}" \
  --claude-sonnet4-model "${CLAUDE_SONNET4_MODEL:-claude-opus-4-6}" \
  --claude-sonnet6-model "${CLAUDE_SONNET6_MODEL:-claude-opus-4-6}" \
  --gemini-model "${GEMINI_MODEL:-gemini-2.5-pro}" \
  --xai-model "${XAI_MODEL_LATEST:-grok-4}" \
  --format json > "${matrix_build_stdout}" 2> "${matrix_build_stderr}"
matrix_build_rc=$?
set -e
if [[ "${matrix_build_rc}" -ne 0 ]]; then
  if attempt_recovery_matrix "build-agent-matrix-exit-${matrix_build_rc}"; then
    exit 0
  fi
  council_failure_stage="matrix"
  council_failure_reason="build-agent-matrix-exit-${matrix_build_rc}"
  write_council_status_snapshot
  emit_council_step_outputs
  echo "Kernel council ${stage} failed before lane execution: ${council_failure_reason}" >&2
  exit "${matrix_build_rc}"
fi
matrix_payload="$(cat "${matrix_build_stdout}")"
printf '%s\n' "${matrix_payload}" > "${run_dir}/matrix.json"

write_fallback_result() {
  local lane_json="$1"
  local out_file="$2"
  jq -n \
    --arg name "$(jq -r '.name' <<<"${lane_json}")" \
    --arg provider "$(jq -r '.provider' <<<"${lane_json}")" \
    --arg api_url "$(jq -r '.api_url // ""' <<<"${lane_json}")" \
    --arg model "$(jq -r '.model' <<<"${lane_json}")" \
    --arg agent_role "$(jq -r '.agent_role' <<<"${lane_json}")" \
    --arg rationale "Kernel council lane crashed before producing JSON output" \
    '{
      name:$name,
      provider:$provider,
      api_url:$api_url,
      model:$model,
      agent_role:$agent_role,
      http_code:"runner-crash",
      skipped:false,
      risk:"HIGH",
      approve:false,
      findings:["Council lane failed before producing a structured verdict"],
      recommendation:"Inspect lane stderr log and rerun council review",
      rationale:$rationale,
      execution_engine:"kernel-council"
    }' > "${out_file}"
}

run_lane() {
  local lane_json="$1"
  local name provider model api_url agent_role directive metered_reason effective_metered_reason lane_dir out_json
  name="$(jq -r '.name' <<<"${lane_json}")"
  provider="$(jq -r '.provider' <<<"${lane_json}")"
  model="$(jq -r '.model' <<<"${lane_json}")"
  api_url="$(jq -r '.api_url // ""' <<<"${lane_json}")"
  agent_role="$(jq -r '.agent_role' <<<"${lane_json}")"
  directive="$(jq -r '.agent_directive // ""' <<<"${lane_json}")"
  metered_reason="$(jq -r '.metered_reason // "none"' <<<"${lane_json}")"
  effective_metered_reason="${metered_reason}"
  if [[ "${effective_metered_reason}" == "none" && "${council_metered_reason_override}" != "none" ]]; then
    effective_metered_reason="${council_metered_reason_override}"
  fi
  lane_dir="${run_dir}/${name}"
  out_json="${agent_dir}/${name}.json"

  mkdir -p "${lane_dir}"
  (
    set +e
    cd "${lane_dir}"
    ISSUE_TITLE="${issue_title}" \
    ISSUE_BODY="${composed_body}" \
    ZAI_API_KEY="$(if [[ "${provider}" == "glm" && "${council_force_missing_provider}" == "glm" ]]; then printf ''; else printf '%s' "${ZAI_API_KEY:-}"; fi)" \
    GEMINI_API_KEY="${GEMINI_API_KEY:-}" \
    XAI_API_KEY="${XAI_API_KEY:-}" \
    PROVIDER="${provider}" \
    MODEL="${model}" \
    API_URL="${api_url}" \
    AGENT_ROLE="${agent_role}" \
    AGENT_NAME="${name}" \
    AGENT_DIRECTIVE="${directive}" \
    METERED_PROVIDER_REASON="${effective_metered_reason}" \
    CLAUDE_MAX_PLAN="${CLAUDE_MAX_PLAN:-true}" \
    CLAUDE_ASSIST_EXECUTION_POLICY="${claude_assist_execution_policy}" \
    CLAUDE_OPUS_MODEL="${CLAUDE_OPUS_MODEL:-claude-opus-4-6}" \
    CODEX_MAIN_MODEL="${CODEX_MAIN_MODEL:-gpt-5.4}" \
    CODEX_MULTI_AGENT_MODEL="${CODEX_MULTI_AGENT_MODEL:-gpt-5-codex}" \
    GLM_MODEL="${GLM_MODEL:-glm-5}" \
    XAI_MODEL_LATEST="${XAI_MODEL_LATEST:-grok-4}" \
    GEMINI_FALLBACK_MODEL="${GEMINI_FALLBACK_MODEL:-gemini-2.5-flash}" \
    COPILOT_GITHUB_TOKEN="${COPILOT_GITHUB_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}" \
    COPILOT_CLI_BIN="${COPILOT_CLI_BIN:-copilot}" \
    HAS_COPILOT_CLI="${HAS_COPILOT_CLI:-false}" \
    HAS_CLAUDE_CLI="$(if [[ "${force_copilot_continuity}" == "true" ]]; then echo "false"; else printf '%s' "${HAS_CLAUDE_CLI:-}"; fi)" \
    STRICT_MAIN_CODEX_MODEL="${STRICT_MAIN_CODEX_MODEL:-true}" \
    STRICT_OPUS_ASSIST_DIRECT="${strict_opus_assist_direct}" \
    CI_EXECUTION_ENGINE="subscription" \
    EXECUTION_PROFILE="${council_execution_profile}" \
    bash "${subscription_runner_script}" > "${lane_dir}/stdout.log" 2> "${lane_dir}/stderr.log"
    rc=$?
    if [[ -f "agent-${name}.json" ]]; then
      cp "agent-${name}.json" "${out_json}"
    else
      write_fallback_result "${lane_json}" "${out_json}"
    fi
    echo "${rc}" > "${lane_dir}/exit_code.txt"
    exit 0
  ) &
}

while IFS= read -r lane_json; do
  while (( $(jobs -pr | wc -l | tr -d ' ') >= max_parallel )); do
    sleep 1
  done
  run_lane "${lane_json}"
done < <(jq -cr '.matrix.include[]' "${run_dir}/matrix.json")

wait

set +e
(
  cd "${run_dir}"
  ASSIST_PROVIDER_RESOLVED="${assist_provider}" \
  CLAUDE_RATE_LIMIT_STATE="${CLAUDE_RATE_LIMIT_STATE:-ok}" \
  REQUIRE_DIRECT_CLAUDE_ASSIST="false" \
  REQUIRE_CLAUDE_SUB_ON_COMPLEX="true" \
  REQUIRE_BASELINE_TRIO="true" \
  INPUT_RISK_TIER="${RISK_TIER:-medium}" \
  INPUT_AMBIGUITY_TRANSLATION_GATE="false" \
  INPUT_AMBIGUITY_TRANSLATION_SCORE="0" \
  INPUT_CLAUDE_SUB_TRIGGER="kernel-council-${stage}" \
  VOTE_COMMAND_INPUT="${VOTE_COMMAND_INPUT:-false}" \
  GITHUB_OUTPUT="${run_dir}/aggregate-output.txt" \
  bash "${aggregate_script}"
)
aggregate_rc=$?
set -e
if [[ "${aggregate_rc}" -ne 0 ]]; then
  if attempt_recovery_matrix "aggregate-script-exit-${aggregate_rc}"; then
    exit 0
  fi
  council_failure_stage="aggregate"
  council_failure_reason="aggregate-script-exit-${aggregate_rc}"
  write_council_status_snapshot
  emit_council_step_outputs
  echo "Kernel council ${stage} failed before aggregation completed: ${council_failure_reason}" >&2
  exit "${aggregate_rc}"
fi

if [[ ! -f "${run_dir}/integration-vars.sh" ]]; then
  if attempt_recovery_matrix "missing-integration-vars"; then
    exit 0
  fi
  council_failure_stage="integration-vars"
  council_failure_reason="missing-integration-vars"
  write_council_status_snapshot
  emit_council_step_outputs
  echo "Kernel council ${stage} failed: ${council_failure_reason}" >&2
  exit 1
fi

# shellcheck disable=SC1090
if ! source "${run_dir}/integration-vars.sh"; then
  if attempt_recovery_matrix "source-integration-vars-failed"; then
    exit 0
  fi
  council_failure_stage="integration-vars"
  council_failure_reason="source-integration-vars-failed"
  write_council_status_snapshot
  emit_council_step_outputs
  echo "Kernel council ${stage} failed: ${council_failure_reason}" >&2
  exit 1
fi

if [[ ! -f "${run_dir}/aggregate-output.txt" ]]; then
  if attempt_recovery_matrix "missing-aggregate-output"; then
    exit 0
  fi
  council_failure_stage="aggregate-output"
  council_failure_reason="missing-aggregate-output"
  write_council_status_snapshot
  emit_council_step_outputs
  echo "Kernel council ${stage} failed: ${council_failure_reason}" >&2
  exit 1
fi

weighted_vote_value="$(grep -E '^weighted_vote_passed=' "${run_dir}/aggregate-output.txt" | head -n1 | cut -d= -f2- || true)"
ok_to_execute_value="$(grep -E '^ok_to_execute=' "${run_dir}/aggregate-output.txt" | head -n1 | cut -d= -f2- || true)"
if [[ -z "${weighted_vote_value}" || -z "${ok_to_execute_value}" ]]; then
  if attempt_recovery_matrix "missing-weighted-vote-or-ok-to-execute"; then
    exit 0
  fi
  council_failure_stage="aggregate-output"
  council_failure_reason="missing-weighted-vote-or-ok-to-execute"
  weighted_vote_value="false"
  ok_to_execute_value="false"
  write_council_status_snapshot
  emit_council_step_outputs
  echo "Kernel council ${stage} failed: ${council_failure_reason}" >&2
  exit 1
fi

# --- Force-missing-provider shadow recovery override ---
# When council_force_missing_provider is active and shadow continuity provides
# adequate coverage (>= 2 families), promote baseline_trio_gate from fail to
# recovery-pass. This handles the implement job scenario where forced provider
# absence plus copilot continuity causes all three baseline providers to be
# unavailable, but shadow continuity (copilot, gemini, xai) provides coverage.
# Does NOT override genuine vote rejections — only infrastructure gaps.
if [[ "${baseline_trio_gate}" == "fail" \
      && "${council_force_missing_provider}" != "none" \
      && "${shadow_continuity_success_count:-0}" -ge 2 ]]; then
  baseline_trio_gate="recovery-pass"
  baseline_trio_reason="${baseline_trio_reason};force-missing=${council_force_missing_provider};shadow-quorum=${shadow_continuity_families}"
  recovery_attempted_value="true"
  _fmp_vote_pass="$(awk \
    -v a="${weighted_approve_score:-0}" \
    -v t="${weighted_threshold:-0}" \
    'BEGIN{if(a+1e-9>=t)print"true";else print"false"}')"
  if [[ "${_fmp_vote_pass}" == "true" ]]; then
    weighted_vote_value="true"
    ok_to_execute_value="true"
  fi
fi

if [[ "${baseline_trio_gate}" != "pass" && "${baseline_trio_gate}" != "recovery-pass" ]]; then
  if attempt_recovery_matrix "baseline=${baseline_trio_gate}/${baseline_trio_reason},ok_to_execute=${ok_to_execute_value}"; then
    exit 0
  fi
  council_failure_stage="council"
  council_failure_reason="baseline=${baseline_trio_gate}/${baseline_trio_reason},ok_to_execute=${ok_to_execute_value}"
  write_council_status_snapshot
  emit_council_step_outputs
  echo "Kernel council ${stage} failed: baseline=${baseline_trio_gate}/${baseline_trio_reason}, ok_to_execute=${ok_to_execute_value}" >&2
  exit 1
fi

if [[ "${ok_to_execute_value}" != "true" ]]; then
  council_failure_stage="council"
  council_failure_reason="weighted-vote=${weighted_vote_value};baseline=${baseline_trio_gate}/${baseline_trio_reason}"
  write_council_status_snapshot
  emit_council_step_outputs
  echo "Kernel council ${stage} rejected: weighted_vote=${weighted_vote_value}, baseline=${baseline_trio_gate}/${baseline_trio_reason}" >&2
  exit 1
fi

write_council_status_snapshot
emit_council_step_outputs
