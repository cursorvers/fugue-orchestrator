#!/usr/bin/env bash
set -euo pipefail

# Subscription-first runner:
# - Codex lane -> `codex exec`
# - Claude lane -> `claude --print`
# - Optional GLM/Gemini specialist lanes -> direct API calls (hybrid mode)

sys_prompt="You are ${AGENT_ROLE}. Analyze the GitHub issue and return ONLY valid JSON with keys: risk (LOW|MEDIUM|HIGH), approve (boolean), findings (array of strings), recommendation (string), rationale (string)."
user_prompt="Issue Title: ${ISSUE_TITLE}

Issue Body:
${ISSUE_BODY}"

ORIGINAL_PROVIDER="${PROVIDER:-}"
ORIGINAL_MODEL="${MODEL:-}"
chosen_model="${MODEL}"
effective_provider="${PROVIDER}"
http_code=""
execution_route="subscription-cli"
attempt_trace=""
session_id=""

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
raw_glm_model="$(echo "${GLM_MODEL:-glm-5.0}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_gemini_model="$(echo "${GEMINI_MODEL:-gemini-3.1-pro}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_gemini_fallback_model="$(echo "${GEMINI_FALLBACK_MODEL:-gemini-3-flash}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -x "${model_policy_script}" ]]; then
  eval "$("${model_policy_script}" \
    --codex-main-model "${raw_codex_main_model}" \
    --codex-multi-agent-model "${raw_codex_multi_agent_model}" \
    --claude-model "${raw_claude_model}" \
    --glm-model "${raw_glm_model}" \
    --gemini-model "${raw_gemini_model}" \
    --gemini-fallback-model "${raw_gemini_fallback_model}" \
    --xai-model "grok-4" \
    --format env)"
  claude_opus_model="${claude_model}"
else
  claude_opus_model="claude-sonnet-4-6"
  codex_main_model="gpt-5-codex"
  codex_multi_agent_model="gpt-5.3-codex-spark"
  glm_model="glm-5.0"
  gemini_model="gemini-3.1-pro"
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

