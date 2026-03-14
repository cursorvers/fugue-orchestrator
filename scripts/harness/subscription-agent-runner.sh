#!/usr/bin/env bash
set -euo pipefail

# Subscription-first runner:
# - Codex lane -> `codex exec`
# - Claude lane -> `claude --print`
# - Gemini lane -> `gemini` CLI first, API fallback
# - Optional GLM specialist lanes -> direct API calls (hybrid mode)
# - Metered Gemini/xAI lanes are reserved for overflow/tie-break only

sys_prompt="You are ${AGENT_ROLE}. Analyze the GitHub issue and return ONLY valid JSON with keys: risk (LOW|MEDIUM|HIGH), approve (boolean), findings (array of strings), recommendation (string), rationale (string)."
user_prompt="Issue Title: ${ISSUE_TITLE}

Issue Body:
${ISSUE_BODY}"

ORIGINAL_PROVIDER="${PROVIDER:-}"
ORIGINAL_MODEL="${MODEL:-}"
execution_profile="$(echo "${EXECUTION_PROFILE:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
chosen_model="${MODEL:-}"
effective_provider="${PROVIDER:-}"
http_code=""
execution_route="subscription-cli"
attempt_trace=""
session_id=""
claude_failure_note=""
copilot_failure_note=""
claude_max_plan="$(echo "${CLAUDE_MAX_PLAN:-${FUGUE_CLAUDE_MAX_PLAN:-true}}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_max_plan}" != "true" ]]; then
  claude_max_plan="false"
fi
claude_assist_execution_policy="$(echo "${CLAUDE_ASSIST_EXECUTION_POLICY:-${FUGUE_CLAUDE_ASSIST_EXECUTION_POLICY:-}}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${claude_assist_execution_policy}" != "direct" && "${claude_assist_execution_policy}" != "hybrid" && "${claude_assist_execution_policy}" != "proxy" ]]; then
  claude_assist_execution_policy=""
fi
if [[ -z "${claude_assist_execution_policy}" ]]; then
  if [[ "${execution_profile}" == "local-direct" ]]; then
    claude_assist_execution_policy="direct"
  elif [[ "${claude_max_plan}" == "true" ]]; then
    claude_assist_execution_policy="hybrid"
  else
    claude_assist_execution_policy="direct"
  fi
fi
fallback_used="false"
missing_lane=""
fallback_provider=""
fallback_reason=""
metered_reason="$(echo "${METERED_PROVIDER_REASON:-${FUGUE_METERED_PROVIDER_REASON:-none}}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${metered_reason}" != "overflow" && "${metered_reason}" != "tie-break" ]]; then
  metered_reason="none"
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
raw_claude_model="$(echo "${CLAUDE_OPUS_MODEL:-claude-opus-4-6}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_codex_main_model="$(echo "${CODEX_MAIN_MODEL:-gpt-5.4}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_codex_multi_agent_model="$(echo "${CODEX_MULTI_AGENT_MODEL:-gpt-5-codex}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_glm_model="$(echo "${GLM_MODEL:-glm-5}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_gemini_model="$(echo "${GEMINI_MODEL:-gemini-2.5-pro}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_gemini_fallback_model="$(echo "${GEMINI_FALLBACK_MODEL:-gemini-2.5-flash}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
raw_xai_model="$(echo "${XAI_MODEL:-grok-4}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
# shellcheck source=../lib/safe-eval-policy.sh
source "${script_dir}/../lib/safe-eval-policy.sh"
if [[ -x "${model_policy_script}" ]]; then
  safe_eval_policy "${model_policy_script}" \
    --codex-main-model "${raw_codex_main_model}" \
    --codex-multi-agent-model "${raw_codex_multi_agent_model}" \
    --claude-model "${raw_claude_model}" \
    --glm-model "${raw_glm_model}" \
    --gemini-model "${raw_gemini_model}" \
    --gemini-fallback-model "${raw_gemini_fallback_model}" \
    --xai-model "${raw_xai_model}" \
    --format env
  claude_opus_model="${claude_cli_model}"
