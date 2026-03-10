#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY="${ROOT_DIR}/scripts/lib/mcp-adapter-policy.sh"
KERNEL_POLICY="${ROOT_DIR}/scripts/lib/mcp-kernel-adapter.sh"
REST_BRIDGE="${ROOT_DIR}/scripts/lib/mcp-rest-bridge.sh"
SKILL_CLI="${ROOT_DIR}/scripts/lib/skill-cli-adapter.sh"

adapter_id=""
action="resolve"
execution_engine="local"
session_provider="none"
format="json"
dry_run="false"
channel=""
text=""
payload=""
payload_file=""
input_file=""
output_file=""
import_mode="batch"
allow_fallback="true"

policy_json='{}'
route_json='{}'
details_json='{}'

usage() {
  cat <<'EOF'
Usage: mcp-adapter-exec.sh --adapter <id> [options]

Options:
  --adapter <id>                    Adapter ID from config/integrations/mcp-adapters.json
  --action <resolve|smoke|notify|export|import|clear|whoami|list-projects|server-command>
                                     Action to perform (default: resolve)
  --execution-engine <subscription|harness|api|local>
                                     Execution context hint (default: local)
  --session-provider <claude|none>  Active session provider (default: none)
  --format <json|env>               Output format (default: json)
  --dry-run                         Emit the resolved request without external side effects
  --channel <id>                    Channel for Slack notify
  --text <text>                     Message text for Slack notify
  --payload <json>                  Raw payload JSON for notify/import actions
  --payload-file <path>             Read payload JSON from file
  --in <path>                       Input file for import
  --out <path>                      Output file for export
  --mode <batch|sync>               Import mode for Excalidraw (default: batch)
  --require-native                  Fail instead of returning claude-session fallback
  -h, --help                        Show help
EOF
}

json_result() {
  local status="$1"
  local message="$2"
  jq -cn \
    --arg adapter_id "${adapter_id}" \
    --arg action "${action}" \
    --arg status "${status}" \
    --arg message "${message}" \
    --argjson policy "${policy_json}" \
    --argjson route "${route_json}" \
    --argjson details "${details_json}" \
    '{
      adapter_id:$adapter_id,
      action:$action,
      status:$status,
      message:$message,
      policy:$policy,
      route:$route,
      details:$details
    }'
}

env_result() {
  local status="$1"
  local message="$2"
  printf 'adapter_id=%q\n' "${adapter_id}"
  printf 'action=%q\n' "${action}"
  printf 'status=%q\n' "${status}"
  printf 'message=%q\n' "${message}"
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

run_node_script() {
  local script_path="$1"
  shift
  ensure_command node
  node "${script_path}" "$@"
}

read_json_file() {
  local path="$1"
  jq -c '.' "${path}"
}

resolve_excalidraw_url() {
  if [[ -n "${EXCALIDRAW_SERVER_URL:-}" ]]; then
    printf '%s\n' "${EXCALIDRAW_SERVER_URL}"
    return 0
  fi
  if [[ -n "${EXPRESS_SERVER_URL:-}" ]]; then
    printf '%s\n' "${EXPRESS_SERVER_URL}"
    return 0
  fi

  local candidates=(
    "http://localhost:3001"
    "http://localhost:3000"
  )
  local candidate=""
  for candidate in "${candidates[@]}"; do
    if curl -sS -I "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  printf '%s\n' "http://localhost:3001"
}

slack_default_payload() {
  jq -cn \
    --arg channel "${channel}" \
    --arg text "${text:-Kernel Slack adapter message}" \
    'if $channel == "" then {text:$text} else {channel:$channel,text:$text} end'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --adapter)
      adapter_id="${2:-}"
      shift 2
      ;;
    --action)
      action="${2:-}"
      shift 2
      ;;
    --execution-engine)
      execution_engine="${2:-}"
      shift 2
      ;;
    --session-provider)
      session_provider="${2:-}"
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
    --payload-file)
      payload_file="${2:-}"
      shift 2
      ;;
    --in)
      input_file="${2:-}"
      shift 2
      ;;
    --out)
      output_file="${2:-}"
      shift 2
      ;;
    --mode)
      import_mode="${2:-}"
      shift 2
      ;;
    --require-native)
      allow_fallback="false"
      shift
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

