#!/usr/bin/env bash
set -euo pipefail

# resolve-orchestration-context.sh — Resolve issue context for Tutti orchestration.
#
# Reads issue from GitHub API, extracts provider hints from labels/body/NL,
# runs translation gateway, applies orchestrator policy, and writes outputs
# to GITHUB_OUTPUT.
#
# Required env vars: GH_TOKEN, ISSUE_NUMBER_FROM_DISPATCH, ISSUE_NUMBER_FROM_ISSUE,
#   OPENAI_API_KEY, ANTHROPIC_API_KEY, DEFAULT_MAIN_ORCHESTRATOR_PROVIDER,
#   DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER, CLAUDE_RATE_LIMIT_STATE, and many more
#   (see env: block in fugue-tutti-caller.yml ctx step).
#
# Usage: bash scripts/harness/resolve-orchestration-context.sh

gh_api_retry() {
  local endpoint="$1"
  local attempts="${2:-5}"
  local sleep_sec=2
  local i out
  for ((i=1; i<=attempts; i++)); do
    if out="$(gh api "${endpoint}" 2>/dev/null)"; then
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

ISSUE_NUMBER=""
if [[ "${GITHUB_EVENT_NAME}" == "workflow_dispatch" ]]; then
  ISSUE_NUMBER="${ISSUE_NUMBER_FROM_DISPATCH}"
else
  ISSUE_NUMBER="${ISSUE_NUMBER_FROM_ISSUE}"
fi

issue_endpoint="repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}"
if ! issue_json="$(gh_api_retry "${issue_endpoint}" 5)"; then
  echo "Failed to fetch issue context after retries: ${issue_endpoint}" >&2
  exit 1
fi
title="$(echo "${issue_json}" | jq -r '.title // ""')"
body="$(echo "${issue_json}" | jq -r '.body // ""')"
trust_subject="$(printf '%s' "${TRUST_SUBJECT_INPUT:-}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -n "${trust_subject}" ]]; then
  trust_subject="$(printf '%s' "${trust_subject}" | sed -E 's/[^A-Za-z0-9_.-]//g')"
