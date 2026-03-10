#!/usr/bin/env bash
set -euo pipefail

provider=""
action="resolve"
session_provider="none"
format="json"
dry_run="false"
channel=""
text=""
payload=""

usage() {
  cat <<'EOF'
Usage: skill-cli-adapter.sh --provider <id> [options]

Options:
  --provider <slack|vercel>
  --action <resolve|smoke|notify|whoami|list-projects>
  --session-provider <claude|none>
  --format <json|env>
  --dry-run
  --channel <id>
  --text <text>
  --payload <json>
EOF
}

json_result() {
  local status="$1"
  local message="$2"
  jq -cn \
    --arg provider "${provider}" \
    --arg action "${action}" \
    --arg status "${status}" \
    --arg message "${message}" \
    --arg route "${route}" \
    --arg available "${available}" \
    --arg backend "${backend}" \
    --arg reason "${reason}" \
    --arg fallback_route "${fallback_route}" \
    --arg backend_hint "${backend_hint}" \
    --argjson details "${details_json}" \
    '{
      provider:$provider,
      action:$action,
      status:$status,
      message:$message,
      route:$route,
      available:($available == "true"),
      backend:$backend,
      reason:$reason,
      fallback_route:$fallback_route,
      backend_hint:$backend_hint,
      details:$details
    }'
}

env_result() {
  local status="$1"
  local message="$2"
  printf 'provider=%q\n' "${provider}"
  printf 'action=%q\n' "${action}"
  printf 'status=%q\n' "${status}"
  printf 'message=%q\n' "${message}"
  printf 'route=%q\n' "${route}"
  printf 'available=%q\n' "${available}"
  printf 'backend=%q\n' "${backend}"
  printf 'reason=%q\n' "${reason}"
  printf 'fallback_route=%q\n' "${fallback_route}"
  printf 'backend_hint=%q\n' "${backend_hint}"
}

emit_result() {
  local status="$1"
  local message="$2"
  if [[ "${format}" == "env" ]]; then
    env_result "${status}" "${message}"
  else
    json_result "${status}" "${message}"
  fi
}

ensure_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    details_json="$(jq -cn --arg missing_command "${cmd}" '{missing_command:$missing_command}')"
    emit_result "error" "missing command"
    exit 127
  fi
}

slack_default_payload() {
  jq -cn \
    --arg channel "${channel}" \
    --arg text "${text:-Kernel Slack adapter message}" \
    'if $channel == "" then {text:$text} else {channel:$channel,text:$text} end'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      provider="${2:-}"
      shift 2
      ;;
    --action)
      action="${2:-}"
      shift 2
      ;;
    --session-provider)
      session_provider="${2:-none}"
      shift 2
      ;;
    --format)
      format="${2:-json}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    --channel)
      channel="${2:-}"
      shift 2
      ;;
    --text)
      text="${2:-}"
      shift 2
      ;;
    --payload)
      payload="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

provider="$(echo "${provider}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
session_provider="$(echo "${session_provider:-none}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${session_provider}" != "claude" ]]; then
  session_provider="none"
fi

route="unavailable"
available="false"
backend="none"
reason="skill-cli-unavailable"
fallback_route="claude-session"
backend_hint="none"
details_json='{}'

case "${provider}" in
  slack)
    slack_skill_enabled="$(echo "${KERNEL_SLACK_SKILL_ENABLED:-true}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${slack_skill_enabled}" == "true" && ( -n "${SLACK_WEBHOOK_URL:-}" || -n "${SLACK_BOT_TOKEN:-}" ) ]]; then
      route="skill-cli"
      available="true"
      backend="slack-cli"
      reason="skill-slack-cli"
      backend_hint="${SLACK_WEBHOOK_URL:-${SLACK_BOT_TOKEN:+slack-bot-token}}"
    elif [[ "${session_provider}" == "claude" ]]; then
      route="claude-session"
      available="true"
      reason="fallback-to-claude-session"
    else
      reason="skill-slack-credentials-missing"
    fi
    ;;
  vercel)
    vercel_skill_enabled="$(echo "${KERNEL_VERCEL_SKILL_ENABLED:-true}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${vercel_skill_enabled}" == "true" && ( -n "${VERCEL_TOKEN:-}" || "$(command -v vercel >/dev/null 2>&1; printf %s "$?")" == "0" ) ]]; then
      route="skill-cli"
      available="true"
      backend="vercel-cli"
      reason="skill-vercel-cli"
      backend_hint="${VERCEL_PROJECT_ID:-${VERCEL_TEAM_ID:-vercel-api}}"
    elif [[ "${session_provider}" == "claude" ]]; then
      route="claude-session"
      available="true"
      reason="fallback-to-claude-session"
    else
      reason="skill-vercel-credentials-missing"
    fi
    ;;
  *)
    reason="unknown-provider"
    ;;
esac

if [[ "${action}" == "resolve" ]]; then
  emit_result "ok" "resolved"
  exit 0
fi

if [[ "${route}" == "claude-session" ]]; then
  details_json="$(jq -cn --arg provider "${provider}" '{provider:$provider,handoff:"claude-session"}')"
  emit_result "fallback" "handoff to claude-session required"
  exit 0
fi

if [[ "${available}" != "true" ]]; then
  details_json="$(jq -cn --arg provider "${provider}" '{provider:$provider}')"
  emit_result "error" "skill-cli adapter unavailable"
  exit 6