else
  claude_opus_model="claude-opus-4-6"
  codex_main_model="gpt-5.4"
  codex_multi_agent_model="gpt-5-codex"
  glm_model="glm-5"
  gemini_model="gemini-2.5-pro"
  gemini_fallback_model="gemini-2.5-flash"
  xai_model="grok-4"
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
  if [[ -n "${requested_model}" && "${requested_model}" =~ ^glm-5(\.0)?$ ]]; then
    MODEL="${glm_model}"
  else
    MODEL="${glm_model}"
  fi
elif [[ "${PROVIDER}" == "gemini" ]]; then
  if [[ "${requested_model}" == "gemini-2.5-pro" || "${requested_model}" == "gemini-2.5-flash" || "${requested_model}" == "gemini-2.5-flash-lite" ]]; then
    MODEL="${requested_model}"
  else
    MODEL="${gemini_model}"
  fi
elif [[ "${PROVIDER}" == "xai" ]]; then
  MODEL="${xai_model}"
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

claude_help_cache=""
detect_claude_permission_flag() {
  if [[ -z "${claude_help_cache}" ]]; then
    claude_help_cache="$(claude --help 2>&1 | strip_known_cli_noise || true)"
  fi
  if echo "${claude_help_cache}" | grep -q -- '--dangerously-skip-permissions'; then
    echo "dangerously-skip-permissions"
  elif echo "${claude_help_cache}" | grep -q -- '--permission-mode'; then
    echo "permission-mode"
  else
    echo ""
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

strip_known_cli_noise() {
  awk 'index($0, "MallocStackLogging") == 0 { print }'
}

filter_known_cli_noise_file() {
  local file_path="$1"
  local tmp_file
  [[ -f "${file_path}" ]] || return 0
  tmp_file="${file_path}.filtered"
  strip_known_cli_noise < "${file_path}" > "${tmp_file}"
  mv "${tmp_file}" "${file_path}"
}

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

mark_missing_lane() {
  missing_lane="$1"
}

mark_fallback() {
  local provider="$1"
  local reason="$2"
  fallback_used="true"
  fallback_provider="${provider}"
  fallback_reason="${reason}"
}

detect_token_type() {
  local token="${1:-}"
  case "${token}" in
    gho_*) printf 'oauth' ;;
    github_pat_*) printf 'fine_grained_pat' ;;
    ghu_*) printf 'user_to_server' ;;
    ghs_*) printf 'app_installation' ;;
    ghp_*) printf 'classic_pat' ;;
    '') printf 'none' ;;
    *) printf 'unknown' ;;
  esac
}

codex_runner_available="false"
if command -v codex >/dev/null 2>&1; then
  codex_runner_available="true"
fi
claude_runner_available="false"
claude_cli_override="$(normalize_optional_bool "${HAS_CLAUDE_CLI:-${FUGUE_HAS_CLAUDE_CLI:-}}" || true)"
if [[ -n "${claude_cli_override}" ]]; then
  claude_runner_available="${claude_cli_override}"
elif command -v claude >/dev/null 2>&1; then
  claude_runner_available="true"
fi
gemini_runner_available="false"
if command -v gemini >/dev/null 2>&1; then
  gemini_runner_available="true"
fi
copilot_runner_bin="${COPILOT_CLI_BIN:-copilot}"
copilot_npx_package="${COPILOT_NPX_PACKAGE:-@github/copilot}"
copilot_runner_token="${COPILOT_GITHUB_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"
if [[ -z "${copilot_runner_token}" && -n "${HAS_GH_AUTH_TOKEN:-}" ]]; then
  copilot_runner_token="${HAS_GH_AUTH_TOKEN}"
fi
if [[ -z "${copilot_runner_token}" && -n "${FUGUE_GH_AUTH_TOKEN:-}" ]]; then
  copilot_runner_token="${FUGUE_GH_AUTH_TOKEN}"
fi
if [[ -z "${copilot_runner_token}" && -n "${GH_AUTH_TOKEN:-}" ]]; then
  copilot_runner_token="${GH_AUTH_TOKEN}"
fi
if [[ -z "${copilot_runner_token}" ]]; then
  if command -v gh >/dev/null 2>&1; then
    copilot_runner_token="$(gh auth token 2>/dev/null || true)"
  fi