fi
allow_processing_rerun="$(echo "${ALLOW_PROCESSING_RERUN_INPUT:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${allow_processing_rerun}" != "true" ]]; then
  allow_processing_rerun="false"
fi
vote_instruction=""
vote_instruction_b64="$(echo "${VOTE_INSTRUCTION_B64_INPUT:-}" | tr -d '\n\r[:space:]')"
if [[ -n "${vote_instruction_b64}" ]]; then
  vote_instruction="$(printf '%s' "${vote_instruction_b64}" | base64 --decode 2>/dev/null || true)"
  vote_instruction="$(printf '%s' "${vote_instruction}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
fi
owner="${GITHUB_REPOSITORY%%/*}"

has_fugue="$(echo "${issue_json}" | jq -r '[.labels[]? | .name] | index("fugue-task") != null')"
has_tutti="$(echo "${issue_json}" | jq -r '[.labels[]? | .name] | index("tutti") != null')"
has_implement="$(echo "${issue_json}" | jq -r '[.labels[]? | .name] | (index("implement") != null) or (index("codex-implement") != null) or (index("claude-implement") != null)')"
has_implement_confirmed="$(echo "${issue_json}" | jq -r '[.labels[]? | .name] | (index("implement-confirmed") != null)')"
ci_execution_engine="$(echo "${CI_EXECUTION_ENGINE:-subscription}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${ci_execution_engine}" != "harness" && "${ci_execution_engine}" != "api" && "${ci_execution_engine}" != "subscription" ]]; then
  ci_execution_engine="subscription"
fi
subscription_offline_policy="$(echo "${SUBSCRIPTION_OFFLINE_POLICY:-continuity}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${subscription_offline_policy}" != "hold" && "${subscription_offline_policy}" != "continuity" ]]; then
  subscription_offline_policy="continuity"
fi
subscription_offline_policy_override="$(echo "${SUBSCRIPTION_OFFLINE_POLICY_OVERRIDE_INPUT:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${subscription_offline_policy_override}" == "hold" || "${subscription_offline_policy_override}" == "continuity" ]]; then
  subscription_offline_policy="${subscription_offline_policy_override}"
fi
emergency_continuity_mode="$(echo "${EMERGENCY_CONTINUITY_MODE:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${emergency_continuity_mode}" != "true" ]]; then
  emergency_continuity_mode="false"
fi
subscription_runner_label="$(echo "${SUBSCRIPTION_RUNNER_LABEL:-fugue-subscription}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -z "${subscription_runner_label}" ]]; then
  subscription_runner_label="fugue-subscription"
fi
self_hosted_online_count="0"
if [[ "${ci_execution_engine}" == "subscription" ]]; then
  runners_endpoint="repos/${GITHUB_REPOSITORY}/actions/runners?per_page=100"
  runners_json="$(gh_api_retry "${runners_endpoint}" 5 || echo '{}')"
  self_hosted_online_count="$(echo "${runners_json}" | jq -r --arg label "${subscription_runner_label}" '[.runners[]? | select(.status=="online" and .busy != true and ([.labels[]?.name] | index("self-hosted") != null) and ([.labels[]?.name] | index($label) != null))] | length' 2>/dev/null || echo "0")"
  self_hosted_online_count="$(echo "${self_hosted_online_count}" | tr -cd '0-9')"
  if [[ -z "${self_hosted_online_count}" ]]; then
    self_hosted_online_count="0"
  else
    self_hosted_online_count="$((10#${self_hosted_online_count}))"
  fi
fi
labels_csv="$(echo "${issue_json}" | jq -r '[.labels[]? | .name] | join(",")')"
body_mode="$(printf '%s\n' "${body}" | awk '
  BEGIN { in_sec=0 }
  tolower($0) ~ /^##[[:space:]]*mode[[:space:]]*$/ { in_sec=1; next }
  in_sec && $0 ~ /^##[[:space:]]/ { exit }
  in_sec {
    line=$0
    gsub(/`/, "", line)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (line != "") {
      print tolower(line)
      exit
    }
  }
')"
if [[ "${body_mode}" != "implement" && "${body_mode}" != "review" ]]; then
  body_mode="$(printf '%s\n' "${body}" | awk '
    BEGIN { in_sec=0 }
    tolower($0) ~ /^###[[:space:]]*execution[[:space:]]+mode[[:space:]]*$/ { in_sec=1; next }
    in_sec && $0 ~ /^###[[:space:]]/ { exit }
    in_sec {
      line=$0
      gsub(/`/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "") {
        print tolower(line)
        exit
      }
    }
  ')"
fi
if [[ "${body_mode}" != "implement" && "${body_mode}" != "review" ]]; then
  body_mode="$(echo "${body}" | sed -nE 's/^[[:space:]]*mode[[:space:]]*:[[:space:]]*(implement|review)[[:space:]]*$/\1/ip' | head -n1 | tr '[:upper:]' '[:lower:]')"
fi
# Explicit review mode in issue body always wins over stale labels.
if [[ "${body_mode}" == "review" ]]; then
  has_implement="false"
  has_implement_confirmed="false"
fi
label_main_provider="$(echo "${issue_json}" | jq -r '
  [ .labels[]? | .name ] as $labels
  | if ((($labels | index("orchestrator:claude")) != null) and (($labels | index("orchestrator:codex")) != null)) then ""
    elif (($labels | index("orchestrator:claude")) != null) then "claude"
    elif (($labels | index("orchestrator:codex")) != null) then "codex"
    else "" end
')"
label_assist_provider="$(echo "${issue_json}" | jq -r '
  [ .labels[]? | .name ] as $labels
  | if (($labels | index("orchestrator-assist:none")) != null) then "none"
    elif ((($labels | index("orchestrator-assist:claude")) != null) and (($labels | index("orchestrator-assist:codex")) != null)) then ""
    elif (($labels | index("orchestrator-assist:claude")) != null) then "claude"
    elif (($labels | index("orchestrator-assist:codex")) != null) then "codex"
    else "" end
')"
force_claude="$(echo "${issue_json}" | jq -r '
  [ .labels[]? | .name ] | index("orchestrator-force:claude") != null
')"
body_main_provider="$(printf '%s\n' "${body}" | awk '
  BEGIN { in_sec=0 }
  tolower($0) ~ /^##[[:space:]]*orchestrator[[:space:]]+provider[[:space:]]*$/ { in_sec=1; next }
  in_sec && $0 ~ /^##[[:space:]]/ { exit }
  in_sec {
    line=$0
    gsub(/`/, "", line)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (line != "") {
      print tolower(line)
      exit
    }
  }
')"
if [[ -z "${body_main_provider}" ]]; then
  body_main_provider="$(printf '%s\n' "${body}" | awk '
    BEGIN { in_sec=0 }
    tolower($0) ~ /^###[[:space:]]*main[[:space:]]+orchestrator[[:space:]]+provider[[:space:]]*$/ { in_sec=1; next }
    in_sec && $0 ~ /^###[[:space:]]/ { exit }
    in_sec {
      line=$0
      gsub(/`/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "") {
        print tolower(line)
        exit
      }
    }
  ')"
fi
if [[ "${body_main_provider}" != "claude" && "${body_main_provider}" != "codex" ]]; then
  body_main_provider=""
fi
if [[ -z "${body_main_provider}" ]]; then
  body_main_provider="$(echo "${body}" | sed -nE 's/^[[:space:]]*orchestrator[[:space:]_-]*provider[[:space:]]*:[[:space:]]*(claude|codex)[[:space:]]*$/\1/ip' | head -n1 | tr '[:upper:]' '[:lower:]')"
fi

body_assist_provider="$(printf '%s\n' "${body}" | awk '
  BEGIN { in_sec=0 }
  tolower($0) ~ /^##[[:space:]]*assist[[:space:]]+orchestrator[[:space:]]+provider[[:space:]]*$/ { in_sec=1; next }
  in_sec && $0 ~ /^##[[:space:]]/ { exit }
  in_sec {
    line=$0
    gsub(/`/, "", line)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    if (line != "") {
      print tolower(line)
      exit
    }
  }
')"
if [[ -z "${body_assist_provider}" ]]; then
  body_assist_provider="$(printf '%s\n' "${body}" | awk '
    BEGIN { in_sec=0 }
    tolower($0) ~ /^###[[:space:]]*assist[[:space:]]+orchestrator[[:space:]]+provider[[:space:]]*$/ { in_sec=1; next }
    in_sec && $0 ~ /^###[[:space:]]/ { exit }
    in_sec {
      line=$0
      gsub(/`/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "") {
        print tolower(line)
        exit
      }
    }
  ')"
fi
if [[ "${body_assist_provider}" != "claude" && "${body_assist_provider}" != "codex" && "${body_assist_provider}" != "none" ]]; then
  body_assist_provider=""
fi
if [[ -z "${body_assist_provider}" ]]; then
  body_assist_provider="$(echo "${body}" | sed -nE 's/^[[:space:]]*assist[[:space:]]+orchestrator[[:space:]_-]*provider[[:space:]]*:[[:space:]]*(claude|codex|none)[[:space:]]*$/\1/ip' | head -n1 | tr '[:upper:]' '[:lower:]')"
fi

eval "$(
  scripts/lib/orchestrator-nl-hints.sh \
    --title "${title}" \
    --body "${body}"
)"

