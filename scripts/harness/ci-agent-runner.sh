#!/usr/bin/env bash
set -euo pipefail

sys_prompt="You are ${AGENT_ROLE}. Analyze the GitHub issue and return ONLY valid JSON with keys: risk (LOW|MEDIUM|HIGH), approve (boolean), findings (array of strings), recommendation (string), rationale (string)."
user_prompt="Issue Title: ${ISSUE_TITLE}

Issue Body:
${ISSUE_BODY}"

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
raw_codex_main_model="$(echo "${CODEX_MAIN_MODEL:-gpt-5-codex}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_codex_multi_agent_model="$(echo "${CODEX_MULTI_AGENT_MODEL:-gpt-5.3-codex-spark}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_glm_model="$(echo "${GLM_MODEL:-${FUGUE_GLM_MODEL:-glm-5.0}}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_xai_model="$(echo "${XAI_MODEL_LATEST:-grok-4}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_gemini_fallback_model="$(echo "${GEMINI_FALLBACK_MODEL:-gemini-3-flash}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -x "${model_policy_script}" ]]; then
  eval "$("${model_policy_script}" \
    --codex-main-model "${raw_codex_main_model}" \
    --codex-multi-agent-model "${raw_codex_multi_agent_model}" \
    --claude-model "${raw_claude_model}" \
    --glm-model "${raw_glm_model}" \
    --gemini-model "gemini-3.1-pro" \
    --gemini-fallback-model "${raw_gemini_fallback_model}" \
    --xai-model "${raw_xai_model}" \
    --format env)"
  claude_opus_model="${claude_model}"
  xai_latest_model="${xai_model}"
else
  claude_opus_model="claude-sonnet-4-6"
  codex_main_model="gpt-5-codex"
  codex_multi_agent_model="gpt-5.3-codex-spark"
  glm_model="glm-5.0"
  xai_latest_model="grok-4"
  gemini_fallback_model="gemini-3-flash"
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
  eval "$("${recursive_policy_script}" \
    --enabled "${recursive_enabled_raw}" \
    --provider "${PROVIDER:-}" \
    --lane "${AGENT_NAME:-}" \
    --depth "${recursive_depth_raw}" \
    --target-lanes "${recursive_targets_raw}" \
    --dry-run "${recursive_dry_run_raw}" \
    --format env)"
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

if [[ "${PROVIDER}" == "claude" && "${claude_assist_execution_policy}" == "proxy" ]]; then
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

