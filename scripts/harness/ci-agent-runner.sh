#!/usr/bin/env bash
set -euo pipefail

sys_prompt="You are ${AGENT_ROLE}. Analyze the GitHub issue and return ONLY valid JSON with keys: risk (LOW|MEDIUM|HIGH), approve (boolean), findings (array of strings), recommendation (string), rationale (string)."
user_prompt="Issue Title: ${ISSUE_TITLE}

Issue Body:
${ISSUE_BODY}"
if [[ "${AGENT_NAME:-}" == "claude-teams-executor" || "${AGENT_ROLE:-}" == "teams-executor" ]]; then
  sys_prompt="${sys_prompt} Claude Teams bounded mode is active; behave as a narrow collaboration executor and return handoff-ready JSON only."
fi

ORIGINAL_PROVIDER="${PROVIDER}"
ORIGINAL_MODEL="${MODEL}"
CLAUDE_PROXY_MODE="false"
CLAUDE_PROXY_NOTE=""
claude_max_plan="$(echo "${CLAUDE_MAX_PLAN:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_max_plan}" != "true" ]]; then
  claude_max_plan="false"
fi
claude_assist_execution_policy="$(echo "${CLAUDE_ASSIST_EXECUTION_POLICY:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_assist_execution_policy}" != "direct" && "${claude_assist_execution_policy}" != "hybrid" && "${claude_assist_execution_policy}" != "proxy" ]]; then
  claude_assist_execution_policy=""
fi
if [[ -z "${claude_assist_execution_policy}" ]]; then
  # Backward compatible default:
  # - max plan true  => hybrid (direct preferred, proxy on missing Anthropic key)
  # - max plan false => direct
  if [[ "${claude_max_plan}" == "true" ]]; then
    claude_assist_execution_policy="hybrid"
  else
    claude_assist_execution_policy="direct"
  fi
fi
strict_main_codex_model="$(echo "${STRICT_MAIN_CODEX_MODEL:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${strict_main_codex_model}" != "true" ]]; then
  strict_main_codex_model="false"
fi
strict_opus_assist_direct="$(echo "${STRICT_OPUS_ASSIST_DIRECT:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${strict_opus_assist_direct}" != "true" ]]; then
  strict_opus_assist_direct="false"
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
model_policy_script="${script_dir}/../lib/model-policy.sh"
recursive_policy_script="${script_dir}/../lib/codex-recursive-policy.sh"
raw_claude_model="$(echo "${CLAUDE_OPUS_MODEL:-claude-sonnet-4-6}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_codex_main_model="$(echo "${CODEX_MAIN_MODEL:-gpt-5.4}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_codex_multi_agent_model="$(echo "${CODEX_MULTI_AGENT_MODEL:-gpt-5.3-codex-spark}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_glm_model="$(echo "${GLM_MODEL:-${FUGUE_GLM_MODEL:-glm-4.7}}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_xai_model="$(echo "${XAI_MODEL_LATEST:-grok-4}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_gemini_fallback_model="$(echo "${GEMINI_FALLBACK_MODEL:-gemini-3-flash}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
# shellcheck source=../lib/safe-eval-policy.sh
source "${script_dir}/../lib/safe-eval-policy.sh"

# Curl timeout defaults (overridable via env).
FUGUE_CURL_CONNECT_TIMEOUT="${FUGUE_CURL_CONNECT_TIMEOUT:-10}"
FUGUE_CURL_MAX_TIME="${FUGUE_CURL_MAX_TIME:-60}"
FUGUE_CURL_RETRY="${FUGUE_CURL_RETRY:-2}"
FUGUE_CURL_RETRY_ALL="${FUGUE_CURL_RETRY_ALL:---retry-all-errors}"
if [[ -x "${model_policy_script}" ]]; then
  safe_eval_policy "${model_policy_script}" \
    --codex-main-model "${raw_codex_main_model}" \
    --codex-multi-agent-model "${raw_codex_multi_agent_model}" \
    --claude-model "${raw_claude_model}" \
    --glm-model "${raw_glm_model}" \
    --gemini-model "gemini-3.1-pro" \
    --gemini-fallback-model "${raw_gemini_fallback_model}" \
    --xai-model "${raw_xai_model}" \
    --format env
  claude_opus_model="${claude_api_model}"
  xai_latest_model="${xai_model}"
else
  claude_opus_model="claude-sonnet-4-0"
  codex_main_model="gpt-5.4"
  codex_multi_agent_model="gpt-5.3-codex-spark"
  glm_model="glm-4.7"
  xai_latest_model="grok-4"
  gemini_fallback_model="gemini-3-flash"
fi

normalize_optional_bool() {
  local raw="${1:-}"
  raw="$(echo "${raw}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ -z "${raw}" ]]; then
    return 1
  fi
  if [[ "${raw}" == "true" || "${raw}" == "1" || "${raw}" == "yes" || "${raw}" == "on" ]]; then
    printf 'true'
    return 0
  fi
  printf 'false'
  return 0
}