requested_main_provider="${label_main_provider}"
main_provider_source="label"
if [[ -z "${requested_main_provider}" && -n "${body_main_provider}" ]]; then
  requested_main_provider="${body_main_provider}"
  main_provider_source="body-structured"
fi
if [[ -z "${requested_main_provider}" && -n "${nl_main_hint}" ]]; then
  requested_main_provider="${nl_main_hint}"
  main_provider_source="body-natural-language"
fi
if [[ -z "${requested_main_provider}" ]]; then
  requested_main_provider="${DEFAULT_MAIN_ORCHESTRATOR_PROVIDER:-codex}"
  main_provider_source="default"
fi
requested_main_provider="$(echo "${requested_main_provider}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${requested_main_provider}" != "claude" && "${requested_main_provider}" != "codex" ]]; then
  requested_main_provider="codex"
  main_provider_source="default"
fi
requested_main_provider_initial="${requested_main_provider}"
orchestration_profile="codex-full"
if [[ "${requested_main_provider_initial}" == "claude" && "${force_claude}" != "true" ]]; then
  orchestration_profile="claude-light"
fi
multi_agent_mode_override="$(echo "${DEFAULT_MULTI_AGENT_MODE:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${multi_agent_mode_override}" != "standard" && "${multi_agent_mode_override}" != "enhanced" && "${multi_agent_mode_override}" != "max" ]]; then
  multi_agent_mode_override=""
fi
multi_agent_mode_lock="$(echo "${DEFAULT_MULTI_AGENT_MODE_LOCK:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${multi_agent_mode_lock}" != "true" ]]; then
  multi_agent_mode_lock="false"
fi
# Early Hybrid Conductor Mode detection for multi-agent restriction check.
# Full computation happens later (line ~733); this is a safe forward-read.
_exec_prov_early="$(echo "${EXECUTION_PROVIDER_DEFAULT:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
hybrid_conductor_mode="false"
if [[ "${_exec_prov_early}" == "codex" || "${_exec_prov_early}" == "claude" ]]; then
  if [[ "${requested_main_provider}" != "${_exec_prov_early}" ]]; then
    hybrid_conductor_mode="true"
  fi
fi
# Apply claude-light multi-agent restrictions only when NOT in Hybrid Conductor Mode.
# In Hybrid, Claude is main but execution is Codex — full multi-agent depth is desired.
if [[ "${orchestration_profile}" == "claude-light" && "${hybrid_conductor_mode}" != "true" ]]; then
  if [[ -z "${multi_agent_mode_override}" ]]; then
    multi_agent_mode_override="$(echo "${CLAUDE_LIGHT_MULTI_AGENT_MODE:-standard}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    if [[ "${multi_agent_mode_override}" != "standard" && "${multi_agent_mode_override}" != "enhanced" && "${multi_agent_mode_override}" != "max" ]]; then
      multi_agent_mode_override="standard"
    fi
  fi
  if [[ "${multi_agent_mode_lock}" != "true" ]]; then
    multi_agent_mode_lock="$(echo "${CLAUDE_LIGHT_MULTI_AGENT_LOCK:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    if [[ "${multi_agent_mode_lock}" != "true" ]]; then
      multi_agent_mode_lock="false"
    fi
  fi
fi

requested_assist_provider="${label_assist_provider}"
assist_provider_source="label"
if [[ -z "${requested_assist_provider}" && -n "${body_assist_provider}" ]]; then
  requested_assist_provider="${body_assist_provider}"
  assist_provider_source="body-structured"
fi
if [[ -z "${requested_assist_provider}" && -n "${nl_assist_hint}" ]]; then
  requested_assist_provider="${nl_assist_hint}"
  assist_provider_source="body-natural-language"
fi
assist_explicit="false"
if [[ -n "${label_assist_provider}" || -n "${body_assist_provider}" || -n "${nl_assist_hint}" ]]; then
  assist_explicit="true"
fi
if [[ -z "${requested_assist_provider}" ]]; then
  requested_assist_provider="${DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER:-claude}"
  assist_provider_source="default"
fi
requested_assist_provider="$(echo "${requested_assist_provider}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${requested_assist_provider}" != "claude" && "${requested_assist_provider}" != "codex" && "${requested_assist_provider}" != "none" ]]; then
  requested_assist_provider="${DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER:-claude}"
  assist_provider_source="default"
fi

claude_state="$(echo "${CLAUDE_RATE_LIMIT_STATE:-ok}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_state}" != "ok" && "${claude_state}" != "degraded" && "${claude_state}" != "exhausted" ]]; then
  claude_state="ok"
fi

# Translation gateway:
# Codex judges whether Claude translation is needed between human input and Codex orchestration.
translator_mode="$(echo "${CLAUDE_TRANSLATOR_MODE:-auto}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${translator_mode}" != "auto" && "${translator_mode}" != "always" && "${translator_mode}" != "off" ]]; then
  translator_mode="auto"
fi
claude_max_plan="$(echo "${CLAUDE_MAX_PLAN:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_max_plan}" != "true" ]]; then
  claude_max_plan="false"
fi
threshold_raw="$(echo "${CLAUDE_TRANSLATOR_THRESHOLD:-75}" | tr -cd '0-9')"
if [[ -z "${threshold_raw}" ]]; then
  threshold_raw="75"
fi
threshold_degraded_raw="$(echo "${CLAUDE_TRANSLATOR_THRESHOLD_DEGRADED:-88}" | tr -cd '0-9')"
if [[ -z "${threshold_degraded_raw}" ]]; then
  threshold_degraded_raw="88"
fi
if [[ "${orchestration_profile}" == "claude-light" ]]; then
  light_threshold_raw="$(echo "${CLAUDE_TRANSLATOR_THRESHOLD_CLAUDE_LIGHT:-90}" | tr -cd '0-9')"
  if [[ -z "${light_threshold_raw}" ]]; then
    light_threshold_raw="90"
  fi
  light_threshold_degraded_raw="$(echo "${CLAUDE_TRANSLATOR_THRESHOLD_DEGRADED_CLAUDE_LIGHT:-95}" | tr -cd '0-9')"
  if [[ -z "${light_threshold_degraded_raw}" ]]; then
    light_threshold_degraded_raw="95"
  fi
  if (( threshold_raw < light_threshold_raw )); then
    threshold_raw="${light_threshold_raw}"
  fi
  if (( threshold_degraded_raw < light_threshold_degraded_raw )); then
    threshold_degraded_raw="${light_threshold_degraded_raw}"
  fi
fi
max_chars_raw="$(echo "${CLAUDE_TRANSLATOR_MAX_CHARS:-6000}" | tr -cd '0-9')"
if [[ -z "${max_chars_raw}" ]]; then
  max_chars_raw="6000"
fi
translation_threshold="${threshold_raw}"
if [[ "${claude_state}" == "degraded" ]]; then
  translation_threshold="${threshold_degraded_raw}"
fi
translation_gate_decision="false"
translation_applied="false"
translation_provider="none"
translation_judge_provider="codex"
translation_score="0"
translation_reason="translation-not-required"
translation_skip_reason=""
translation_event="false"
translation_payload=""
normalized_text="$(printf '%s\n\n%s\n' "${title}" "${body}" | head -c "${max_chars_raw}")"
CODEX_MAIN_MODEL="gpt-5-codex"
if ! [[ "${CODEX_MULTI_AGENT_MODEL}" =~ ^gpt-5(\.[0-9]+)?-codex-spark$ ]]; then
  CODEX_MULTI_AGENT_MODEL="gpt-5.3-codex-spark"
fi
if [[ "${CLAUDE_TRANSLATOR_MODEL}" != "claude-sonnet-4-6" ]]; then
  CLAUDE_TRANSLATOR_MODEL="claude-sonnet-4-6"
fi

if [[ "${translator_mode}" != "off" && -n "${OPENAI_API_KEY:-}" ]]; then
  judge_sys_prompt="You are Codex Orchestrator gate. Decide if Claude translation should be inserted before orchestration. Return ONLY compact JSON: {\"score\":0-100,\"should_translate\":true|false,\"reason\":\"short\",\"signals\":[\"...\"]}."
  judge_user_prompt="Analyze this issue text for ambiguity/conflict/risk/implicit constraints. Prioritize translation when requirements are unclear, mixed-language, or high-risk refactor/migration. Text:\n${normalized_text}"
  judge_candidates=("${CODEX_MULTI_AGENT_MODEL}" "${CODEX_MAIN_MODEL}" "gpt-5-codex")
  judge_json=""
  for judge_model in "${judge_candidates[@]}"; do
    judge_req="$(jq -n \
      --arg model "${judge_model}" \
      --arg s "${judge_sys_prompt}" \
      --arg u "${judge_user_prompt}" \
      '{model:$model,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.0}')"
    judge_http="$(curl -sS -o /tmp/fugue-judge-response.json -w "%{http_code}" https://api.openai.com/v1/chat/completions \
      --connect-timeout 10 --max-time 60 --retry 2 \
      -H "Authorization: Bearer ${OPENAI_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "${judge_req}" || true)"
    if [[ "${judge_http}" == "200" ]]; then
      judge_content="$(jq -r '.choices[0].message.content // ""' /tmp/fugue-judge-response.json 2>/dev/null || echo "")"
      judge_json="$(printf '%s' "${judge_content}" | sed -E 's/^```json[[:space:]]*//; s/^```[[:space:]]*//; s/[[:space:]]*```$//')"
      if printf '%s' "${judge_json}" | jq -e . >/dev/null 2>&1; then
        break
      fi
    fi
    judge_json=""
  done
  if [[ -n "${judge_json}" ]]; then
    translation_score="$(printf '%s' "${judge_json}" | jq -r '.score // 0' | tr -cd '0-9')"
    if [[ -z "${translation_score}" ]]; then
      translation_score="0"
    fi
    judge_decision="$(printf '%s' "${judge_json}" | jq -r '.should_translate // false')"
    if [[ "${judge_decision}" == "true" || "${translator_mode}" == "always" || "${translation_score}" -ge "${translation_threshold}" ]]; then
      translation_gate_decision="true"
    fi
    translation_reason="$(printf '%s' "${judge_json}" | jq -r '.reason // "codex-judge"' | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
  else
    # Heuristic fallback when Codex judge response is unavailable.
    translation_score=30
    if [[ "${#normalized_text}" -gt 1600 ]]; then translation_score=$((translation_score + 20)); fi
    if echo "${normalized_text}" | grep -Eqi '(大規模|全面|全体|リファクタ|refactor|migration|rewrite|アーキテクチャ刷新)'; then translation_score=$((translation_score + 25)); fi
    if echo "${normalized_text}" | grep -Eqi '(いい感じ|任せ|よろしく|適宜|うまく|なんとか|ざっくり|とりあえず|as needed|best effort)'; then translation_score=$((translation_score + 20)); fi
    if echo "${normalized_text}" | grep -Eqi '(must not|制約|禁止|rollback|ロールバック|受け入れ|acceptance)'; then translation_score=$((translation_score + 10)); fi
    if (( translation_score > 100 )); then translation_score=100; fi
    translation_reason="codex-judge-fallback-heuristic"
    if [[ "${translator_mode}" == "always" || "${translation_score}" -ge "${translation_threshold}" ]]; then
      translation_gate_decision="true"
    fi
  fi
fi
if [[ "${translator_mode}" == "always" ]]; then
  translation_gate_decision="true"
elif [[ "${translator_mode}" == "off" ]]; then
  translation_gate_decision="false"
  translation_reason="translator-mode-off"
fi

if [[ "${translation_gate_decision}" == "true" ]]; then
  if [[ "${claude_state}" == "exhausted" && "${force_claude}" != "true" ]]; then
    translation_skip_reason="claude-rate-limit-exhausted"
  else
    translator_sys_prompt="You are a requirements translator between human request and Codex orchestrator. Preserve intent. Return ONLY compact JSON with keys: task_summary, goal, constraints(array), acceptance_criteria(array), risks(array), open_questions(array), execution_mode_hint(review|implement|unspecified)."
    translator_user_prompt="Translate and structure this issue for precise execution:\n${normalized_text}"
    translation_resp_json=""
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
      translation_provider="claude"
      claude_req="$(jq -n \
        --arg model "${CLAUDE_TRANSLATOR_MODEL}" \
        --arg s "${translator_sys_prompt}" \
        --arg u "${translator_user_prompt}" \
        '{model:$model,system:$s,messages:[{role:"user",content:$u}],max_tokens:1400,temperature:0.1}')"
      claude_http="$(curl -sS -o /tmp/fugue-translation-response.json -w "%{http_code}" https://api.anthropic.com/v1/messages \
        --connect-timeout 10 --max-time 60 --retry 2 \
        -H "x-api-key: ${ANTHROPIC_API_KEY}" \
        -H "anthropic-version: 2023-06-01" \
        -H "Content-Type: application/json" \
        -d "${claude_req}" || true)"
      if [[ "${claude_http}" == "200" ]]; then
        translation_resp_json="$(jq -r '[.content[]? | select(.type=="text") | .text] | join("\n") // ""' /tmp/fugue-translation-response.json 2>/dev/null || echo "")"
      fi
    elif [[ "${claude_max_plan}" == "true" && -n "${OPENAI_API_KEY:-}" ]]; then
      translation_provider="claude-max-proxy-codex"
      proxy_candidates=("${CODEX_MULTI_AGENT_MODEL}" "${CODEX_MAIN_MODEL}" "gpt-5-codex")
      for proxy_model in "${proxy_candidates[@]}"; do
        proxy_req="$(jq -n \
          --arg model "${proxy_model}" \
          --arg s "${translator_sys_prompt}" \
          --arg u "${translator_user_prompt}" \
          '{model:$model,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"
        proxy_http="$(curl -sS -o /tmp/fugue-translation-response.json -w "%{http_code}" https://api.openai.com/v1/chat/completions \
          --connect-timeout 10 --max-time 60 --retry 2 \
          -H "Authorization: Bearer ${OPENAI_API_KEY}" \
          -H "Content-Type: application/json" \
          -d "${proxy_req}" || true)"
        if [[ "${proxy_http}" == "200" ]]; then
          translation_resp_json="$(jq -r '.choices[0].message.content // ""' /tmp/fugue-translation-response.json 2>/dev/null || echo "")"
          if [[ -n "${translation_resp_json}" ]]; then
            break
          fi
        fi
      done
    else
      translation_skip_reason="missing-claude-translation-credentials"
    fi

    if [[ -n "${translation_resp_json}" ]]; then
      translation_payload="$(printf '%s' "${translation_resp_json}" | sed -E 's/^```json[[:space:]]*//; s/^```[[:space:]]*//; s/[[:space:]]*```$//')"
      if ! printf '%s' "${translation_payload}" | jq -e . >/dev/null 2>&1; then
        translation_payload=""
        translation_skip_reason="translator-invalid-json"
      fi
    fi
  fi
fi

if [[ "${translation_gate_decision}" == "true" && -n "${translation_payload}" ]]; then
  task_summary="$(printf '%s' "${translation_payload}" | jq -r '.task_summary // ""')"
  translated_goal="$(printf '%s' "${translation_payload}" | jq -r '.goal // ""')"
  exec_mode_hint="$(printf '%s' "${translation_payload}" | jq -r '.execution_mode_hint // "unspecified"')"
  constraints_md="$(printf '%s' "${translation_payload}" | jq -r '(.constraints // []) | if length==0 then "- none" else map("- " + .) | join("\n") end')"
  acceptance_md="$(printf '%s' "${translation_payload}" | jq -r '(.acceptance_criteria // []) | if length==0 then "- none" else map("- " + .) | join("\n") end')"
  risks_md="$(printf '%s' "${translation_payload}" | jq -r '(.risks // []) | if length==0 then "- none" else map("- " + .) | join("\n") end')"
  questions_md="$(printf '%s' "${translation_payload}" | jq -r '(.open_questions // []) | if length==0 then "- none" else map("- " + .) | join("\n") end')"
  ts_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  marker_start="<!-- fugue-translation-gateway:start -->"
  marker_end="<!-- fugue-translation-gateway:end -->"
  old_body_file="$(mktemp)"
  new_body_file="$(mktemp)"
  block_file="$(mktemp)"
  printf '%s\n' "${body}" > "${old_body_file}"
  {
    echo "${marker_start}"
    echo "## FUGUE Translation Gateway"
    echo "- mode: ${translator_mode}"
    echo "- judge: ${translation_judge_provider}"
    echo "- decision: ${translation_gate_decision}"
    echo "- score: ${translation_score} (threshold=${translation_threshold})"
    echo "- reason: ${translation_reason}"
    echo "- translator: ${translation_provider}"
    echo "- timestamp_utc: ${ts_utc}"
    echo
    echo "### Task Summary"
    echo "${task_summary}"
    echo
    echo "### Goal"
    echo "${translated_goal}"
    echo
    echo "### Constraints"
    echo "${constraints_md}"
    echo
    echo "### Acceptance Criteria"
    echo "${acceptance_md}"
    echo
    echo "### Risk Notes"
    echo "${risks_md}"
    echo
    echo "### Open Questions"
    echo "${questions_md}"
    echo
    echo "### Routing Hint"
    echo "- execution_mode_hint: ${exec_mode_hint}"
    echo "${marker_end}"
  } > "${block_file}"
  awk -v start="${marker_start}" -v end="${marker_end}" '
    $0 == start {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "${old_body_file}" > "${new_body_file}"
  printf '\n\n' >> "${new_body_file}"
  cat "${block_file}" >> "${new_body_file}"
  new_body="$(cat "${new_body_file}")"
  if [[ "${new_body}" != "${body}" ]]; then
    payload_file="$(mktemp)"
    jq -n --arg b "${new_body}" '{body:$b}' > "${payload_file}"
    gh api "repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}" \
      --method PATCH \
      --input "${payload_file}" >/dev/null
    body="${new_body}"
  fi
  translation_applied="true"
  translation_event="true"
elif [[ "${translation_gate_decision}" == "true" ]]; then
  if [[ -z "${translation_skip_reason}" ]]; then
    translation_skip_reason="translator-no-output"
  fi
  translation_event="true"
fi

eval "$(
  scripts/lib/orchestrator-policy.sh \
    --main "${requested_main_provider_initial}" \
    --assist "${requested_assist_provider}" \
    --default-main "${DEFAULT_MAIN_ORCHESTRATOR_PROVIDER}" \
    --default-assist "${DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER}" \
    --claude-state "${claude_state}" \
    --force-claude "${force_claude}" \
    --assist-policy "${CLAUDE_MAIN_ASSIST_POLICY}" \
    --claude-role-policy "${CLAUDE_ROLE_POLICY}" \
    --degraded-assist-policy "${CLAUDE_DEGRADED_ASSIST_POLICY}"
)"
requested_main_provider="${resolved_main}"
requested_assist_provider="${resolved_assist}"
main_claude_fallback_applied="${main_fallback_applied}"
main_claude_fallback_reason="${main_fallback_reason}"
assist_claude_fallback_applied="${assist_fallback_applied}"
assist_claude_fallback_reason="${assist_fallback_reason}"
claude_pressure_guard_applied="${pressure_guard_applied}"
claude_pressure_guard_reason="${pressure_guard_reason}"
# Profile should follow the resolved main provider, not just initial request.
orchestration_profile="codex-full"
if [[ "${requested_main_provider}" == "claude" ]]; then
  orchestration_profile="claude-light"
fi

# Hybrid Conductor Mode: execution provider can differ from main orchestrator.
execution_provider="$(echo "${EXECUTION_PROVIDER_DEFAULT:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${execution_provider}" != "codex" && "${execution_provider}" != "claude" ]]; then
  execution_provider="${requested_main_provider}"
fi
hybrid_conductor_mode="false"
if [[ "${requested_main_provider}" != "${execution_provider}" ]]; then
  hybrid_conductor_mode="true"
fi
# Guard: only main=claude + execution=codex is a valid Hybrid combination.
if [[ "${hybrid_conductor_mode}" == "true" && "${requested_main_provider}" != "claude" ]]; then
  echo "Warning: reverse Hybrid (main=${requested_main_provider}, execution=${execution_provider}) is unsupported; falling back to non-Hybrid." >&2
  execution_provider="${requested_main_provider}"
  hybrid_conductor_mode="false"
fi
# Execution profile determines implementation parameters (codex-full or claude-light).
execution_profile="codex-full"
if [[ "${execution_provider}" == "claude" ]]; then
  execution_profile="claude-light"
fi

implementation_dialogue_rounds_raw="${IMPLEMENT_DIALOGUE_ROUNDS_DEFAULT:-2}"
if [[ "${execution_profile}" == "claude-light" ]]; then
  implementation_dialogue_rounds_raw="${IMPLEMENT_DIALOGUE_ROUNDS_CLAUDE:-1}"
fi
implementation_dialogue_rounds="$(echo "${implementation_dialogue_rounds_raw}" | tr -cd '0-9')"
if [[ -z "${implementation_dialogue_rounds}" ]]; then
  implementation_dialogue_rounds="2"
fi
if (( implementation_dialogue_rounds < 1 )); then
  implementation_dialogue_rounds=1
elif (( implementation_dialogue_rounds > 5 )); then
  implementation_dialogue_rounds=5
fi

preflight_cycles_raw="${IMPLEMENT_PREFLIGHT_CYCLES_FULL:-2}"
if [[ "${execution_profile}" == "claude-light" ]]; then
  preflight_cycles_raw="${IMPLEMENT_PREFLIGHT_CYCLES_CLAUDE:-1}"
fi
preflight_cycles="$(echo "${preflight_cycles_raw}" | tr -cd '0-9')"
if [[ -z "${preflight_cycles}" ]]; then
  preflight_cycles="2"
fi
if [[ "${execution_profile}" == "claude-light" ]]; then
  if (( preflight_cycles < 1 )); then
    preflight_cycles=1
  elif (( preflight_cycles > 3 )); then
    preflight_cycles=3
  fi
else
  if (( preflight_cycles < 2 )); then
    preflight_cycles=2
  elif (( preflight_cycles > 5 )); then
    preflight_cycles=5
  fi
fi

eval "$(
  scripts/lib/workflow-risk-policy.sh \
    --title "${title}" \
    --body "${body}" \
    --labels "${labels_csv}" \
    --has-implement "${has_implement}" \
    --orchestration-profile "${orchestration_profile}"
)"

if (( preflight_cycles < preflight_cycles_floor )); then
  preflight_cycles="${preflight_cycles_floor}"
fi
if (( implementation_dialogue_rounds < implementation_dialogue_rounds_floor )); then
  implementation_dialogue_rounds="${implementation_dialogue_rounds_floor}"
fi
assist_auto_selected="explicit-or-default"
sub_auto_escalate="$(echo "${CLAUDE_SUB_AUTO_ESCALATE:-high}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${sub_auto_escalate}" != "off" && "${sub_auto_escalate}" != "high" && "${sub_auto_escalate}" != "medium-high" ]]; then
  sub_auto_escalate="high"
fi
claude_sub_trigger="none"
auto_attach_claude="false"
ambiguity_score_min="$(echo "${CLAUDE_SUB_AMBIGUITY_MIN_SCORE:-90}" | tr -cd '0-9')"
if [[ -z "${ambiguity_score_min}" ]]; then
  ambiguity_score_min="90"
fi
if (( ambiguity_score_min < 0 )); then
  ambiguity_score_min=0
elif (( ambiguity_score_min > 100 )); then
  ambiguity_score_min=100
fi
translation_score_num="$(echo "${translation_score}" | tr -cd '0-9')"
if [[ -z "${translation_score_num}" ]]; then
  translation_score_num=0
fi
# Secondary triggers to avoid "never-use-Claude" failure when risk heuristics miss.
if [[ "${risk_tier}" == "high" ]]; then
  auto_attach_claude="true"
  claude_sub_trigger="risk-high"
elif [[ "${correction_signal}" == "true" ]]; then
  auto_attach_claude="true"
  claude_sub_trigger="correction-signal"
elif [[ "${translation_gate_decision}" == "true" && "${translation_score_num}" -ge "${ambiguity_score_min}" ]]; then
  auto_attach_claude="true"
  claude_sub_trigger="ambiguity-translation-gate(${translation_score_num})"
fi
# Claude is a sub orchestrator under constrained MAX plans.
# Auto-attach only when risk warrants it and no explicit/default assist was requested.
if [[ "${assist_explicit}" != "true" && "${force_claude}" != "true" && "${requested_assist_provider}" == "none" ]]; then
  if [[ "${sub_auto_escalate}" == "off" ]]; then
    requested_assist_provider="none"
    assist_provider_source="risk-auto(off)"
    assist_auto_selected="off->none"
  elif [[ "${sub_auto_escalate}" == "medium-high" ]]; then
    if [[ "${risk_tier}" == "medium" || "${risk_tier}" == "high" || "${auto_attach_claude}" == "true" ]]; then
      requested_assist_provider="claude"
      assist_provider_source="risk-auto(medium-high)"
      assist_auto_selected="${risk_tier}->claude(${claude_sub_trigger})"
    else
      requested_assist_provider="none"
      assist_provider_source="risk-auto(medium-high)"
      assist_auto_selected="low->none"
    fi
  else
    if [[ "${auto_attach_claude}" == "true" ]]; then
      requested_assist_provider="claude"
      assist_provider_source="risk-auto(high)"
      assist_auto_selected="${risk_tier}->claude(${claude_sub_trigger})"
    else
      requested_assist_provider="none"
      assist_provider_source="risk-auto(high)"
      assist_auto_selected="${risk_tier}->none"
    fi
  fi
fi
eval "$(
  scripts/lib/orchestrator-policy.sh \
    --main "${requested_main_provider_initial}" \
    --assist "${requested_assist_provider}" \
    --default-main "${DEFAULT_MAIN_ORCHESTRATOR_PROVIDER}" \
    --default-assist "${DEFAULT_ASSIST_ORCHESTRATOR_PROVIDER}" \
    --claude-state "${claude_state}" \
    --force-claude "${force_claude}" \
    --assist-policy "${CLAUDE_MAIN_ASSIST_POLICY}" \
    --claude-role-policy "${CLAUDE_ROLE_POLICY}" \
    --degraded-assist-policy "${CLAUDE_DEGRADED_ASSIST_POLICY}"
)"
requested_main_provider="${resolved_main}"
requested_assist_provider="${resolved_assist}"
main_claude_fallback_applied="${main_fallback_applied}"
main_claude_fallback_reason="${main_fallback_reason}"
assist_claude_fallback_applied="${assist_fallback_applied}"
assist_claude_fallback_reason="${assist_fallback_reason}"
claude_pressure_guard_applied="${pressure_guard_applied}"
claude_pressure_guard_reason="${pressure_guard_reason}"
if [[ "${main_claude_fallback_applied}" == "true" && -n "${main_claude_fallback_reason}" ]]; then
  main_provider_source="${main_provider_source}+policy(${main_claude_fallback_reason})"
fi
if [[ "${assist_claude_fallback_applied}" == "true" && -n "${assist_claude_fallback_reason}" ]]; then
  assist_provider_source="${assist_provider_source}+policy(${assist_claude_fallback_reason})"
elif [[ "${claude_pressure_guard_applied}" == "true" && -n "${claude_pressure_guard_reason}" ]]; then
  assist_provider_source="${assist_provider_source}+policy(${claude_pressure_guard_reason})"
fi
# Keep low-risk tasks lightweight and high-risk tasks exhaustive when
# no explicit multi-agent override was provided.
if [[ -z "${multi_agent_mode_override}" && "${multi_agent_mode_lock}" != "true" ]]; then
  if [[ "${risk_tier}" == "low" ]]; then
    multi_agent_mode_override="standard"
  elif [[ "${risk_tier}" == "high" ]]; then
    multi_agent_mode_override="max"
  fi
fi

# 1) Prefer fully-qualified owner/repo found inside backticks.
target_repo="$(printf '%s\n' "${body}" \
  | sed -nE 's/.*`([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)`.*/\1/p' \
  | head -n1)"

# 1b) Also accept plain "owner/repo" (common on mobile forms).
if [[ -z "${target_repo}" ]]; then
  target_repo="$(printf '%s\n' "${body}" | grep -oE "${owner}/[A-Za-z0-9_.-]+" | head -n1 || true)"
fi

# 2) Fallback: repo name in backticks on lines mentioning repo/リポジトリ.
if [[ -z "${target_repo}" ]]; then
  bare_repo="$(printf '%s\n' "${body}" \
    | grep -E 'repo|Repo|repository|Repository|リポジトリ' \
    | sed -nE 's/.*`([A-Za-z0-9_.-]+)`.*/\1/p' \
    | head -n1 || true)"
  if [[ -n "${bare_repo}" ]]; then
    target_repo="${owner}/${bare_repo}"
  fi
fi

# 3) Default to caller repo when no hint exists.
if [[ -z "${target_repo}" ]]; then
  target_repo="${GITHUB_REPOSITORY}"
fi

should_run="true"
skip_reason=""
if [[ "${has_fugue}" != "true" || "${has_tutti}" != "true" ]]; then
  should_run="false"
  skip_reason="missing-required-labels"
elif [[ "${ci_execution_engine}" == "subscription" && "${subscription_offline_policy}" == "hold" && "${emergency_continuity_mode}" != "true" && "${self_hosted_online_count}" == "0" ]]; then
  should_run="false"
  skip_reason="subscription-self-hosted-offline-strict"
fi

{
  echo "issue_number=${ISSUE_NUMBER}"
  echo "has_implement_request=${has_implement}"
  echo "has_implement_confirmed=${has_implement_confirmed}"
  echo "self_hosted_online_count=${self_hosted_online_count}"
  echo "subscription_runner_label=${subscription_runner_label}"
  echo "subscription_offline_policy=${subscription_offline_policy}"
  echo "trust_subject=${trust_subject}"
  echo "target_repo=${target_repo}"
  echo "orchestrator_provider=${requested_main_provider}"
  echo "main_orchestrator_provider=${requested_main_provider}"
  echo "assist_orchestrator_provider=${requested_assist_provider}"
  echo "main_provider_source=${main_provider_source}"
  echo "assist_provider_source=${assist_provider_source}"
  echo "nl_hint_applied=${nl_hint_applied}"
  echo "nl_main_hint=${nl_main_hint}"
  echo "nl_assist_hint=${nl_assist_hint}"
  echo "nl_main_reason=${nl_main_reason}"
  echo "nl_assist_reason=${nl_assist_reason}"
  echo "nl_inference_skipped_reason=${nl_inference_skipped_reason}"
  echo "claude_fallback_applied=${main_claude_fallback_applied}"
  echo "claude_fallback_reason=${main_claude_fallback_reason}"
  echo "main_claude_fallback_applied=${main_claude_fallback_applied}"
  echo "main_claude_fallback_reason=${main_claude_fallback_reason}"
  echo "assist_claude_fallback_applied=${assist_claude_fallback_applied}"
  echo "assist_claude_fallback_reason=${assist_claude_fallback_reason}"
  echo "claude_pressure_guard_applied=${claude_pressure_guard_applied}"
  echo "claude_pressure_guard_reason=${claude_pressure_guard_reason}"
  echo "claude_role_policy=${claude_role_policy}"
  echo "claude_degraded_assist_policy=${degraded_assist_policy}"
  echo "translation_gate_decision=${translation_gate_decision}"
  echo "translation_applied=${translation_applied}"
  echo "translation_provider=${translation_provider}"
  echo "translation_score=${translation_score}"
  echo "translation_threshold=${translation_threshold}"
  echo "translation_reason=$(echo "${translation_reason}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')"
  echo "translation_skip_reason=${translation_skip_reason}"
  echo "translation_event=${translation_event}"
  echo "orchestration_profile=${orchestration_profile}"
  echo "preflight_cycles=${preflight_cycles}"
  echo "multi_agent_mode_override=${multi_agent_mode_override}"
  echo "multi_agent_mode_lock=${multi_agent_mode_lock}"
  echo "implementation_dialogue_rounds=${implementation_dialogue_rounds}"
  echo "risk_tier=${risk_tier}"
  echo "risk_score=${risk_score}"
  echo "risk_reasons=${risk_reasons}"
  echo "lessons_required=${lessons_required}"
  echo "correction_signal=${correction_signal}"
  echo "context_budget_initial=${context_budget_initial}"
  echo "context_budget_max=${context_budget_max}"
  echo "context_budget_floor_initial=${context_budget_floor_initial}"
  echo "context_budget_floor_max=${context_budget_floor_max}"
  echo "context_budget_floor_span=${context_budget_floor_span}"
  echo "context_budget_guard_applied=${context_budget_guard_applied}"
  echo "context_budget_guard_reasons=${context_budget_guard_reasons}"
  echo "assist_auto_selected=${assist_auto_selected}"
  echo "force_claude=${force_claude}"
  echo "execution_provider=${execution_provider}"
  echo "execution_profile=${execution_profile}"
  echo "hybrid_conductor_mode=${hybrid_conductor_mode}"
  echo "subscription_offline_policy=${subscription_offline_policy}"
  echo "trust_subject=${trust_subject}"
  echo "allow_processing_rerun=${allow_processing_rerun}"
  echo "vote_instruction<<EOF"
  echo "${vote_instruction}"
  echo "EOF"
  echo "should_run=${should_run}"
  echo "skip_reason=${skip_reason}"
} >> "${GITHUB_OUTPUT}"