if [[ "${PROVIDER}" == "claude" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
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

if [[ "${PROVIDER}" == "codex" ]]; then
  candidates=("${MODEL}" "${codex_main_model}" "${codex_multi_agent_model}" "gpt-5-codex" "gpt-5" "gpt-4.1")
  for m in "${candidates[@]}"; do
    chosen_model="${m}"
    req="$(jq -n \
      --arg model "${chosen_model}" \
      --arg s "${sys_prompt}" \
      --arg u "${user_prompt}" \
      '{model:$model,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"

    http_code="$(curl -sS -o response.json -w "%{http_code}" "${API_URL}" \
      --connect-timeout 10 --max-time 60 --retry 2 \
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
    glm_fallback_candidates=("${glm_model}" "glm-4.5")
    for gm in "${glm_fallback_candidates[@]}"; do
      chosen_model="${gm}"
      fallback_req="$(jq -n \
        --arg model "${chosen_model}" \
        --arg s "${sys_prompt}" \
        --arg u "${user_prompt}" \
        '{model:$model,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"
      http_code="$(curl -sS -o response.json -w "%{http_code}" "${effective_api_url}" \
        --connect-timeout 10 --max-time 60 --retry 2 \
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
      --connect-timeout 10 --max-time 60 --retry 2 \
      -H "${auth_header}" \
      -H "Content-Type: application/json" \
      -d "${req}" || true)"
    append_attempt "xai" "${m}" "${http_code}"
    if [[ "${http_code}" == "200" ]]; then
      break
    fi
  done
elif [[ "${PROVIDER}" == "claude" ]]; then
  candidates=("${MODEL}" "${claude_opus_model}")
  for m in "${candidates[@]}"; do
    chosen_model="${m}"
    req="$(jq -n \
      --arg model "${chosen_model}" \
      --arg s "${sys_prompt}" \
      --arg u "${user_prompt}" \
      '{model:$model,system:$s,messages:[{role:"user",content:$u}],max_tokens:1200,temperature:0.1}')"

    http_code="$(curl -sS -o response.json -w "%{http_code}" "${API_URL}" \
      --connect-timeout 10 --max-time 60 --retry 2 \
      -H "x-api-key: ${ANTHROPIC_API_KEY}" \
      -H "anthropic-version: 2023-06-01" \
      -H "Content-Type: application/json" \
      -d "${req}" || true)"
    append_attempt "claude" "${m}" "${http_code}"
    if [[ "${http_code}" == "200" ]]; then
      break
    fi
  done
else
  if [[ "${PROVIDER}" == "glm" ]]; then
    candidates=("${MODEL}" "${glm_model}" "glm-4.5")
    for m in "${candidates[@]}"; do
      chosen_model="${m}"
      req="$(jq -n \
        --arg model "${chosen_model}" \
        --arg s "${sys_prompt}" \
        --arg u "${user_prompt}" \
        '{model:$model,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"

      http_code="$(curl -sS -o response.json -w "%{http_code}" "${API_URL}" \
        --connect-timeout 10 --max-time 60 --retry 2 \
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
        --connect-timeout 10 --max-time 60 --retry 2 \
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
        --connect-timeout 10 --max-time 60 --retry 2 \
        -H "Content-Type: application/json" \
        -d "${req}" || true)"
      append_attempt "gemini" "${gm}" "${http_code}"
      if [[ "${http_code}" == "200" ]]; then
        break
      fi
    done
  fi
fi

if [[ "${PROVIDER}" == "gemini" ]]; then
  content="$(jq -r '.candidates[0].content.parts[0].text // ""' response.json 2>/dev/null || echo "")"
elif [[ "${PROVIDER}" == "claude" ]]; then
  content="$(jq -r '[.content[]? | select(.type=="text") | .text] | join("\n") // ""' response.json 2>/dev/null || echo "")"
else
  content="$(jq -r '.choices[0].message.content // ""' response.json 2>/dev/null || echo "")"
fi

skipped_flag="false"
if [[ ( "${PROVIDER}" == "gemini" || "${PROVIDER}" == "xai" || "${PROVIDER}" == "claude" ) && "${http_code}" != "200" ]]; then
  skipped_flag="true"
fi

optional_error_note=""
optional_provider_label=""
if [[ "${PROVIDER}" == "gemini" && "${http_code}" != "200" ]]; then
  optional_provider_label="Gemini"
  if [[ "${http_code}" == "429" ]]; then
    optional_error_note="Gemini API rate limited (HTTP 429)"
  else
    optional_error_note="Gemini API error (HTTP ${http_code})"
  fi
elif [[ "${PROVIDER}" == "xai" && "${http_code}" != "200" ]]; then
  optional_provider_label="xAI"
  if [[ "${http_code}" == "429" ]]; then
    optional_error_note="xAI API rate limited (HTTP 429)"
  else
    optional_error_note="xAI API error (HTTP ${http_code})"
  fi
elif [[ "${PROVIDER}" == "claude" && "${http_code}" != "200" ]]; then
  optional_provider_label="Claude"
  if [[ "${http_code}" == "429" ]]; then
    optional_error_note="Claude API rate limited (HTTP 429)"
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
  if [[ "${effective_provider}" != "claude" || "${chosen_model}" != "${claude_opus_model}" || "${http_code}" != "200" || "${CLAUDE_PROXY_MODE}" == "true" ]]; then
    echo "Strict guard violation: claude-opus-assist must execute directly with provider=claude model=${claude_opus_model} (http=200, no proxy)." >&2
    echo "Observed provider=${effective_provider} model=${chosen_model} http=${http_code} proxy=${CLAUDE_PROXY_MODE}" >&2
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
