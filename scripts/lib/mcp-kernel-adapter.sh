#!/usr/bin/env bash
set -euo pipefail

provider=""
session_provider=""
format="env"

PENCIL_WRAPPER_DEFAULT="${HOME}/Dev/cursorvers/claude-config/scripts/pencil-mcp-wrapper.sh"
EXCALIDRAW_ROOT_DEFAULT="${HOME}/Dev/tmp/mcp_excalidraw/skills/excalidraw-skill/scripts"

usage() {
  cat <<'EOF'
Usage: mcp-kernel-adapter.sh --provider <id> [options]

Options:
  --provider <pencil|excalidraw|slack|vercel>
  --session-provider <claude|none>
  --format <env|json>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      provider="${2:-}"
      shift 2
      ;;
    --session-provider)
      session_provider="${2:-none}"
      shift 2
      ;;
    --format)
      format="${2:-env}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

provider="$(echo "${provider}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
session_provider="$(echo "${session_provider:-none}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${session_provider}" != "claude" ]]; then
  session_provider="none"
fi

pencil_wrapper="${KERNEL_PENCIL_WRAPPER:-${PENCIL_WRAPPER_DEFAULT}}"
excalidraw_script_root="${KERNEL_EXCALIDRAW_SCRIPT_ROOT:-${EXCALIDRAW_ROOT_DEFAULT}}"
excalidraw_health_script="${KERNEL_EXCALIDRAW_HEALTHCHECK_SCRIPT:-${excalidraw_script_root}/healthcheck.cjs}"

route="unavailable"
available="false"
backend="none"
reason="kernel-adapter-unavailable"
fallback_route="none"
backend_hint="none"

case "${provider}" in
  pencil)
    if [[ "$(echo "${KERNEL_PENCIL_ADAPTER_ENABLED:-true}" | tr '[:upper:]' '[:lower:]')" == "true" && -x "${pencil_wrapper}" ]]; then
      route="kernel-adapter"
      available="true"
      backend="pencil-wrapper"
      reason="kernel-pencil-adapter"
      backend_hint="${pencil_wrapper}"
    else
      reason="kernel-pencil-backend-missing"
    fi
    fallback_route="claude-session"
    ;;
  excalidraw)
    if [[ "$(echo "${KERNEL_EXCALIDRAW_ADAPTER_ENABLED:-true}" | tr '[:upper:]' '[:lower:]')" == "true" && -f "${excalidraw_health_script}" ]]; then
      route="kernel-adapter"
      available="true"
      backend="excalidraw-rest"
      reason="kernel-excalidraw-adapter"
      backend_hint="${excalidraw_health_script}"
    else
      reason="kernel-excalidraw-backend-missing"
    fi
    fallback_route="claude-session"
    ;;
  slack)
    slack_kernel_enabled="$(echo "${KERNEL_SLACK_ADAPTER_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${slack_kernel_enabled}" == "true" ]]; then
      route="kernel-adapter"
      available="true"
      backend="slack-api"
      reason="kernel-slack-adapter"
      backend_hint="${SLACK_WEBHOOK_URL:-${SLACK_BOT_TOKEN:+slack-bot-token}}"
    elif [[ "${session_provider}" != "claude" && ( -n "${SLACK_WEBHOOK_URL:-}" || -n "${SLACK_BOT_TOKEN:-}" ) ]]; then
      route="kernel-adapter"
      available="true"
      backend="slack-api"
      reason="kernel-slack-adapter-auto"
      backend_hint="${SLACK_WEBHOOK_URL:-${SLACK_BOT_TOKEN:+slack-bot-token}}"
    else
      fallback_route="claude-session"
    fi
    ;;
  vercel)
    vercel_kernel_enabled="$(echo "${KERNEL_VERCEL_ADAPTER_ENABLED:-false}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${vercel_kernel_enabled}" == "true" ]]; then
      route="kernel-adapter"
      available="true"
      backend="vercel-rest"
      reason="kernel-vercel-adapter"
      backend_hint="${VERCEL_PROJECT_ID:-${VERCEL_TEAM_ID:-vercel-api}}"
    elif [[ "${session_provider}" != "claude" && -n "${VERCEL_TOKEN:-}" ]]; then
      route="kernel-adapter"
      available="true"
      backend="vercel-rest"
      reason="kernel-vercel-adapter-auto"
      backend_hint="${VERCEL_PROJECT_ID:-${VERCEL_TEAM_ID:-vercel-api}}"
    else
      fallback_route="claude-session"
    fi
    ;;
  *)
    reason="unknown-provider"
    ;;
esac

if [[ "${available}" != "true" && "${fallback_route}" == "claude-session" && "${session_provider}" == "claude" ]]; then
  route="claude-session"
  available="true"
  reason="fallback-to-claude-session"
fi

if [[ "${format}" == "json" ]]; then
  jq -cn \
    --arg provider "${provider}" \
    --arg route "${route}" \
    --arg available "${available}" \
    --arg backend "${backend}" \
    --arg reason "${reason}" \
    --arg fallback_route "${fallback_route}" \
    --arg backend_hint "${backend_hint}" \
    '{
      provider:$provider,
      route:$route,
      available:($available == "true"),
      backend:$backend,
      reason:$reason,
      fallback_route:$fallback_route,
      backend_hint:$backend_hint
    }'
  exit 0
fi

printf 'provider=%q\n' "${provider}"
printf 'route=%q\n' "${route}"
printf 'available=%q\n' "${available}"
printf 'backend=%q\n' "${backend}"
printf 'reason=%q\n' "${reason}"
printf 'fallback_route=%q\n' "${fallback_route}"
printf 'backend_hint=%q\n' "${backend_hint}"