fi

case "${provider}" in
  slack)
    case "${action}" in
      smoke)
        if [[ "${dry_run}" == "true" ]]; then
          details_json="$(jq -cn --arg has_webhook "${SLACK_WEBHOOK_URL:+true}" --arg has_token "${SLACK_BOT_TOKEN:+true}" '{has_webhook:($has_webhook=="true"),has_bot_token:($has_token=="true"),mode:"skill-cli"}')"
          emit_result "ok" "slack dry-run"
          exit 0
        fi
        if [[ -n "${SLACK_BOT_TOKEN:-}" ]]; then
          ensure_command curl
          auth_response="$(curl -sS -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" https://slack.com/api/auth.test)"
          details_json="$(echo "${auth_response}" | jq -c '.')"
          [[ "$(echo "${auth_response}" | jq -r '.ok // false')" == "true" ]] || {
            emit_result "error" "slack auth.test failed"
            exit 6
          }
          emit_result "ok" "slack smoke passed"
          exit 0
        fi
        details_json="$(jq -cn '{mode:"webhook-only",safe_live_probe:false}')"
        emit_result "ok" "slack adapter available (webhook-only; no safe live smoke)"
        ;;
      notify)
        slack_payload="${payload}"
        if [[ -z "${slack_payload}" ]]; then
          slack_payload="$(slack_default_payload)"
        fi
        if [[ "${dry_run}" == "true" ]]; then
          details_json="$(jq -cn --arg channel "${channel}" --argjson payload "${slack_payload}" '{channel:$channel,payload:$payload,mode:"skill-cli"}')"
          emit_result "ok" "slack notify dry-run"
          exit 0
        fi
        if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
          ensure_command curl
          webhook_response="$(curl -sS -X POST -H "Content-Type: application/json" --data "${slack_payload}" "${SLACK_WEBHOOK_URL}")"
          details_json="$(jq -cn --arg response "${webhook_response}" '{response:$response,delivery:"webhook"}')"
          emit_result "ok" "slack webhook delivered"
          exit 0
        fi
        if [[ -n "${SLACK_BOT_TOKEN:-}" && -n "${channel}" ]]; then
          ensure_command curl
          post_response="$(curl -sS -X POST https://slack.com/api/chat.postMessage -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" -H "Content-Type: application/json" --data "${slack_payload}")"
          details_json="$(echo "${post_response}" | jq -c '.')"
          [[ "$(echo "${post_response}" | jq -r '.ok // false')" == "true" ]] || {
            emit_result "error" "slack chat.postMessage failed"
            exit 6
          }
          emit_result "ok" "slack message posted"
          exit 0
        fi
        emit_result "error" "slack notify requires SLACK_WEBHOOK_URL or SLACK_BOT_TOKEN+--channel"
        exit 6
        ;;
      *)
        details_json="$(jq -cn '{supported_actions:["resolve","smoke","notify"]}')"
        emit_result "error" "unsupported slack action"
        exit 5
        ;;
    esac
    ;;
  vercel)
    vercel_api_url="${VERCEL_API_URL:-https://api.vercel.com}"
    case "${action}" in
      smoke|whoami)
        if [[ "${dry_run}" == "true" ]]; then
          details_json="$(jq -cn --arg api "${vercel_api_url}" --arg token "${VERCEL_TOKEN:+true}" '{api:$api,has_token:($token=="true"),mode:"skill-cli"}')"
          emit_result "ok" "vercel dry-run"
          exit 0
        fi
        if [[ -n "${VERCEL_TOKEN:-}" ]]; then
          ensure_command curl
          vercel_response="$(curl -sS -H "Authorization: Bearer ${VERCEL_TOKEN}" "${vercel_api_url}/v2/user")"
          details_json="$(echo "${vercel_response}" | jq -c '.')"
          [[ "$(echo "${vercel_response}" | jq -r '.user.id // empty')" != "" ]] || {
            emit_result "error" "vercel whoami failed"
            exit 6
          }
          emit_result "ok" "vercel whoami passed"
          exit 0
        fi
        ensure_command vercel
        vercel_output="$(vercel whoami 2>&1)"
        details_json="$(jq -cn --arg output "${vercel_output}" '{output:$output,mode:"cli"}')"
        emit_result "ok" "vercel cli whoami completed"
        ;;
      list-projects)
        if [[ "${dry_run}" == "true" ]]; then
          details_json="$(jq -cn --arg api "${vercel_api_url}" '{api:$api,endpoint:"/v9/projects",mode:"skill-cli"}')"
          emit_result "ok" "vercel list-projects dry-run"
          exit 0
        fi
        [[ -n "${VERCEL_TOKEN:-}" ]] || {
          emit_result "error" "VERCEL_TOKEN is required for list-projects"
          exit 6
        }
        ensure_command curl
        projects_response="$(curl -sS -H "Authorization: Bearer ${VERCEL_TOKEN}" "${vercel_api_url}/v9/projects")"
        details_json="$(echo "${projects_response}" | jq -c '.')"
        emit_result "ok" "vercel projects listed"
        ;;
      *)
        details_json="$(jq -cn '{supported_actions:["resolve","smoke","whoami","list-projects"]}')"
        emit_result "error" "unsupported vercel action"
        exit 5
        ;;
    esac
    ;;
esac