fi
copilot_runner_token_type="$(detect_token_type "${copilot_runner_token}")"
copilot_runner_available="false"
copilot_cli_override="$(normalize_optional_bool "${HAS_COPILOT_CLI:-${FUGUE_HAS_COPILOT_CLI:-}}" || true)"
if [[ -n "${copilot_cli_override}" ]]; then
  copilot_runner_available="${copilot_cli_override}"
elif [[ "${execution_profile}" == "local-direct" && "${claude_assist_execution_policy}" == "direct" ]]; then
  copilot_runner_available="false"
elif command -v "${copilot_runner_bin}" >/dev/null 2>&1; then
  copilot_runner_available="true"
fi
copilot_allow_all_tools="$(normalize_optional_bool "${COPILOT_ALLOW_ALL_TOOLS:-true}" || true)"
if [[ -z "${copilot_allow_all_tools}" ]]; then
  copilot_allow_all_tools="true"
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
    --arg fallback_used "${fallback_used}" \
    --arg missing_lane "${missing_lane}" \
    --arg fallback_provider "${fallback_provider}" \
    --arg fallback_reason "${fallback_reason}" \
    --arg metered_reason "${metered_reason}" \
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
      fallback_used:($fallback_used == "true"),
      missing_lane:(if $missing_lane == "" then null else $missing_lane end),
      fallback_provider:(if $fallback_provider == "" then null else $fallback_provider end),
      fallback_reason:(if $fallback_reason == "" then null else $fallback_reason end),
      metered_reason:(if $metered_reason == "none" then null else $metered_reason end),
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
chmod 600 "${schema_file}"
cat > "${schema_file}" <<'JSON'
{"type":"object","properties":{"risk":{"type":"string"},"approve":{"type":"boolean"},"findings":{"type":"array","items":{"type":"string"}},"recommendation":{"type":"string"},"rationale":{"type":"string"}},"required":["risk","approve","findings","recommendation","rationale"],"additionalProperties":false}
JSON

tmp_dir="$(mktemp -d)"
chmod 700 "${tmp_dir}"
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
  filter_known_cli_noise_file "${err_file}"

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
  local teams_mode="false"
  local permission_flag=""
  local -a claude_cmd
  local prompt
  if [[ "${AGENT_NAME:-}" == "claude-teams-executor" || "${AGENT_ROLE:-}" == "teams-executor" ]]; then
    teams_mode="true"
  fi
  prompt="${sys_prompt}

${user_prompt}

Return ONLY valid JSON."
  if [[ "${teams_mode}" == "true" ]]; then
    prompt="${prompt}

Claude Teams bounded mode is active. Work as a narrow collaboration executor and return handoff-ready JSON only."
  fi
  configured_session_id="$(echo "${CLAUDE_SESSION_ID:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  permission_flag="$(detect_claude_permission_flag)"
  claude_cmd=(
    claude
    --print
    --output-format json
    --model "${model}"
  )
  if [[ "${permission_flag}" == "dangerously-skip-permissions" ]]; then
    claude_cmd+=("--dangerously-skip-permissions")
  elif [[ "${permission_flag}" == "permission-mode" ]]; then
    claude_cmd+=("--permission-mode" "bypassPermissions")
  fi
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
  filter_known_cli_noise_file "${err_file}"

  append_attempt "claude" "${model}" "exit${rc}"
  if [[ "${rc}" -ne 0 ]]; then
    claude_failure_note="$(extract_claude_error_message "${err_file}")"
    if [[ -z "${claude_failure_note}" ]]; then
      claude_failure_note="Claude CLI failed with exit code ${rc}."
    fi
    return 1
  fi
  if [[ ! -s "${out_file}" ]]; then
    append_attempt "claude" "${model}" "empty"
    claude_failure_note="Claude CLI returned empty output."
    return 1
  fi

  local result_text
  result_text="$(jq -r '.result // ""' "${out_file}" 2>/dev/null || true)"
  if [[ -z "${result_text}" ]]; then
    result_text="$(cat "${out_file}")"
  fi
  if ! parsed="$(extract_json_object "${result_text}")"; then
    append_attempt "claude" "${model}" "parse-failed"
    claude_failure_note="Claude CLI returned non-JSON output."
    return 1
  fi
  session_id="$(jq -r '.session_id // empty' "${out_file}" 2>/dev/null || true)"
  if [[ -z "${session_id}" && -n "${configured_session_id}" ]]; then
    session_id="${configured_session_id}"
  fi

  chosen_model="${model}"
  effective_provider="claude"
  if [[ "${teams_mode}" == "true" ]]; then
    execution_route="claude-cli-teams-bounded"
  else
    execution_route="claude-cli"
  fi
  http_code="cli:0"
  claude_failure_note=""
  append_attempt "claude" "${model}" "ok"
  return 0
}