copilot_runner_bin="${COPILOT_CLI_BIN:-copilot}"
copilot_runner_token="${COPILOT_GITHUB_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"
copilot_runner_available="false"
copilot_cli_override="$(normalize_optional_bool "${HAS_COPILOT_CLI:-${FUGUE_HAS_COPILOT_CLI:-}}" || true)"
if [[ -n "${copilot_cli_override}" ]]; then
  copilot_runner_available="${copilot_cli_override}"
elif command -v "${copilot_runner_bin}" >/dev/null 2>&1; then
  copilot_runner_available="true"
fi
copilot_allow_all_tools="$(normalize_optional_bool "${COPILOT_ALLOW_ALL_TOOLS:-true}" || true)"
if [[ -z "${copilot_allow_all_tools}" ]]; then
  copilot_allow_all_tools="true"
fi

recursive_enabled_raw="${FUGUE_CODEX_RECURSIVE_DELEGATION:-false}"
recursive_depth_raw="${FUGUE_CODEX_RECURSIVE_MAX_DEPTH:-3}"
recursive_targets_raw="${FUGUE_CODEX_RECURSIVE_TARGET_LANES:-codex-main-orchestrator,codex-orchestration-assist}"
recursive_dry_run_raw="${FUGUE_CODEX_RECURSIVE_DRY_RUN:-false}"
recursive_enabled="false"
recursive_active="false"
recursive_reason="policy-script-missing"
recursive_lane_allowed="false"
recursive_target_lanes="${recursive_targets_raw}"
recursive_depth="3"
recursive_dry_run="false"
if [[ -x "${recursive_policy_script}" ]]; then
  safe_eval_policy "${recursive_policy_script}" \
    --enabled "${recursive_enabled_raw}" \
    --provider "${PROVIDER:-}" \
    --lane "${AGENT_NAME:-}" \
    --depth "${recursive_depth_raw}" \
    --target-lanes "${recursive_targets_raw}" \
    --dry-run "${recursive_dry_run_raw}" \
    --format env
fi

# Force requested model onto the latest-track policy for each provider.
requested_model="$(echo "${MODEL:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
case "${PROVIDER}" in
  codex)
    if [[ "${AGENT_NAME}" == "codex-main-orchestrator" ]]; then
      MODEL="${codex_main_model}"
    elif [[ -n "${requested_model}" && "${requested_model}" =~ ^gpt-5(\.[0-9]+)?-codex-spark$ ]]; then
      MODEL="${requested_model}"
    else
      MODEL="${codex_multi_agent_model}"
    fi
    ;;
  claude)
    MODEL="${claude_opus_model}"
    ;;
  glm)
    MODEL="${glm_model}"
    ;;
  gemini)
    if [[ "${requested_model}" == "gemini-3.1-pro" || "${requested_model}" == "gemini-3-flash" ]]; then
      MODEL="${requested_model}"
    else
      MODEL="gemini-3.1-pro"
    fi
    ;;
  xai)
    if [[ -n "${requested_model}" && "${requested_model}" =~ ^grok-4([.-].+)?$ ]]; then
      MODEL="${requested_model}"
    else
      MODEL="${xai_latest_model}"
    fi
    ;;
esac

if [[ "${PROVIDER}" == "codex" && "${recursive_active}" == "true" ]]; then
  sys_prompt="${sys_prompt} Recursive Delegation Mode enabled: execute parent -> child -> grandchild delegation depth ${recursive_depth} before finalizing. Use codex multi-agent reasoning and include marker in rationale: delegation_mode=recursive depth=${recursive_depth} lane=${AGENT_NAME}."
fi

if [[ "${PROVIDER}" == "gemini" && -z "${GEMINI_API_KEY:-}" ]]; then
  result="$(jq -n \
    --arg name "${AGENT_NAME}" \
    --arg provider "${PROVIDER}" \
    --arg api_url "${API_URL}" \
    --arg model "${MODEL}" \
    --arg agent_role "${AGENT_ROLE}" \
    '{
      name:$name,
      provider:$provider,
      api_url:$api_url,
      model:$model,
      agent_role:$agent_role,
      http_code:"skipped",
      skipped:true,
      risk:"MEDIUM",
      approve:false,
      findings:["Skipped: missing GEMINI_API_KEY"],
      recommendation:"Add GEMINI_API_KEY to enable Gemini voter",
      rationale:"Gemini voter was skipped due to missing secret",
      execution_engine:"harness"
    }')"
  echo "${result}" > "agent-${AGENT_NAME}.json"
  exit 0
fi

