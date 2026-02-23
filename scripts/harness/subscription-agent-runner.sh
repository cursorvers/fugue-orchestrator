#!/usr/bin/env bash
set -euo pipefail

# Subscription-first runner:
# - Codex lane -> `codex exec`
# - Claude lane -> `claude --print`
# This runner intentionally avoids pay-as-you-go API calls.

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

strict_main_codex_model="$(echo "${STRICT_MAIN_CODEX_MODEL:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${strict_main_codex_model}" != "true" ]]; then
  strict_main_codex_model="false"
fi
strict_opus_assist_direct="$(echo "${STRICT_OPUS_ASSIST_DIRECT:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${strict_opus_assist_direct}" != "true" ]]; then
  strict_opus_assist_direct="false"
fi
claude_opus_model="$(echo "${CLAUDE_OPUS_MODEL:-claude-opus-4-6}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ -z "${claude_opus_model}" ]]; then
  claude_opus_model="claude-opus-4-6"
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
  prompt="${sys_prompt}

${user_prompt}

Return ONLY valid JSON."

  set +e
  run_with_timeout "${subscription_timeout_sec}" \
    codex exec \
      --skip-git-repo-check \
      --sandbox read-only \
      --model "${model}" \
      --output-schema "${schema_file}" \
      --output-last-message "${out_file}" \
      "${prompt}" >"${events_file}" 2>"${err_file}"
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
  execution_route="codex-cli"
  http_code="cli:0"
  append_attempt "codex" "${model}" "ok"
  return 0
}

execute_claude_model() {
  local model="$1"
  local out_file="${tmp_dir}/claude-${model}-out.json"
  local err_file="${tmp_dir}/claude-${model}-stderr.log"
  local prompt
  prompt="${sys_prompt}

${user_prompt}

Return ONLY valid JSON."

  set +e
  run_with_timeout "${subscription_timeout_sec}" \
    claude \
      --print \
      --output-format json \
      --permission-mode bypassPermissions \
      --model "${model}" \
      "${prompt}" >"${out_file}" 2>"${err_file}"
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

  chosen_model="${model}"
  effective_provider="claude"
  execution_route="claude-cli"
  http_code="cli:0"
  append_attempt "claude" "${model}" "ok"
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
  candidates=("${MODEL}")
  if [[ -z "${MODEL}" ]]; then
    candidates=("gpt-5.3-codex")
  elif [[ "${MODEL}" != "gpt-5.3-codex" ]]; then
    candidates+=("gpt-5.3-codex")
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
      echo "Strict guard violation: codex-main-orchestrator must execute with codex CLI model gpt-5.3-codex." >&2
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
else
  write_skipped_result \
    "Skipped: provider ${PROVIDER} is not supported in subscription-cli mode" \
    "Use codex/claude lanes for subscription-only orchestration" \
    "subscription-cli mode intentionally disables pay-as-you-go providers" \
    "unsupported-provider"
fi

# Fail-closed guards for critical orchestration lanes.
if [[ "${strict_main_codex_model}" == "true" && "${AGENT_NAME}" == "codex-main-orchestrator" ]]; then
  if [[ "${effective_provider}" != "codex" || "${chosen_model}" != "gpt-5.3-codex" || "${http_code}" != "cli:0" ]]; then
    echo "Strict guard violation: codex-main-orchestrator must execute with provider=codex model=gpt-5.3-codex (subscription-cli)." >&2
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
    risk:(($payload.risk // "MEDIUM")|ascii_upcase),
    approve:($payload.approve // false),
    findings:(if ($payload.findings|type)=="array" then $payload.findings else [($payload.findings|tostring)] end),
    recommendation:($payload.recommendation // "No recommendation"),
    rationale:($payload.rationale // "No rationale"),
    execution_engine:"subscription-cli",
    execution_route:$execution_route
  }')"

echo "${result}" > "agent-${AGENT_NAME}.json"