if [[ -z "${adapter_id}" ]]; then
  echo "Error: --adapter is required" >&2
  exit 2
fi

if [[ -n "${payload_file}" ]]; then
  payload="$(cat "${payload_file}")"
fi

policy_json="$("${POLICY}" --adapter "${adapter_id}" --execution-engine "${execution_engine}" --session-provider "${session_provider}" --format json)"
provider="$(echo "${policy_json}" | jq -r '.provider')"
route="$(echo "${policy_json}" | jq -r '.route')"
available="$(echo "${policy_json}" | jq -r '.available')"
fallback_route="$(echo "${policy_json}" | jq -r '.fallback_route')"

if [[ "${route}" == "kernel-adapter" ]]; then
  route_json="$("${KERNEL_POLICY}" --provider "${provider}" --session-provider "${session_provider}" --format json)"
fi

if [[ "${action}" == "resolve" ]]; then
  emit_result "ok" "resolved"
  exit 0
fi

if [[ "${available}" != "true" ]]; then
  details_json="$(jq -cn --arg route "${route}" --arg fallback_route "${fallback_route}" '{route:$route,fallback_route:$fallback_route}')"
  emit_result "error" "adapter unavailable"
  exit 3
fi

if [[ "${route}" == "claude-session" ]]; then
  details_json="$(jq -cn --arg provider "${provider}" --arg route "${route}" '{provider:$provider,route:$route,handoff:"claude-session"}')"
  if [[ "${allow_fallback}" == "true" ]]; then
    emit_result "fallback" "handoff to claude-session required"
    exit 0
  fi
  emit_result "error" "native route required but only claude-session is available"
  exit 4
fi