extract_claude_error_message() {
  local file_path="${1:-claude-response.stderr}"
  if [[ ! -s "${file_path}" ]]; then
    return 0
  fi
  sed -E 's/\x1b\[[0-9;]*m//g' "${file_path}" \
    | tr '\r' '\n' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | awk 'NF { print; exit }'
}

extract_copilot_error_message() {
  local file_path="${1:-copilot-response.stderr}"
  if [[ ! -s "${file_path}" ]]; then
    return 0
  fi
  sed -E 's/\x1b\[[0-9;]*m//g' "${file_path}" \
    | tr '\r' '\n' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | awk 'NF { print; exit }'
}

execute_copilot_claude() {
  local requested_model="$1"
  local out_file="${tmp_dir}/copilot-response.txt"
  local err_file="${tmp_dir}/copilot-response.stderr"
  local prompt parsed_output
  local -a copilot_cmd

  prompt="SYSTEM:
${sys_prompt}

USER:
${user_prompt}

Return ONLY valid JSON."
  if [[ "${AGENT_NAME:-}" == "claude-teams-executor" || "${AGENT_ROLE:-}" == "teams-executor" ]]; then
    prompt="${prompt}

Claude Teams bounded mode is active. Work as a narrow collaboration executor and return handoff-ready JSON only."
  fi

  if [[ -z "${copilot_runner_token}" ]]; then
    copilot_failure_note="Copilot CLI authentication token is missing."
    append_attempt "copilot-cli" "${requested_model}" "missing-token"
    return 1
  fi
  if [[ "${copilot_runner_token_type}" == "classic_pat" || "${copilot_runner_token_type}" == "app_installation" ]]; then
    copilot_failure_note="Copilot CLI token type is unsupported (${copilot_runner_token_type})."
    append_attempt "copilot-cli" "${requested_model}" "unsupported-token-type"
    return 1
  fi

  if [[ "${copilot_runner_bin}" == npx:* ]]; then
    copilot_cmd=(npx --yes "${copilot_runner_bin#npx:}" -p "${prompt}")
  elif command -v "${copilot_runner_bin}" >/dev/null 2>&1; then
    copilot_cmd=("${copilot_runner_bin}" -p "${prompt}")
  elif command -v npx >/dev/null 2>&1; then
    copilot_cmd=(npx --yes "${copilot_npx_package}" -p "${prompt}")
  else
    copilot_failure_note="Copilot CLI launcher is unavailable."
    append_attempt "copilot-cli" "${requested_model}" "launcher-unavailable"
    return 1
  fi
  if [[ "${copilot_allow_all_tools}" == "true" ]]; then
    copilot_cmd+=(--allow-all-tools)
  fi

  set +e
  GH_TOKEN="${copilot_runner_token}" \
  GITHUB_TOKEN="${copilot_runner_token}" \
    run_with_timeout "${subscription_timeout_sec}" "${copilot_cmd[@]}" >"${out_file}" 2>"${err_file}"
  local rc=$?
  set -e
  filter_known_cli_noise_file "${err_file}"

  append_attempt "copilot-cli" "${requested_model}" "exit${rc}"
  if [[ "${rc}" -ne 0 || ! -s "${out_file}" ]]; then
    copilot_failure_note="$(extract_copilot_error_message "${err_file}")"
    if [[ -z "${copilot_failure_note}" ]]; then
      copilot_failure_note="Copilot CLI failed with exit code ${rc}."
    fi
    return 1
  fi
  if ! parsed_output="$(extract_json_object "$(cat "${out_file}")")"; then
    append_attempt "copilot-cli" "${requested_model}" "parse-failed"
    copilot_failure_note="Copilot CLI returned non-JSON output."
    return 1
  fi

  parsed="${parsed_output}"
  copilot_failure_note=""
  chosen_model="${requested_model}"
  effective_provider="claude"
  execution_route="claude-via-copilot-cli"
  http_code="cli:0"
  append_attempt "copilot-cli" "${requested_model}" "ok"
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
  local err_file="${tmp_dir}/gemini-${model}-stderr.log"
  local -a gemini_cmd

  if [[ "${gemini_runner_available}" == "true" ]]; then
    gemini_cmd=(
      gemini
      --model "${model}"
      --output-format json
      "SYSTEM:
${sys_prompt}

USER:
${user_prompt}

Return ONLY valid JSON."
    )

    set +e
    run_with_timeout "${subscription_timeout_sec}" \
      "${gemini_cmd[@]}" >"${out_file}" 2>"${err_file}"
    local rc=$?
    set -e
    filter_known_cli_noise_file "${err_file}"

    append_attempt "gemini-cli" "${model}" "exit${rc}"
    if [[ "${rc}" -eq 0 && -s "${out_file}" ]]; then
      content="$(jq -r '.result // .response // .text // .content // empty' "${out_file}" 2>/dev/null || true)"
      if [[ -z "${content}" ]]; then
        content="$(cat "${out_file}")"
      fi
      if parsed="$(extract_json_object "${content}")"; then
        chosen_model="${model}"
        effective_provider="gemini"
        execution_route="gemini-cli"
        http_code="cli:0"
        append_attempt "gemini-cli" "${model}" "ok"
        return 0
      fi
      append_attempt "gemini-cli" "${model}" "parse-failed"
    fi
  fi

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

execute_xai_model() {
  local model="$1"
  local out_file="${tmp_dir}/xai-${model}-response.json"
  local req content

  req="$(jq -n \
    --arg m "${model}" \
    --arg s "${sys_prompt}" \
    --arg u "${user_prompt}" \
    '{model:$m,messages:[{role:"system",content:$s},{role:"user",content:$u}],temperature:0.1}')"

  set +e
  http_code="$(curl -sS -o "${out_file}" -w "%{http_code}" "https://api.x.ai/v1/chat/completions" \
    --connect-timeout 10 --max-time 60 --retry 2 \
    -H "Authorization: Bearer ${XAI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "${req}")"
  local rc=$?
  set -e

  append_attempt "xai" "${model}" "exit${rc}-http${http_code}"
  if [[ "${rc}" -ne 0 || "${http_code}" != "200" ]]; then
    return 1
  fi

  content="$(jq -r '.choices[0].message.content // ""' "${out_file}" 2>/dev/null || true)"
  if [[ -z "${content}" ]]; then
    append_attempt "xai" "${model}" "empty"
    return 1
  fi
  if ! parsed="$(extract_json_object "${content}")"; then
    append_attempt "xai" "${model}" "parse-failed"
    return 1
  fi

  chosen_model="${model}"
  effective_provider="xai"
  execution_route="xai-api"
  append_attempt "xai" "${model}" "ok"
  return 0
}

execute_metered_specialist_fallback() {
  local missing_provider="$1"
  local reason="$2"
  local ok="false"
  if [[ "${metered_reason}" != "overflow" && "${metered_reason}" != "tie-break" ]]; then
    return 1
  fi

  if [[ -n "${GEMINI_API_KEY:-}" || "${gemini_runner_available}" == "true" ]]; then
    local gemini_candidates=("${gemini_model}")
    if [[ -n "${gemini_fallback_model}" && "${gemini_fallback_model}" != "${gemini_model}" ]]; then
      gemini_candidates+=("${gemini_fallback_model}")
    fi
    local gm
    for gm in "${gemini_candidates[@]}"; do
      if execute_gemini_model "${gm}"; then
        mark_missing_lane "${missing_provider}"
        mark_fallback "gemini" "${reason}"
        ok="true"
        break
      fi
    done
  fi

  if [[ "${ok}" != "true" && -n "${XAI_API_KEY:-}" ]]; then
    if execute_xai_model "${xai_model}"; then
      mark_missing_lane "${missing_provider}"
      mark_fallback "xai" "${reason}"
      ok="true"
    fi
  fi

  [[ "${ok}" == "true" ]]
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
  candidates=()
  append_unique_candidate "${MODEL}"
  append_unique_candidate "${claude_opus_model}"
  ok="false"
  if [[ "${claude_runner_available}" == "true" ]]; then
    for m in "${candidates[@]}"; do
      if execute_claude_model "${m}"; then
        ok="true"
        break
      fi
    done
  elif [[ "${strict_opus_assist_direct}" == "true" && "${AGENT_NAME}" == "claude-opus-assist" ]]; then
    echo "Strict guard violation: claude-opus-assist requires claude CLI, but claude command is not available." >&2
    exit 43
  fi
  if [[ "${ok}" != "true" && "${strict_opus_assist_direct}" != "true" && "${copilot_runner_available}" == "true" ]]; then
    if execute_copilot_claude "${MODEL}"; then
      mark_missing_lane "claude"
      mark_fallback "copilot" "claude-cli->copilot-cli"
      ok="true"
    fi
  fi
  if [[ "${ok}" != "true" ]]; then
    if [[ "${strict_opus_assist_direct}" != "true" ]] && execute_metered_specialist_fallback "claude" "claude-lane->metered-${metered_reason}"; then
      ok="true"
    fi
  fi
  if [[ "${ok}" != "true" ]]; then
    if [[ "${strict_opus_assist_direct}" == "true" && "${AGENT_NAME}" == "claude-opus-assist" ]]; then
      echo "Strict guard violation: claude-opus-assist must execute via claude CLI with model=${claude_opus_model}." >&2
      echo "Observed provider=${effective_provider} model=${chosen_model} http=${http_code}" >&2
      echo "Attempt trace=${attempt_trace}" >&2
      exit 43
    fi
    if [[ "${claude_runner_available}" != "true" && "${copilot_runner_available}" != "true" ]]; then
      write_skipped_result \
        "Skipped: subscription-cli mode requires Claude CLI or Copilot CLI for Claude lanes" \
        "Install/login Claude CLI, or configure Copilot CLI with a supported token" \
        "Neither claude executable nor Copilot CLI was available" \
        "claude-cli-and-copilot-unavailable"
    fi
    if [[ "${claude_runner_available}" != "true" && "${copilot_runner_available}" == "true" ]]; then
      write_skipped_result \
        "Skipped: Copilot CLI failed to return valid JSON for Claude lane in subscription mode" \
        "Check Copilot CLI auth, launcher, and supported token type on the worker host" \
        "${copilot_failure_note:-Copilot CLI did not produce a valid JSON result}" \
        "claude-via-copilot-cli-failed"
    fi
    write_skipped_result \
      "Skipped: Claude lane failed in subscription mode" \
      "Check Claude CLI login/model availability and Copilot CLI continuity auth on the worker host" \
      "$(if [[ -n "${claude_failure_note}" || -n "${copilot_failure_note}" ]]; then printf '%s%s%s' "${claude_failure_note:-All claude model attempts failed or returned non-JSON output}" "$(if [[ -n "${claude_failure_note}" && -n "${copilot_failure_note}" ]]; then printf '; '; fi)" "$(if [[ -n "${copilot_failure_note}" ]]; then printf 'Copilot CLI preflight failed: %s' "${copilot_failure_note}"; fi)"; else printf 'All claude model attempts failed or returned non-JSON output'; fi)" \
      "claude-cli-failed"
  fi
elif [[ "${PROVIDER}" == "glm" ]]; then
  ok="false"
  if [[ -z "${ZAI_API_KEY:-}" ]]; then
    mark_missing_lane "glm"
    if execute_metered_specialist_fallback "glm" "glm-lane->metered-${metered_reason}"; then
      ok="true"
    else
      write_skipped_result \
        "Skipped: GLM lane requires ZAI_API_KEY in subscription hybrid mode" \
        "Set ZAI_API_KEY to enable GLM baseline voters" \
        "GLM API credential was not configured" \
        "glm-api-key-missing"
    fi
  fi
  if [[ "${ok}" != "true" ]]; then
    candidates=()
    append_unique_candidate "${MODEL}"
    append_unique_candidate "${glm_model}"
    for m in "${candidates[@]}"; do
      if execute_glm_model "${m}"; then
        ok="true"
        break
      fi
    done
  fi
  if [[ "${ok}" != "true" ]]; then
    mark_missing_lane "glm"
    if ! execute_metered_specialist_fallback "glm" "glm-lane->metered-${metered_reason}"; then
      write_skipped_result \
        "Skipped: GLM API failed to return valid JSON in subscription hybrid mode" \
        "Check ZAI_API_KEY and GLM endpoint availability" \
        "All GLM model attempts failed or returned non-JSON output" \
        "glm-api-failed"
    fi
  fi
elif [[ "${PROVIDER}" == "gemini" ]]; then
  if [[ "${metered_reason}" == "none" ]]; then
    write_skipped_result \
      "Skipped: Gemini lane requires metered_reason=overflow|tie-break" \
      "Set METERED_PROVIDER_REASON=overflow or tie-break before enabling Gemini lanes" \
      "Gemini is reserved for metered overflow/tie-break usage in subscription mode" \
      "gemini-metered-reason-missing"
  fi
  gemini_cli_preferred="$(echo "${FUGUE_GEMINI_CLI_FIRST:-true}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${gemini_cli_preferred}" != "true" ]]; then
    gemini_cli_preferred="false"
  fi
  if [[ "${gemini_cli_preferred}" != "true" && -z "${GEMINI_API_KEY:-}" ]]; then
    write_skipped_result \
      "Skipped: Gemini lane requires GEMINI_API_KEY in subscription hybrid mode" \
      "Set GEMINI_API_KEY to enable design-oriented Gemini voter" \
      "Gemini API credential was not configured" \
      "gemini-api-key-missing"
  elif [[ "${gemini_runner_available}" != "true" && -z "${GEMINI_API_KEY:-}" ]]; then
    write_skipped_result \
      "Skipped: Gemini lane requires Gemini CLI login or GEMINI_API_KEY" \
      "Login to Gemini CLI for subscription/free-first use, or set GEMINI_API_KEY for API fallback" \
      "Neither Gemini CLI nor API credential was available" \
      "gemini-cli-and-api-unavailable"
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
elif [[ "${PROVIDER}" == "xai" ]]; then
  if [[ "${metered_reason}" == "none" ]]; then
    write_skipped_result \
      "Skipped: xAI lane requires metered_reason=overflow|tie-break" \
      "Set METERED_PROVIDER_REASON=overflow or tie-break before enabling xAI lanes" \
      "xAI is reserved for metered overflow/tie-break usage in subscription mode" \
      "xai-metered-reason-missing"
  fi
  if [[ -z "${XAI_API_KEY:-}" ]]; then
    write_skipped_result \
      "Skipped: xAI lane requires XAI_API_KEY" \
      "Set XAI_API_KEY to enable xAI tie-break lanes" \
      "xAI API credential was not configured" \
      "xai-api-key-missing"
  fi
  if ! execute_xai_model "${xai_model}"; then
    write_skipped_result \
      "Skipped: xAI API failed to return valid JSON in subscription hybrid mode" \
      "Check XAI_API_KEY and xAI endpoint availability" \
      "All xAI model attempts failed or returned non-JSON output" \
      "xai-api-failed"
  fi
else
  write_skipped_result \
    "Skipped: provider ${PROVIDER} is not supported in subscription-cli mode" \
    "Use codex/claude/glm/gemini/xai lanes for this execution profile" \
    "subscription hybrid mode only supports codex-cli, claude-cli, glm-api, gemini, and xai lanes" \
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
  --arg copilot_failure "${copilot_failure_note}" \
  --arg fallback_used "${fallback_used}" \
  --arg missing_lane "${missing_lane}" \
  --arg fallback_provider "${fallback_provider}" \
  --arg fallback_reason "${fallback_reason}" \
  --arg metered_reason "${metered_reason}" \
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
    copilot_failure:(if $copilot_failure == "" then null else $copilot_failure end),
    fallback_used:($fallback_used == "true"),
    missing_lane:(if $missing_lane == "" then null else $missing_lane end),
    fallback_provider:(if $fallback_provider == "" then null else $fallback_provider end),
    fallback_reason:(if $fallback_reason == "" then null else $fallback_reason end),
    metered_reason:(if $metered_reason == "none" then null else $metered_reason end),
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