if [[ "${PROVIDER}" == "xai" && -z "${XAI_API_KEY:-}" ]]; then
  result="$(jq -n \
    --arg name "${AGENT_NAME}" \
    --arg provider "${PROVIDER}" \
    --arg api_url "${API_URL}" \
    --arg model "${MODEL}" \
    --arg agent_role "${AGENT_ROLE}" \
    '{
      name:$name,
      provider:$provider,
      api_url:$api_url,
      model:$model,
      agent_role:$agent_role,
      http_code:"skipped",
      skipped:true,
      risk:"MEDIUM",
      approve:false,
      findings:["Skipped: missing XAI_API_KEY"],
      recommendation:"Add XAI_API_KEY to enable xAI voter",
      rationale:"xAI voter was skipped due to missing secret",
      execution_engine:"harness"
    }')"
  echo "${result}" > "agent-${AGENT_NAME}.json"
  exit 0
fi

if [[ "${PROVIDER}" == "claude" && "${claude_assist_execution_policy}" == "proxy" && "${copilot_runner_available}" != "true" ]]; then
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    PROVIDER="codex"
    API_URL="https://api.openai.com/v1/chat/completions"
    MODEL="${codex_multi_agent_model}"
    CLAUDE_PROXY_MODE="true"
    CLAUDE_PROXY_NOTE="Claude assist execution policy=proxy: executed via Codex proxy."
  else
    if [[ "${strict_opus_assist_direct}" == "true" && "${AGENT_NAME}" == "claude-opus-assist" ]]; then
      echo "Strict guard violation: claude-opus-assist requires direct Claude execution, but proxy prerequisites are unavailable." >&2
      exit 43
    fi
    result="$(jq -n \
      --arg name "${AGENT_NAME}" \
      --arg provider "${PROVIDER}" \
      --arg api_url "${API_URL}" \
      --arg model "${MODEL}" \
      --arg agent_role "${AGENT_ROLE}" \
      '{
        name:$name,
        provider:$provider,
        api_url:$api_url,
        model:$model,
        agent_role:$agent_role,
        http_code:"skipped",
        skipped:true,
        risk:"MEDIUM",
        approve:false,
        findings:["Skipped: FUGUE_CLAUDE_ASSIST_EXECUTION_POLICY=proxy but OPENAI_API_KEY is not configured"],
        recommendation:"Set OPENAI_API_KEY or switch FUGUE_CLAUDE_ASSIST_EXECUTION_POLICY to direct|hybrid",
        rationale:"Claude assist lane requested proxy execution but Codex credentials are unavailable",
        execution_engine:"harness",
        execution_route:"claude-proxy-unavailable"
      }')"
    echo "${result}" > "agent-${AGENT_NAME}.json"
    exit 0
  fi
fi

if [[ "${PROVIDER}" == "claude" && -z "${ANTHROPIC_API_KEY:-}" && "${copilot_runner_available}" != "true" ]]; then
  if [[ "${claude_assist_execution_policy}" == "hybrid" && -n "${OPENAI_API_KEY:-}" ]]; then
    PROVIDER="codex"
    API_URL="https://api.openai.com/v1/chat/completions"
    MODEL="${codex_multi_agent_model}"
    CLAUDE_PROXY_MODE="true"
    CLAUDE_PROXY_NOTE="Claude assist execution policy=hybrid: executed via Codex proxy because ANTHROPIC_API_KEY is not configured."
  else
    if [[ "${strict_opus_assist_direct}" == "true" && "${AGENT_NAME}" == "claude-opus-assist" ]]; then
      echo "Strict guard violation: claude-opus-assist requires direct Claude execution, but ANTHROPIC_API_KEY is not configured." >&2
      exit 43
    fi
    result="$(jq -n \
      --arg name "${AGENT_NAME}" \
      --arg provider "${PROVIDER}" \
      --arg api_url "${API_URL}" \
      --arg model "${MODEL}" \
      --arg agent_role "${AGENT_ROLE}" \
      '{
        name:$name,
        provider:$provider,
        api_url:$api_url,
        model:$model,
        agent_role:$agent_role,
        http_code:"skipped",
        skipped:true,
        risk:"MEDIUM",
        approve:false,
        findings:["Skipped: missing ANTHROPIC_API_KEY for Claude lane"],
        recommendation:"Provide ANTHROPIC_API_KEY, or set FUGUE_CLAUDE_ASSIST_EXECUTION_POLICY=hybrid|proxy with OPENAI_API_KEY configured",
        rationale:"Claude lane was skipped because ANTHROPIC_API_KEY is not configured and execution policy could not use proxy fallback",
        execution_engine:"harness",
        execution_route:"claude-direct-unavailable"
      }')"
    echo "${result}" > "agent-${AGENT_NAME}.json"
    exit 0
  fi
fi