case "${route}" in
  rest-bridge)
    if [[ "${action}" != "smoke" ]]; then
      details_json="$(jq -cn --arg route "${route}" '{route:$route,supported_actions:["smoke"]}')"
      emit_result "error" "unsupported action for rest bridge"
      exit 5
    fi
    if [[ "${dry_run}" == "true" ]]; then
      details_json="$(jq -cn --arg provider "${provider}" '{provider:$provider,bridge:"mcp-rest-bridge"}')"
      emit_result "ok" "rest bridge dry-run"
      exit 0
    fi
    bridge_output="$("${REST_BRIDGE}" --smoke)"
    details_json="$(echo "${bridge_output}" | jq -c '.')"
    emit_result "ok" "rest bridge smoke passed"
    ;;
  skill-cli)
    skill_args=(
      --provider "${provider}"
      --action "${action}"
      --session-provider "${session_provider}"
      --format json
    )
    if [[ "${dry_run}" == "true" ]]; then
      skill_args+=(--dry-run)
    fi
    if [[ -n "${channel}" ]]; then
      skill_args+=(--channel "${channel}")
    fi
    if [[ -n "${text}" ]]; then
      skill_args+=(--text "${text}")
    fi
    if [[ -n "${payload}" ]]; then
      skill_args+=(--payload "${payload}")
    fi
    skill_output="$("${SKILL_CLI}" "${skill_args[@]}")"
    details_json="$(echo "${skill_output}" | jq -c '{provider,route,backend,reason,fallback_route,details}')"
    skill_status="$(echo "${skill_output}" | jq -r '.status')"
    skill_message="$(echo "${skill_output}" | jq -r '.message')"
    emit_result "${skill_status}" "${skill_message}"
    if [[ "${skill_status}" != "ok" ]]; then
      exit 6
    fi
    ;;
  kernel-adapter)
    case "${provider}" in
      pencil)
        pencil_wrapper="$(echo "${route_json}" | jq -r '.backend_hint')"
        case "${action}" in
          smoke)
            if [[ "${dry_run}" == "true" ]]; then
              details_json="$(jq -cn --arg wrapper "${pencil_wrapper}" '{wrapper:$wrapper,probe:"lsof Pencil LISTEN",ready:false}')"
              emit_result "ok" "pencil dry-run"
              exit 0
            fi
            ensure_command lsof
            pencil_port="$(lsof -i -P 2>/dev/null | awk '/Pencil.*LISTEN/ {print $9}' | head -1 | sed -E 's/.*:([0-9]+)$/\1/')"
            if [[ -n "${pencil_port}" ]]; then
              details_json="$(jq -cn --arg wrapper "${pencil_wrapper}" --arg port "${pencil_port}" '{wrapper:$wrapper,ready:true,port:($port|tonumber)}')"
              emit_result "ok" "pencil adapter ready"
              exit 0
            fi
            details_json="$(jq -cn --arg wrapper "${pencil_wrapper}" '{wrapper:$wrapper,ready:false}')"
            emit_result "ok" "pencil adapter available but Pencil is not running"
            ;;
          server-command)
            details_json="$(jq -cn --arg wrapper "${pencil_wrapper}" '{wrapper:$wrapper,launch_mode:"stdio"}')"
            emit_result "ok" "pencil command resolved"
            ;;
          *)
            details_json="$(jq -cn '{supported_actions:["smoke","server-command"]}')"
            emit_result "error" "unsupported pencil action"
            exit 5
            ;;
        esac
        ;;
      excalidraw)
        excalidraw_health_script="$(echo "${route_json}" | jq -r '.backend_hint')"
        excalidraw_root="$(dirname "${excalidraw_health_script}")"
        excalidraw_url="$(resolve_excalidraw_url)"
        case "${action}" in
          smoke)
            if [[ "${dry_run}" == "true" ]]; then
              details_json="$(jq -cn --arg script "${excalidraw_health_script}" --arg url "${excalidraw_url}" '{script:$script,url:$url}')"
              emit_result "ok" "excalidraw dry-run"
              exit 0
            fi
            smoke_output="$(run_node_script "${excalidraw_health_script}" --url "${excalidraw_url}")"
            details_json="$(jq -cn --arg url "${excalidraw_url}" --arg output "${smoke_output}" '{url:$url,health:$output}')"
            emit_result "ok" "excalidraw smoke passed"
            ;;
          export)
            export_script="${excalidraw_root}/export-elements.cjs"
            [[ -n "${output_file}" ]] || { emit_result "error" "--out is required for export"; exit 2; }
            if [[ "${dry_run}" == "true" ]]; then
              details_json="$(jq -cn --arg script "${export_script}" --arg url "${excalidraw_url}" --arg out "${output_file}" '{script:$script,url:$url,out:$out}')"
              emit_result "ok" "excalidraw export dry-run"
              exit 0
            fi
            export_output="$(run_node_script "${export_script}" --url "${excalidraw_url}" --out "${output_file}")"
            details_json="$(jq -cn --arg out "${output_file}" --arg output "${export_output}" '{out:$out,output:$output}')"
            emit_result "ok" "excalidraw export completed"
            ;;
          import)
            import_script="${excalidraw_root}/import-elements.cjs"
            [[ -n "${input_file}" ]] || { emit_result "error" "--in is required for import"; exit 2; }
            if [[ "${dry_run}" == "true" ]]; then
              details_json="$(jq -cn --arg script "${import_script}" --arg url "${excalidraw_url}" --arg in_file "${input_file}" --arg mode "${import_mode}" '{script:$script,url:$url,input:$in_file,mode:$mode}')"
              emit_result "ok" "excalidraw import dry-run"
              exit 0
            fi
            import_output="$(run_node_script "${import_script}" --url "${excalidraw_url}" --in "${input_file}" --mode "${import_mode}")"
            details_json="$(jq -cn --arg in_file "${input_file}" --arg output "${import_output}" '{input:$in_file,output:$output}')"
            emit_result "ok" "excalidraw import completed"
            ;;
          clear)
            clear_script="${excalidraw_root}/clear-canvas.cjs"
            if [[ "${dry_run}" == "true" ]]; then
              details_json="$(jq -cn --arg script "${clear_script}" --arg url "${excalidraw_url}" '{script:$script,url:$url}')"
              emit_result "ok" "excalidraw clear dry-run"
              exit 0
            fi
            clear_output="$(run_node_script "${clear_script}" --url "${excalidraw_url}")"
            details_json="$(jq -cn --arg output "${clear_output}" '{output:$output}')"
            emit_result "ok" "excalidraw canvas cleared"
            ;;
          *)
            details_json="$(jq -cn '{supported_actions:["smoke","export","import","clear"]}')"
            emit_result "error" "unsupported excalidraw action"
            exit 5
            ;;
        esac
        ;;
      slack)
        if [[ "${action}" == "smoke" ]]; then
          if [[ "${dry_run}" == "true" ]]; then
            details_json="$(jq -cn --arg has_webhook "${SLACK_WEBHOOK_URL:+true}" --arg has_token "${SLACK_BOT_TOKEN:+true}" '{has_webhook:($has_webhook=="true"),has_bot_token:($has_token=="true")}')"
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
          if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
            details_json="$(jq -cn '{mode:"webhook-only",safe_live_probe:false}')"
            emit_result "ok" "slack adapter available (webhook-only; no safe live smoke)"
            exit 0
          fi
          emit_result "error" "slack credentials missing"
          exit 6
        fi

        if [[ "${action}" != "notify" ]]; then
          details_json="$(jq -cn '{supported_actions:["smoke","notify"]}')"
          emit_result "error" "unsupported slack action"
          exit 5
        fi

        slack_payload="${payload}"
        if [[ -z "${slack_payload}" ]]; then
          slack_payload="$(slack_default_payload)"
        fi

        if [[ "${dry_run}" == "true" ]]; then
          details_json="$(jq -cn --arg channel "${channel}" --argjson payload "${slack_payload}" '{channel:$channel,payload:$payload}')"
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
      vercel)
        vercel_api_url="${VERCEL_API_URL:-https://api.vercel.com}"
        case "${action}" in
          smoke|whoami)
            if [[ "${dry_run}" == "true" ]]; then
              details_json="$(jq -cn --arg api "${vercel_api_url}" --arg token "${VERCEL_TOKEN:+true}" '{api:$api,has_token:($token=="true")}')"
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
            if command -v vercel >/dev/null 2>&1; then
              vercel_output="$(vercel whoami 2>&1)"
              details_json="$(jq -cn --arg output "${vercel_output}" '{output:$output,mode:"cli"}')"
              emit_result "ok" "vercel cli whoami completed"
              exit 0
            fi
            emit_result "error" "vercel credentials missing"
            exit 6
            ;;
          list-projects)
            if [[ "${dry_run}" == "true" ]]; then
              details_json="$(jq -cn --arg api "${vercel_api_url}" '{api:$api,endpoint:"/v9/projects"}')"
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
            exit 0
            ;;
          *)
            details_json="$(jq -cn '{supported_actions:["smoke","whoami","list-projects"]}')"
            emit_result "error" "unsupported vercel action"
            exit 5
            ;;
        esac
        ;;
      *)
        emit_result "error" "unknown kernel adapter provider"
        exit 5
        ;;
    esac
    ;;
  *)
    details_json="$(jq -cn --arg route "${route}" '{route:$route}')"
    emit_result "error" "unsupported route"
    exit 5
    ;;
esac