requested_model="$(echo "${MODEL:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${PROVIDER}" == "codex" ]]; then
  if [[ "${AGENT_NAME}" == "codex-main-orchestrator" ]]; then
    MODEL="${codex_main_model}"
  elif [[ -n "${requested_model}" && "${requested_model}" =~ ^gpt-5(\.[0-9]+)?-codex-spark$ ]]; then
    MODEL="${requested_model}"
  else
    MODEL="${codex_multi_agent_model}"
  fi
elif [[ "${PROVIDER}" == "claude" ]]; then
  MODEL="${claude_opus_model}"
elif [[ "${PROVIDER}" == "glm" ]]; then
  if [[ -n "${requested_model}" && "${requested_model}" =~ ^glm-5(\.[0-9]+)?$ ]]; then
    MODEL="${requested_model}"
  else
    MODEL="${glm_model}"
  fi
elif [[ "${PROVIDER}" == "gemini" ]]; then
  if [[ "${requested_model}" == "gemini-3.1-pro" || "${requested_model}" == "gemini-3-flash" ]]; then
    MODEL="${requested_model}"
  else
    MODEL="${gemini_model}"
  fi
fi

subscription_timeout_sec="$(echo "${SUBSCRIPTION_CLI_TIMEOUT_SEC:-180}" | tr -cd '0-9')"
if [[ -z "${subscription_timeout_sec}" ]]; then
  subscription_timeout_sec="180"
fi

append_attempt() {
  local provider="$1"
  local model="$2"
  local status="$3"
  if [[ -n "${attempt_trace}" ]]; then
    attempt_trace="${attempt_trace};"
  fi
  attempt_trace="${attempt_trace}${provider}:${model}:${status}"
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

codex_runner_available="false"
if command -v codex >/dev/null 2>&1; then
  codex_runner_available="true"
fi
claude_runner_available="false"
if command -v claude >/dev/null 2>&1; then
  claude_runner_available="true"
fi

write_skipped_result() {
  local findings="$1"
  local recommendation="$2"
  local rationale="$3"
  local route="$4"
  local payload
  payload="$(jq -n \
    --arg findings "${findings}" \
    --arg recommendation "${recommendation}" \
    --arg rationale "${rationale}" \
    '{risk:"MEDIUM",approve:false,findings:[$findings],recommendation:$recommendation,rationale:$rationale}')"
  result="$(jq -n \
    --arg name "${AGENT_NAME}" \
    --arg provider "${effective_provider}" \
    --arg api_url "subscription-cli" \
    --arg model "${chosen_model}" \
    --arg agent_role "${AGENT_ROLE}" \
    --arg requested_provider "${ORIGINAL_PROVIDER}" \
    --arg requested_model "${ORIGINAL_MODEL}" \
    --argjson payload "${payload}" \
    --arg http_code "skipped" \
    --arg execution_route "${route}" \
    --arg model_attempts "${attempt_trace}" \
    --arg session_id "${session_id}" \
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
      skipped:true,
      model_attempts:$model_attempts,
      session_id:(if $session_id == "" then null else $session_id end),
      delegation_mode:$delegation_mode,
      delegation_depth:($delegation_depth|tonumber),
      delegation_reason:$delegation_reason,
      risk:(($payload.risk // "MEDIUM")|ascii_upcase),
      approve:($payload.approve // false),
      findings:(if ($payload.findings|type)=="array" then $payload.findings else [($payload.findings|tostring)] end),
      recommendation:($payload.recommendation // "No recommendation"),
      rationale:($payload.rationale // "No rationale"),
      execution_engine:"subscription-cli",
      execution_route:$execution_route
    }')"
  echo "${result}" > "agent-${AGENT_NAME}.json"
  exit 0
}

schema_file="$(mktemp)"
cat > "${schema_file}" <<'JSON'
{"type":"object","properties":{"risk":{"type":"string"},"approve":{"type":"boolean"},"findings":{"type":"array","items":{"type":"string"}},"recommendation":{"type":"string"},"rationale":{"type":"string"}},"required":["risk","approve","findings","recommendation","rationale"],"additionalProperties":false}
JSON

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}" "${schema_file}"
}
trap cleanup EXIT

parsed=""
execute_codex_model() {
  local model="$1"
  local out_file="${tmp_dir}/codex-${model}-last.json"
  local err_file="${tmp_dir}/codex-${model}-stderr.log"
  local events_file="${tmp_dir}/codex-${model}-events.log"
  local prompt
  local -a codex_cmd
  if [[ "${recursive_active}" == "true" && "${recursive_dry_run}" == "true" ]]; then
    parsed="$(jq -cn \
      --arg lane "${AGENT_NAME}" \
      --arg depth "${recursive_depth}" \
      '{
        risk:"MEDIUM",
        approve:false,
        findings:["Recursive delegation dry-run active for lane " + $lane],
        recommendation:"Disable FUGUE_CODEX_RECURSIVE_DRY_RUN to execute recursive codex delegation",
        rationale:("delegation_mode=recursive depth=" + $depth + " dry_run=true")
      }')"
    chosen_model="${model}"
    effective_provider="codex"
    execution_route="codex-cli-recursive-dry-run"
    http_code="cli:0"
    append_attempt "codex" "${model}" "recursive-dry-run"
    return 0
  fi
  prompt="${sys_prompt}

${user_prompt}

Return ONLY valid JSON."
  if [[ "${recursive_active}" == "true" ]]; then
    prompt="${prompt}

Recursive Delegation Mode:
- Perform parent -> child -> grandchild delegation with depth ${recursive_depth}.
- Use Codex multi-agent orchestration to validate assumptions at each depth.
- Before finalizing, integrate child/grandchild findings back to the parent verdict.
- Keep the final output strictly in the required JSON schema.
- Include marker in rationale: delegation_mode=recursive depth=${recursive_depth} lane=${AGENT_NAME}."
  fi

  codex_cmd=(
    codex exec
    --skip-git-repo-check
    --sandbox read-only
    --model "${model}"
    --output-schema "${schema_file}"
    --output-last-message "${out_file}"
  )
  if [[ "${recursive_active}" == "true" ]]; then
    codex_cmd+=(--enable multi_agent)
  fi
  codex_cmd+=("${prompt}")
  set +e
  run_with_timeout "${subscription_timeout_sec}" "${codex_cmd[@]}" >"${events_file}" 2>"${err_file}"
  local rc=$?
  set -e

  append_attempt "codex" "${model}" "exit${rc}"
  if [[ "${rc}" -ne 0 ]]; then
    return 1
  fi
  if [[ ! -s "${out_file}" ]]; then
    append_attempt "codex" "${model}" "empty"
    return 1
  fi
  if ! jq -e 'type == "object"' "${out_file}" >/dev/null 2>&1; then
    append_attempt "codex" "${model}" "parse-failed"
    return 1
  fi

  parsed="$(cat "${out_file}")"
  chosen_model="${model}"
  effective_provider="codex"
  if [[ "${recursive_active}" == "true" ]]; then
    execution_route="codex-cli-recursive"
  else
    execution_route="codex-cli"
  fi
  http_code="cli:0"
  append_attempt "codex" "${model}" "ok"
  return 0
}

execute_claude_model() {
  local model="$1"
  local out_file="${tmp_dir}/claude-${model}-out.json"
  local err_file="${tmp_dir}/claude-${model}-stderr.log"
  local configured_session_id
  local -a claude_cmd
  local prompt
  prompt="${sys_prompt}

${user_prompt}

Return ONLY valid JSON."
  configured_session_id="$(echo "${CLAUDE_SESSION_ID:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  claude_cmd=(
    claude
    --print
    --output-format json
    --permission-mode bypassPermissions
    --model "${model}"
  )
  if [[ -n "${configured_session_id}" ]]; then
    claude_cmd+=(
      --session-id "${configured_session_id}"
    )
  fi
  claude_cmd+=("${prompt}")

  set +e
  run_with_timeout "${subscription_timeout_sec}" \
    "${claude_cmd[@]}" >"${out_file}" 2>"${err_file}"
  local rc=$?
  set -e

  append_attempt "claude" "${model}" "exit${rc}"
  if [[ "${rc}" -ne 0 ]]; then
    return 1
  fi
  if [[ ! -s "${out_file}" ]]; then
    append_attempt "claude" "${model}" "empty"
    return 1
  fi

  local result_text
  result_text="$(jq -r '.result // ""' "${out_file}" 2>/dev/null || true)"
  if [[ -z "${result_text}" ]]; then
    result_text="$(cat "${out_file}")"
  fi
  if ! parsed="$(extract_json_object "${result_text}")"; then
    append_attempt "claude" "${model}" "parse-failed"
    return 1
  fi
  session_id="$(jq -r '.session_id // empty' "${out_file}" 2>/dev/null || true)"
  if [[ -z "${session_id}" && -n "${configured_session_id}" ]]; then
    session_id="${configured_session_id}"
  fi

  chosen_model="${model}"
  effective_provider="claude"
  execution_route="claude-cli"
  http_code="cli:0"
  append_attempt "claude" "${model}" "ok"
  return 0
}

execute_glm_model() {
  local model="$1"
  local out_file="${tmp_dir}/glm-${model}-response.json"
  local req content
  req="$(jq -n \
    --arg m "${model}" \
    --arg s "${sys_prompt}" \
    --arg u "${user_prompt}" \
    '{model:$m,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"

  set +e
  http_code="$(curl -sS -o "${out_file}" -w "%{http_code}" "https://api.z.ai/api/coding/paas/v4/chat/completions" \
    --connect-timeout 10 --max-time 60 --retry 2 \
    -H "Authorization: Bearer ${ZAI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "${req}")"
  local rc=$?
  set -e

  append_attempt "glm" "${model}" "exit${rc}-http${http_code}"
  if [[ "${rc}" -ne 0 || "${http_code}" != "200" ]]; then
    return 1
  fi

  content="$(jq -r '.choices[0].message.content // ""' "${out_file}" 2>/dev/null || true)"
  if [[ -z "${content}" ]]; then
    append_attempt "glm" "${model}" "empty"
    return 1
  fi
  if ! parsed="$(extract_json_object "${content}")"; then
    append_attempt "glm" "${model}" "parse-failed"
    return 1
  fi

  chosen_model="${model}"
  effective_provider="glm"
  execution_route="glm-api"
  append_attempt "glm" "${model}" "ok"
  return 0
}

execute_gemini_model() {
  local model="$1"
  local out_file="${tmp_dir}/gemini-${model}-response.json"
  local req content gemini_url
  req="$(jq -n \
    --arg text "SYSTEM:\n${sys_prompt}\n\nUSER:\n${user_prompt}\n\nReturn ONLY JSON." \
    '{contents:[{parts:[{text:$text}]}],generationConfig:{temperature:0.1}}')"
  gemini_url="https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}"

  set +e
  http_code="$(curl -sS -o "${out_file}" -w "%{http_code}" "${gemini_url}" \
    --connect-timeout 10 --max-time 60 --retry 2 \
    -H "Content-Type: application/json" \
    -d "${req}")"
  local rc=$?
  set -e

  append_attempt "gemini" "${model}" "exit${rc}-http${http_code}"
  if [[ "${rc}" -ne 0 || "${http_code}" != "200" ]]; then
    return 1
  fi

  content="$(jq -r '.candidates[0].content.parts[0].text // ""' "${out_file}" 2>/dev/null || true)"
  if [[ -z "${content}" ]]; then
    append_attempt "gemini" "${model}" "empty"
    return 1
  fi
  if ! parsed="$(extract_json_object "${content}")"; then
    append_attempt "gemini" "${model}" "parse-failed"
    return 1
  fi

  chosen_model="${model}"
  effective_provider="gemini"
  execution_route="gemini-api"
  append_attempt "gemini" "${model}" "ok"
  return 0
}

if [[ "${PROVIDER}" == "codex" ]]; then
  if [[ "${codex_runner_available}" != "true" ]]; then
    if [[ "${strict_main_codex_model}" == "true" && "${AGENT_NAME}" == "codex-main-orchestrator" ]]; then
      echo "Strict guard violation: codex-main-orchestrator requires codex CLI, but codex command is not available." >&2
      exit 42
    fi
    write_skipped_result \
      "Skipped: subscription-cli mode requires codex CLI but command is unavailable" \
      "Install/login Codex CLI on the subscription worker" \
      "codex executable was not found in PATH" \
      "codex-cli-unavailable"
  fi
  required_codex_main_model="${MODEL:-${codex_main_model}}"
  candidates=("${required_codex_main_model}")
  if [[ "${required_codex_main_model}" != "${codex_main_model}" ]]; then
    candidates+=("${codex_main_model}")
  fi
  if [[ "${required_codex_main_model}" != "${codex_multi_agent_model}" ]]; then
    candidates+=("${codex_multi_agent_model}")
  fi
  ok="false"
  for m in "${candidates[@]}"; do
    if execute_codex_model "${m}"; then
      ok="true"
      break
    fi
  done
  if [[ "${ok}" != "true" ]]; then
    if [[ "${strict_main_codex_model}" == "true" && "${AGENT_NAME}" == "codex-main-orchestrator" ]]; then
      echo "Strict guard violation: codex-main-orchestrator must execute with codex CLI model=${required_codex_main_model}." >&2
      echo "Observed provider=${effective_provider} model=${chosen_model} http=${http_code}" >&2
      echo "Attempt trace=${attempt_trace}" >&2
      exit 42
    fi
    write_skipped_result \
      "Skipped: codex CLI failed to return valid JSON in subscription mode" \
      "Check Codex subscription login and model availability on worker host" \
      "All codex model attempts failed or returned non-JSON output" \
      "codex-cli-failed"
  fi
elif [[ "${PROVIDER}" == "claude" ]]; then
  if [[ "${claude_runner_available}" != "true" ]]; then
    if [[ "${strict_opus_assist_direct}" == "true" && "${AGENT_NAME}" == "claude-opus-assist" ]]; then
      echo "Strict guard violation: claude-opus-assist requires claude CLI, but claude command is not available." >&2
      exit 43
    fi
    write_skipped_result \
      "Skipped: subscription-cli mode requires Claude CLI but command is unavailable" \
      "Install/login Claude CLI on the subscription worker" \
      "claude executable was not found in PATH" \
      "claude-cli-unavailable"
  fi
  candidates=("${MODEL}")
  if [[ -z "${MODEL}" ]]; then
    candidates=("${claude_opus_model}")
  elif [[ "${MODEL}" != "${claude_opus_model}" ]]; then
    candidates+=("${claude_opus_model}")
  fi
  ok="false"
  for m in "${candidates[@]}"; do
    if execute_claude_model "${m}"; then
      ok="true"
      break
    fi
  done
  if [[ "${ok}" != "true" ]]; then
    if [[ "${strict_opus_assist_direct}" == "true" && "${AGENT_NAME}" == "claude-opus-assist" ]]; then
      echo "Strict guard violation: claude-opus-assist must execute via claude CLI with model=${claude_opus_model}." >&2
      echo "Observed provider=${effective_provider} model=${chosen_model} http=${http_code}" >&2
      echo "Attempt trace=${attempt_trace}" >&2
      exit 43
    fi
    write_skipped_result \
      "Skipped: Claude CLI failed to return valid JSON in subscription mode" \
      "Check Claude subscription login and model availability on worker host" \
      "All claude model attempts failed or returned non-JSON output" \
      "claude-cli-failed"
  fi
elif [[ "${PROVIDER}" == "glm" ]]; then
  if [[ -z "${ZAI_API_KEY:-}" ]]; then
    write_skipped_result \
      "Skipped: GLM lane requires ZAI_API_KEY in subscription hybrid mode" \
      "Set ZAI_API_KEY to enable GLM baseline voters" \
      "GLM API credential was not configured" \
      "glm-api-key-missing"
  fi
  candidates=("${MODEL}")
  if [[ -z "${MODEL}" ]]; then
    candidates=("${glm_model}")
  elif [[ "${MODEL}" != "${glm_model}" ]]; then
    candidates+=("${glm_model}")
  fi
  ok="false"
  for m in "${candidates[@]}"; do
    if execute_glm_model "${m}"; then
      ok="true"
      break
    fi
  done
  if [[ "${ok}" != "true" ]]; then
    write_skipped_result \
      "Skipped: GLM API failed to return valid JSON in subscription hybrid mode" \
      "Check ZAI_API_KEY and GLM endpoint availability" \
      "All GLM model attempts failed or returned non-JSON output" \
      "glm-api-failed"
  fi
elif [[ "${PROVIDER}" == "gemini" ]]; then
  if [[ -z "${GEMINI_API_KEY:-}" ]]; then
    write_skipped_result \
      "Skipped: Gemini lane requires GEMINI_API_KEY in subscription hybrid mode" \
      "Set GEMINI_API_KEY to enable design-oriented Gemini voter" \
      "Gemini API credential was not configured" \
      "gemini-api-key-missing"
  fi
  candidates=("${MODEL}")
  if [[ -z "${MODEL}" ]]; then
    candidates=("${gemini_model}")
  elif [[ "${MODEL}" != "${gemini_model}" ]]; then
    candidates+=("${gemini_model}")
  fi
  if [[ -n "${gemini_fallback_model}" && "${gemini_fallback_model}" != "${gemini_model}" ]]; then
    candidates+=("${gemini_fallback_model}")
  fi
  ok="false"
  for m in "${candidates[@]}"; do
    if execute_gemini_model "${m}"; then
      ok="true"
      break
    fi
  done
  if [[ "${ok}" != "true" ]]; then
    write_skipped_result \
      "Skipped: Gemini API failed to return valid JSON in subscription hybrid mode" \
      "Check GEMINI_API_KEY and Gemini endpoint availability" \
      "All Gemini model attempts failed or returned non-JSON output" \
      "gemini-api-failed"
  fi
else
  write_skipped_result \
    "Skipped: provider ${PROVIDER} is not supported in subscription-cli mode" \
    "Use codex/claude/glm/gemini lanes for this execution profile" \
    "subscription hybrid mode only supports codex-cli, claude-cli, glm-api, and gemini-api" \
    "unsupported-provider"
fi

# Fail-closed guards for critical orchestration lanes.
if [[ "${strict_main_codex_model}" == "true" && "${AGENT_NAME}" == "codex-main-orchestrator" ]]; then
  required_codex_main_model="${MODEL:-${codex_main_model}}"
  if [[ "${effective_provider}" != "codex" || "${chosen_model}" != "${required_codex_main_model}" || "${http_code}" != "cli:0" ]]; then
    echo "Strict guard violation: codex-main-orchestrator must execute with provider=codex model=${required_codex_main_model} (subscription-cli)." >&2
    echo "Observed provider=${effective_provider} model=${chosen_model} http=${http_code}" >&2
    echo "Attempt trace=${attempt_trace}" >&2
    exit 42
  fi
fi
if [[ "${strict_opus_assist_direct}" == "true" && "${AGENT_NAME}" == "claude-opus-assist" ]]; then
  if [[ "${effective_provider}" != "claude" || "${chosen_model}" != "${claude_opus_model}" || "${http_code}" != "cli:0" ]]; then
    echo "Strict guard violation: claude-opus-assist must execute directly with provider=claude model=${claude_opus_model} (subscription-cli)." >&2
    echo "Observed provider=${effective_provider} model=${chosen_model} http=${http_code}" >&2
    echo "Attempt trace=${attempt_trace}" >&2
    exit 43
  fi
fi

result="$(jq -n \
  --arg name "${AGENT_NAME}" \
  --arg provider "${effective_provider}" \
  --arg api_url "subscription-cli" \
  --arg model "${chosen_model}" \
  --arg agent_role "${AGENT_ROLE}" \
  --arg requested_provider "${ORIGINAL_PROVIDER}" \
  --arg requested_model "${ORIGINAL_MODEL}" \
  --argjson payload "${parsed}" \
  --arg http_code "${http_code}" \
  --arg execution_route "${execution_route}" \
  --arg model_attempts "${attempt_trace}" \
  --arg session_id "${session_id}" \
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
    skipped:false,
    model_attempts:$model_attempts,
    session_id:(if $session_id == "" then null else $session_id end),
    delegation_mode:$delegation_mode,
    delegation_depth:($delegation_depth|tonumber),
    delegation_reason:$delegation_reason,
    risk:(($payload.risk // "MEDIUM")|ascii_upcase),
    approve:($payload.approve // false),
    findings:(if ($payload.findings|type)=="array" then $payload.findings else [($payload.findings|tostring)] end),
    recommendation:($payload.recommendation // "No recommendation"),
    rationale:($payload.rationale // "No rationale"),
    execution_engine:"subscription-cli",
    execution_route:$execution_route
  }')"

echo "${result}" > "agent-${AGENT_NAME}.json"
