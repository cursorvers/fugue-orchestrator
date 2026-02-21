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

if [[ "${PROVIDER}" == "claude" && -z "${ANTHROPIC_API_KEY:-}" ]]; then
  if [[ "${claude_max_plan}" == "true" && -n "${OPENAI_API_KEY:-}" ]]; then
    PROVIDER="codex"
    API_URL="https://api.openai.com/v1/chat/completions"
    MODEL="gpt-5.3-codex-spark"
    CLAUDE_PROXY_MODE="true"
    CLAUDE_PROXY_NOTE="Claude MAX plan mode: executed via Codex proxy because ANTHROPIC_API_KEY is not configured."
  else
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
        findings:["Skipped: missing ANTHROPIC_API_KEY and Claude MAX proxy mode is disabled"],
        recommendation:"Set FUGUE_CLAUDE_MAX_PLAN=true or provide ANTHROPIC_API_KEY to enable Claude assist lanes",
        rationale:"Claude assist lane was skipped due to missing credential path",
        execution_engine:"harness"
      }')"
    echo "${result}" > "agent-${AGENT_NAME}.json"
    exit 0
  fi
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

if [[ "${PROVIDER}" == "codex" ]]; then
  candidates=("${MODEL}" "gpt-5.3-codex" "gpt-5.2-codex" "gpt-5.1-codex" "gpt-4.1" "gpt-4o-mini")
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
    if [[ "${http_code}" == "200" ]]; then
      break
    fi
  done

  if [[ "${http_code}" != "200" && -n "${ZAI_API_KEY:-}" ]]; then
    effective_provider="glm"
    effective_api_url="https://api.z.ai/api/coding/paas/v4/chat/completions"
    chosen_model="glm-5.0"
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
  fi
elif [[ "${PROVIDER}" == "xai" ]]; then
  candidates=("${MODEL}" "grok-3-mini" "grok-2-latest")
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
    if [[ "${http_code}" == "200" ]]; then
      break
    fi
  done
elif [[ "${PROVIDER}" == "claude" ]]; then
  candidates=("${MODEL}" "claude-opus-4-1-20250805" "claude-opus-4-20250514" "claude-3-7-sonnet-latest" "claude-3-5-sonnet-latest")
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
    if [[ "${http_code}" == "200" ]]; then
      break
    fi
  done
else
  if [[ "${PROVIDER}" == "glm" ]]; then
    candidates=("${MODEL}" "glm-5.0" "glm-4.5")
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
      if [[ "${http_code}" == "200" ]]; then
        break
      fi
    done

    if [[ "${http_code}" != "200" && -n "${OPENAI_API_KEY:-}" ]]; then
      effective_provider="codex"
      effective_api_url="https://api.openai.com/v1/chat/completions"
      chosen_model="gpt-5.3-codex-spark"
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
    fi
  else
    gemini_url="${API_URL}/${MODEL}:generateContent?key=${GEMINI_API_KEY}"
    http_code="$(curl -sS -o response.json -w "%{http_code}" "${gemini_url}" \
      --connect-timeout 10 --max-time 60 --retry 2 \
      -H "Content-Type: application/json" \
      -d "${req}" || true)"
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
  optional_provider_label="Claude Assist"
  if [[ "${http_code}" == "429" ]]; then
    optional_error_note="Claude Assist API rate limited (HTTP 429)"
  else
    optional_error_note="Claude Assist API error (HTTP ${http_code})"
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

result="$(jq -n \
  --arg name "${AGENT_NAME}" \
  --arg provider "${reported_provider}" \
  --arg api_url "${effective_api_url}" \
  --arg model "${chosen_model}" \
  --arg agent_role "${AGENT_ROLE}" \
  --argjson payload "${parsed}" \
  --arg http_code "${http_code}" \
  --arg skipped "${skipped_flag}" \
  '{
    name:$name,
    provider:$provider,
    api_url:$api_url,
    model:$model,
    agent_role:$agent_role,
    http_code:$http_code,
    skipped:($skipped == "true"),
    risk:(($payload.risk // "MEDIUM")|ascii_upcase),
    approve:($payload.approve // false),
    findings:(if ($payload.findings|type)=="array" then $payload.findings else [($payload.findings|tostring)] end),
    recommendation:($payload.recommendation // "No recommendation"),
    rationale:($payload.rationale // "No rationale"),
    execution_engine:"harness"
  }')"

echo "${result}" > "agent-${AGENT_NAME}.json"