if [[ "${PROVIDER}" == "codex" && "${recursive_active}" == "true" && "${recursive_dry_run}" == "true" ]]; then
  result="$(jq -n \
    --arg name "${AGENT_NAME}" \
    --arg provider "codex" \
    --arg api_url "${API_URL}" \
    --arg model "${MODEL}" \
    --arg agent_role "${AGENT_ROLE}" \
    --arg requested_provider "${ORIGINAL_PROVIDER}" \
    --arg requested_model "${ORIGINAL_MODEL}" \
    --arg delegation_mode "recursive" \
    --arg delegation_depth "${recursive_depth}" \
    --arg delegation_reason "${recursive_reason}" \
    '{
      name:$name,
      provider:$provider,
      api_url:$api_url,
      model:$model,
      agent_role:$agent_role,
      requested_provider:$requested_provider,
      requested_model:$requested_model,
      http_code:"dry-run",
      skipped:false,
      delegation_mode:$delegation_mode,
      delegation_depth:($delegation_depth|tonumber),
      delegation_reason:$delegation_reason,
      risk:"MEDIUM",
      approve:false,
      findings:["Recursive delegation dry-run active for codex lane"],
      recommendation:"Disable FUGUE_CODEX_RECURSIVE_DRY_RUN to execute real recursive codex delegation",
      rationale:("delegation_mode=recursive depth=" + $delegation_depth + " dry_run=true"),
      execution_engine:"harness",
      execution_route:"codex-api-recursive-dry-run"
    }')"
  echo "${result}" > "agent-${AGENT_NAME}.json"
  exit 0
fi

req=""
auth_header=""
if [[ "${PROVIDER}" == "codex" || "${PROVIDER}" == "glm" || "${PROVIDER}" == "xai" ]]; then
  req="$(jq -n \
    --arg model "${MODEL}" \
    --arg s "${sys_prompt}" \
    --arg u "${user_prompt}" \
    '{model:$model,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"
  if [[ "${PROVIDER}" == "codex" ]]; then
    auth_header="Authorization: Bearer ${OPENAI_API_KEY}"
  elif [[ "${PROVIDER}" == "glm" ]]; then
    auth_header="Authorization: Bearer ${ZAI_API_KEY}"
  else
    auth_header="Authorization: Bearer ${XAI_API_KEY}"
  fi
elif [[ "${PROVIDER}" == "claude" ]]; then
  req="$(jq -n \
    --arg model "${MODEL}" \
    --arg s "${sys_prompt}" \
    --arg u "${user_prompt}" \
    '{model:$model,system:$s,messages:[{role:"user",content:$u}],max_tokens:1200,temperature:0.1}')"
else
  req="$(jq -n \
    --arg text "SYSTEM:\n${sys_prompt}\n\nUSER:\n${user_prompt}\n\nReturn ONLY JSON." \
    '{contents:[{parts:[{text:$text}]}],generationConfig:{temperature:0.1}}')"
fi

chosen_model="${MODEL}"
effective_provider="${PROVIDER}"
effective_api_url="${API_URL}"
http_code=""
content=""
attempt_trace=""

append_attempt() {
  local provider="$1"
  local model="$2"
  local code="$3"
  if [[ -n "${attempt_trace}" ]]; then
    attempt_trace="${attempt_trace};"
  fi
  attempt_trace="${attempt_trace}${provider}:${model}:${code}"
}

append_unique_candidate() {
  local candidate="$1"
  [[ -n "${candidate}" ]] || return 0
  local existing
  for existing in "${candidates[@]:-}"; do
    if [[ "${existing}" == "${candidate}" ]]; then
      return 0
    fi
  done
  candidates+=("${candidate}")
}

run_with_timeout() {
  local timeout_sec="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${timeout_sec}" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${timeout_sec}" "$@"
  else
    "$@"
  fi
}

extract_json_object() {
  local raw="$1"
  local extracted normalized
  extracted="$(jq -Rn --arg s "${raw}" '
    ($s | gsub("\r"; "") | gsub("^\\s+|\\s+$"; "")) as $t |
    if ($t | test("```json"; "i")) then
      (($t | split("```json") | .[1] // $t) | split("```") | .[0]) | gsub("^\\s+|\\s+$"; "")
    elif ($t | test("```"; "i")) then
      (($t | split("```") | .[1] // $t) | split("```") | .[0]) | gsub("^\\s+|\\s+$"; "")
    else
      $t
    end
  ')"
  normalized="$(echo "${extracted}" | jq -c '
    if type == "string" then (fromjson? // .) else . end
  ' 2>/dev/null || true)"
  if [[ -n "${normalized}" ]] && echo "${normalized}" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "${normalized}"
    return 0
  fi
  return 1
}

extract_response_error_message() {
  local file_path="${1:-response.json}"
  if [[ ! -s "${file_path}" ]]; then
    return 0
  fi
  jq -r '
    .error.message
    // .error.error.message
    // .error.details
    // .message
    // (if (.error | type) == "string" then .error else empty end)
    // empty
  ' "${file_path}" 2>/dev/null | head -n1
}

execute_copilot_claude() {
  local requested_model="$1"
  local out_file="copilot-response.txt"
  local err_file="copilot-response.stderr"
  local prompt parsed_output
  prompt="SYSTEM:
${sys_prompt}

USER:
${user_prompt}

Return ONLY valid JSON."
  if [[ "${AGENT_NAME:-}" == "claude-teams-executor" || "${AGENT_ROLE:-}" == "teams-executor" ]]; then
    prompt="${prompt}

Claude Teams bounded mode is active. Work as a narrow collaboration executor and return handoff-ready JSON only."
  fi

  local -a copilot_cmd
  copilot_cmd=("${copilot_runner_bin}" -p "${prompt}")
  if [[ "${copilot_allow_all_tools}" == "true" ]]; then
    copilot_cmd+=(--allow-all-tools)
  fi

  set +e
  GH_TOKEN="${copilot_runner_token}" \
  GITHUB_TOKEN="${copilot_runner_token}" \
    run_with_timeout 180 "${copilot_cmd[@]}" >"${out_file}" 2>"${err_file}"
  local rc=$?
  set -e

  append_attempt "copilot-cli" "${requested_model}" "exit${rc}"
  if [[ "${rc}" -ne 0 || ! -s "${out_file}" ]]; then
    return 1
  fi
  if ! parsed_output="$(extract_json_object "$(cat "${out_file}")")"; then
    append_attempt "copilot-cli" "${requested_model}" "parse-failed"
    return 1
  fi

  parsed="${parsed_output}"
  content="$(cat "${out_file}")"
  chosen_model="${requested_model}"
  effective_provider="claude"
  effective_api_url="copilot-cli"
  http_code="cli:0"
  append_attempt "copilot-cli" "${requested_model}" "ok"
  return 0
}

if [[ "${PROVIDER}" == "codex" ]]; then
  candidates=("${MODEL}" "${codex_main_model}" "${codex_multi_agent_model}" "gpt-5.4" "gpt-5-codex" "gpt-5" "gpt-4.1")
  for m in "${candidates[@]}"; do
    chosen_model="${m}"
    req="$(jq -n \
      --arg model "${chosen_model}" \
      --arg s "${sys_prompt}" \
      --arg u "${user_prompt}" \
      '{model:$model,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"

    http_code="$(curl -sS -o response.json -w "%{http_code}" "${API_URL}" \
      --connect-timeout "${FUGUE_CURL_CONNECT_TIMEOUT}" --max-time "${FUGUE_CURL_MAX_TIME}" --retry "${FUGUE_CURL_RETRY}" ${FUGUE_CURL_RETRY_ALL} \
      -H "${auth_header}" \
      -H "Content-Type: application/json" \
      -d "${req}" || true)"
    append_attempt "codex" "${m}" "${http_code}"
    if [[ "${http_code}" == "200" ]]; then
      break
    fi
  done

  if [[ "${http_code}" != "200" && -n "${ZAI_API_KEY:-}" ]]; then
    effective_provider="glm"
    effective_api_url="https://api.z.ai/api/coding/paas/v4/chat/completions"
    glm_fallback_candidates=()
    candidates=()
    append_unique_candidate "${glm_model}"
    append_unique_candidate "glm-4.6"
    append_unique_candidate "glm-4.5"
    glm_fallback_candidates=("${candidates[@]}")
    for gm in "${glm_fallback_candidates[@]}"; do
      chosen_model="${gm}"
      fallback_req="$(jq -n \
        --arg model "${chosen_model}" \
        --arg s "${sys_prompt}" \
        --arg u "${user_prompt}" \
        '{model:$model,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"
      http_code="$(curl -sS -o response.json -w "%{http_code}" "${effective_api_url}" \
        --connect-timeout "${FUGUE_CURL_CONNECT_TIMEOUT}" --max-time "${FUGUE_CURL_MAX_TIME}" --retry "${FUGUE_CURL_RETRY}" ${FUGUE_CURL_RETRY_ALL} \
        -H "Authorization: Bearer ${ZAI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "${fallback_req}" || true)"
      append_attempt "glm" "${chosen_model}" "${http_code}"
      if [[ "${http_code}" == "200" ]]; then
        break
      fi
    done
  fi
elif [[ "${PROVIDER}" == "xai" ]]; then
  candidates=("${MODEL}" "${xai_latest_model}" "grok-4-fast-reasoning" "grok-4-fast-non-reasoning")
  for m in "${candidates[@]}"; do
    chosen_model="${m}"
    req="$(jq -n \
      --arg model "${chosen_model}" \
      --arg s "${sys_prompt}" \
      --arg u "${user_prompt}" \
      '{model:$model,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"

    http_code="$(curl -sS -o response.json -w "%{http_code}" "${API_URL}" \
      --connect-timeout "${FUGUE_CURL_CONNECT_TIMEOUT}" --max-time "${FUGUE_CURL_MAX_TIME}" --retry "${FUGUE_CURL_RETRY}" ${FUGUE_CURL_RETRY_ALL} \
      -H "${auth_header}" \
      -H "Content-Type: application/json" \
      -d "${req}" || true)"
    append_attempt "xai" "${m}" "${http_code}"
    if [[ "${http_code}" == "200" ]]; then
      break
    fi
  done
elif [[ "${PROVIDER}" == "claude" ]]; then
  candidates=()
  append_unique_candidate "${MODEL}"
  append_unique_candidate "${claude_opus_model}"
  if [[ "${copilot_runner_available}" == "true" ]]; then
    execute_copilot_claude "${MODEL}" || true
  fi
  if [[ "${http_code}" != "cli:0" ]]; then
  for m in "${candidates[@]}"; do
    chosen_model="${m}"
    req="$(jq -n \
      --arg model "${chosen_model}" \
      --arg s "${sys_prompt}" \
      --arg u "${user_prompt}" \
      '{model:$model,system:$s,messages:[{role:"user",content:$u}],max_tokens:1200,temperature:0.1}')"

    http_code="$(curl -sS -o response.json -w "%{http_code}" "${API_URL}" \
      --connect-timeout "${FUGUE_CURL_CONNECT_TIMEOUT}" --max-time "${FUGUE_CURL_MAX_TIME}" --retry "${FUGUE_CURL_RETRY}" ${FUGUE_CURL_RETRY_ALL} \
      -H "x-api-key: ${ANTHROPIC_API_KEY}" \
      -H "anthropic-version: 2023-06-01" \
      -H "Content-Type: application/json" \
      -d "${req}" || true)"
    append_attempt "claude" "${m}" "${http_code}"
    if [[ "${http_code}" == "200" ]]; then
      break
    fi
  done
  fi
else
  if [[ "${PROVIDER}" == "glm" ]]; then
    candidates=()
    append_unique_candidate "${MODEL}"
    append_unique_candidate "${glm_model}"
    append_unique_candidate "glm-4.6"
    append_unique_candidate "glm-4.5"
    for m in "${candidates[@]}"; do
      chosen_model="${m}"
      req="$(jq -n \
        --arg model "${chosen_model}" \
        --arg s "${sys_prompt}" \
        --arg u "${user_prompt}" \
        '{model:$model,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"

      http_code="$(curl -sS -o response.json -w "%{http_code}" "${API_URL}" \
        --connect-timeout "${FUGUE_CURL_CONNECT_TIMEOUT}" --max-time "${FUGUE_CURL_MAX_TIME}" --retry "${FUGUE_CURL_RETRY}" ${FUGUE_CURL_RETRY_ALL} \
        -H "${auth_header}" \
        -H "Content-Type: application/json" \
        -d "${req}" || true)"
      append_attempt "glm" "${m}" "${http_code}"
      if [[ "${http_code}" == "200" ]]; then
        break
      fi
    done

    if [[ "${http_code}" != "200" && -n "${OPENAI_API_KEY:-}" ]]; then
      effective_provider="codex"
      effective_api_url="https://api.openai.com/v1/chat/completions"
      chosen_model="${codex_multi_agent_model}"
      fallback_req="$(jq -n \
        --arg model "${chosen_model}" \
        --arg s "${sys_prompt}" \
        --arg u "${user_prompt}" \
        '{model:$model,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"
      http_code="$(curl -sS -o response.json -w "%{http_code}" "${effective_api_url}" \
        --connect-timeout "${FUGUE_CURL_CONNECT_TIMEOUT}" --max-time "${FUGUE_CURL_MAX_TIME}" --retry "${FUGUE_CURL_RETRY}" ${FUGUE_CURL_RETRY_ALL} \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "${fallback_req}" || true)"
      append_attempt "codex" "${chosen_model}" "${http_code}"
    fi
  else
    gemini_candidates=("${MODEL}")
    if [[ -n "${gemini_fallback_model}" && "${MODEL}" != "${gemini_fallback_model}" ]]; then
      gemini_candidates+=("${gemini_fallback_model}")
    fi
    for gm in "${gemini_candidates[@]}"; do
      chosen_model="${gm}"
      gemini_url="${API_URL}/${gm}:generateContent?key=${GEMINI_API_KEY}"
      http_code="$(curl -sS -o response.json -w "%{http_code}" "${gemini_url}" \
        --connect-timeout "${FUGUE_CURL_CONNECT_TIMEOUT}" --max-time "${FUGUE_CURL_MAX_TIME}" --retry "${FUGUE_CURL_RETRY}" ${FUGUE_CURL_RETRY_ALL} \
        -H "Content-Type: application/json" \
        -d "${req}" || true)"
      append_attempt "gemini" "${gm}" "${http_code}"
      if [[ "${http_code}" == "200" ]]; then
        break
      fi
    done
  fi
fi

if [[ "${http_code}" == "cli:0" && "${effective_api_url}" == "copilot-cli" ]]; then
  :
elif [[ "${PROVIDER}" == "gemini" ]]; then
  content="$(jq -r '.candidates[0].content.parts[0].text // ""' response.json 2>/dev/null || echo "")"
elif [[ "${PROVIDER}" == "claude" ]]; then
  content="$(jq -r '[.content[]? | select(.type=="text") | .text] | join("\n") // ""' response.json 2>/dev/null || echo "")"
else
  content="$(jq -r '.choices[0].message.content // ""' response.json 2>/dev/null || echo "")"
fi

skipped_flag="false"
provider_success="false"
if [[ "${PROVIDER}" == "claude" ]]; then
  if [[ "${http_code}" == "200" || "${http_code}" == "cli:0" ]]; then
    provider_success="true"
  fi
elif [[ "${http_code}" == "200" ]]; then
  provider_success="true"
fi
if [[ ( "${PROVIDER}" == "gemini" || "${PROVIDER}" == "xai" || "${PROVIDER}" == "claude" || "${PROVIDER}" == "glm" ) && "${provider_success}" != "true" ]]; then
  skipped_flag="true"
fi

optional_error_note=""
optional_provider_label=""
error_message="$(extract_response_error_message response.json)"
if [[ "${PROVIDER}" == "glm" && "${http_code}" != "200" ]]; then
  optional_provider_label="GLM"
  if [[ -n "${error_message}" ]]; then
    optional_error_note="GLM API error (HTTP ${http_code}): ${error_message}"
  else
    optional_error_note="GLM API error (HTTP ${http_code})"
  fi
elif [[ "${PROVIDER}" == "gemini" && "${http_code}" != "200" ]]; then
  optional_provider_label="Gemini"
  if [[ "${http_code}" == "429" ]]; then
    optional_error_note="Gemini API rate limited (HTTP 429)"
  elif [[ -n "${error_message}" ]]; then
    optional_error_note="Gemini API error (HTTP ${http_code}): ${error_message}"
  else
    optional_error_note="Gemini API error (HTTP ${http_code})"
  fi
elif [[ "${PROVIDER}" == "xai" && "${http_code}" != "200" ]]; then
  optional_provider_label="xAI"
  if [[ "${http_code}" == "429" ]]; then
    optional_error_note="xAI API rate limited (HTTP 429)"
  elif [[ -n "${error_message}" ]]; then
    optional_error_note="xAI API error (HTTP ${http_code}): ${error_message}"
  else
    optional_error_note="xAI API error (HTTP ${http_code})"
  fi
elif [[ "${PROVIDER}" == "claude" && "${provider_success}" != "true" ]]; then
  optional_provider_label="Claude"
  if [[ "${http_code}" == "429" ]]; then
    optional_error_note="Claude API rate limited (HTTP 429)"
  elif [[ -n "${error_message}" ]]; then
    optional_error_note="Claude API error (HTTP ${http_code}): ${error_message}"
  else
    optional_error_note="Claude API error (HTTP ${http_code})"
  fi
fi

# Fail-closed guards for critical orchestration lanes.
if [[ "${strict_main_codex_model}" == "true" && "${AGENT_NAME}" == "codex-main-orchestrator" ]]; then
  required_codex_main_model="${MODEL:-${codex_main_model}}"
  if [[ "${effective_provider}" != "codex" || "${chosen_model}" != "${required_codex_main_model}" || "${http_code}" != "200" ]]; then
    echo "Strict guard violation: codex-main-orchestrator must execute with provider=codex model=${required_codex_main_model} (http=200)." >&2
    echo "Observed provider=${effective_provider} model=${chosen_model} http=${http_code}" >&2
    echo "Attempt trace=${attempt_trace}" >&2
    exit 42
  fi
fi
if [[ "${strict_opus_assist_direct}" == "true" && "${AGENT_NAME}" == "claude-opus-assist" ]]; then
  if [[ "${effective_provider}" != "claude" || "${chosen_model}" != "${claude_opus_model}" || "${http_code}" != "200" || "${CLAUDE_PROXY_MODE}" == "true" || "${effective_api_url}" == "copilot-cli" ]]; then
    echo "Strict guard violation: claude-opus-assist must execute directly with provider=claude model=${claude_opus_model} (http=200, no proxy/copilot)." >&2
    echo "Observed provider=${effective_provider} model=${chosen_model} http=${http_code} proxy=${CLAUDE_PROXY_MODE} api_url=${effective_api_url}" >&2
    echo "Attempt trace=${attempt_trace}" >&2
    exit 43
  fi
fi

extracted="$(jq -Rn --arg s "${content}" '
  ($s | gsub("\r"; "") | gsub("^\\s+|\\s+$"; "")) as $t |
  if ($t | test("```json"; "i")) then
    (($t | split("```json") | .[1] // $t) | split("```") | .[0]) | gsub("^\\s+|\\s+$"; "")
  elif ($t | test("```"; "i")) then
    (($t | split("```") | .[1] // $t) | split("```") | .[0]) | gsub("^\\s+|\\s+$"; "")
  else
    $t
  end
')"

normalized="$(echo "${extracted}" | jq -c '
  if type == "string" then (fromjson? // .) else . end
' 2>/dev/null || true)"

if [[ -n "${optional_error_note}" ]]; then
  parsed="$(jq -n \
    --arg note "${optional_error_note}" \
    --arg provider "${optional_provider_label}" \
    '{
      risk:"MEDIUM",
      approve:false,
      findings:[$note],
      recommendation:("Retry later or reduce " + $provider + " specialist lane pressure"),
      rationale:"Optional specialist lane skipped due to provider-side throttling/error"
    }')"
elif [[ -n "${normalized}" ]] && echo "${normalized}" | jq -e 'type == "object"' >/dev/null 2>&1; then
  parsed="${normalized}"
else
  parsed="$(jq -n --arg c "${content}" '{risk:"MEDIUM",approve:false,findings:["Could not parse JSON object from model output"],recommendation:"Manual review required",rationale:($c|tostring)}')"
fi

if [[ "${CLAUDE_PROXY_MODE}" == "true" ]]; then
  parsed="$(echo "${parsed}" | jq -c \
    --arg note "${CLAUDE_PROXY_NOTE}" \
    '{
      risk:(.risk // "MEDIUM"),
      approve:(.approve // false),
      findings:(
        (if (.findings|type)=="array" then .findings else [(.findings|tostring)] end) + [$note]
      ),
      recommendation:(.recommendation // "No recommendation"),
      rationale:(
        (.rationale // "No rationale") + " | " + $note
      )
    }')"
fi

reported_provider="${effective_provider}"
if [[ "${CLAUDE_PROXY_MODE}" == "true" ]]; then
  reported_provider="claude-max-proxy-codex"
fi
execution_route="native"
if [[ "${ORIGINAL_PROVIDER}" == "claude" ]]; then
  execution_route="claude-direct"
fi
if [[ "${CLAUDE_PROXY_MODE}" == "true" ]]; then
  execution_route="claude-via-codex-proxy"
fi
if [[ "${effective_api_url}" == "copilot-cli" ]]; then
  execution_route="claude-via-copilot-cli"
fi
if [[ "${ORIGINAL_PROVIDER}" == "codex" && "${recursive_active}" == "true" ]]; then
  if [[ "${effective_provider}" == "codex" ]]; then
    execution_route="codex-api-recursive"
  else
    execution_route="codex-api-recursive-fallback"
  fi
fi

result="$(jq -n \
  --arg name "${AGENT_NAME}" \
  --arg provider "${reported_provider}" \
  --arg api_url "${effective_api_url}" \
  --arg model "${chosen_model}" \
  --arg agent_role "${AGENT_ROLE}" \
  --arg requested_provider "${ORIGINAL_PROVIDER}" \
  --arg requested_model "${ORIGINAL_MODEL}" \
  --argjson payload "${parsed}" \
  --arg http_code "${http_code}" \
  --arg skipped "${skipped_flag}" \
  --arg execution_route "${execution_route}" \
  --arg model_attempts "${attempt_trace}" \
  --arg delegation_mode "$( [[ "${recursive_active}" == "true" ]] && echo "recursive" || echo "flat" )" \
  --arg delegation_depth "$( [[ "${recursive_active}" == "true" ]] && echo "${recursive_depth}" || echo "1" )" \
  --arg delegation_reason "${recursive_reason}" \
  '{
    name:$name,
    provider:$provider,
    api_url:$api_url,
    model:$model,
    agent_role:$agent_role,
    requested_provider:$requested_provider,
    requested_model:$requested_model,
    http_code:$http_code,
    skipped:($skipped == "true"),
    model_attempts:$model_attempts,
    delegation_mode:$delegation_mode,
    delegation_depth:($delegation_depth|tonumber),
    delegation_reason:$delegation_reason,
    risk:(($payload.risk // "MEDIUM")|ascii_upcase),
    approve:($payload.approve // false),
    findings:(if ($payload.findings|type)=="array" then $payload.findings else [($payload.findings|tostring)] end),
    recommendation:($payload.recommendation // "No recommendation"),
    rationale:($payload.rationale // "No rationale"),
    execution_engine:"harness",
    execution_route:$execution_route
  }')"

echo "${result}" > "agent-${AGENT_NAME}.json"
