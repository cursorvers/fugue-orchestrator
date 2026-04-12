#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${ROOT_DIR}/config/integrations/mcp-adapters.json"
KERNEL_ADAPTER_SCRIPT="${ROOT_DIR}/scripts/lib/mcp-kernel-adapter.sh"
SKILL_CLI_SCRIPT="${ROOT_DIR}/scripts/lib/skill-cli-adapter.sh"

adapter_id=""
execution_engine=""
session_provider=""
format="env"

usage() {
  cat <<'EOF'
Usage: mcp-adapter-policy.sh --adapter <id> [options]

Options:
  --adapter <id>                     Adapter ID from config/integrations/mcp-adapters.json
  --execution-engine <subscription|harness|api|local>
                                     Optional execution engine hint (default: local)
  --session-provider <claude|none>   Optional active session provider (default: none)
  --format <env|json>                Output format (default: env)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --adapter)
      adapter_id="${2:-}"
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

if [[ -z "${adapter_id}" ]]; then
  echo "Error: --adapter is required" >&2
  exit 1
fi
if [[ ! -f "${MANIFEST}" ]]; then
  echo "Error: manifest not found: ${MANIFEST}" >&2
  exit 1
fi
if [[ ! -x "${KERNEL_ADAPTER_SCRIPT}" ]]; then
  echo "Error: kernel adapter script not found: ${KERNEL_ADAPTER_SCRIPT}" >&2
  exit 1
fi
if [[ ! -x "${SKILL_CLI_SCRIPT}" ]]; then
  echo "Error: skill cli adapter script not found: ${SKILL_CLI_SCRIPT}" >&2
  exit 1
fi

execution_engine="$(echo "${execution_engine:-local}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
case "${execution_engine}" in
  subscription|harness|api|local|"") ;;
  *)
    echo "Error: invalid --execution-engine=${execution_engine}" >&2
    exit 1
    ;;
esac
if [[ -z "${execution_engine}" ]]; then
  execution_engine="local"
fi

session_provider="$(echo "${session_provider:-none}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
if [[ "${session_provider}" != "claude" ]]; then
  session_provider="none"
fi

adapter_json="$(jq -c --arg id "${adapter_id}" '.adapters[] | select(.id == $id)' "${MANIFEST}")"
if [[ -z "${adapter_json}" ]]; then
  echo "Error: unknown adapter id: ${adapter_id}" >&2
  exit 1
fi

provider="$(echo "${adapter_json}" | jq -r '.provider')"
access_mode="$(echo "${adapter_json}" | jq -r '.access_mode')"
runtime_availability="$(echo "${adapter_json}" | jq -r '.runtime_availability')"
control_plane="$(echo "${adapter_json}" | jq -r '.control_plane')"
kernel_compatible="$(echo "${adapter_json}" | jq -r '.kernel_compatible')"
fallback_route="$(echo "${adapter_json}" | jq -r '.fallback_route')"

route="unavailable"
available="false"
requires_session="false"

case "${access_mode}" in
  rest-bridge)
    route="rest-bridge"
    available="true"
    ;;
  kernel-adapter)
    kernel_route_json="$("${KERNEL_ADAPTER_SCRIPT}" --provider "${provider}" --session-provider "${session_provider}" --format json)"
    route="$(echo "${kernel_route_json}" | jq -r '.route')"
    available="$(echo "${kernel_route_json}" | jq -r '.available')"
    fallback_route="$(echo "${kernel_route_json}" | jq -r '.fallback_route')"
    ;;
  skill-cli)
    skill_route_json="$("${SKILL_CLI_SCRIPT}" --provider "${provider}" --action resolve --session-provider "${session_provider}" --format json)"
    route="$(echo "${skill_route_json}" | jq -r '.route')"
    available="$(echo "${skill_route_json}" | jq -r '.available')"
    fallback_route="$(echo "${skill_route_json}" | jq -r '.fallback_route')"
    ;;
  claude-session)
    requires_session="true"
    if [[ "${session_provider}" == "claude" ]]; then
      route="claude-session"
      available="true"
    fi
    ;;
esac

if [[ "${format}" == "json" ]]; then
  jq -cn \
    --arg adapter_id "${adapter_id}" \
    --arg provider "${provider}" \
    --arg access_mode "${access_mode}" \
    --arg runtime_availability "${runtime_availability}" \
    --arg control_plane "${control_plane}" \
    --arg kernel_compatible "${kernel_compatible}" \
    --arg fallback_route "${fallback_route}" \
    --arg execution_engine "${execution_engine}" \
    --arg session_provider "${session_provider}" \
    --arg route "${route}" \
    --arg available "${available}" \
    --arg requires_session "${requires_session}" \
    '{
      adapter_id:$adapter_id,
      provider:$provider,
      access_mode:$access_mode,
      runtime_availability:$runtime_availability,
      control_plane:$control_plane,
      kernel_compatible:($kernel_compatible == "true"),
      fallback_route:$fallback_route,
      execution_engine:$execution_engine,
      session_provider:$session_provider,
      route:$route,
      available:($available == "true"),
      requires_session:($requires_session == "true")
    }'
  exit 0
fi

printf 'adapter_id=%q\n' "${adapter_id}"
printf 'provider=%q\n' "${provider}"
printf 'access_mode=%q\n' "${access_mode}"
printf 'runtime_availability=%q\n' "${runtime_availability}"
printf 'control_plane=%q\n' "${control_plane}"
printf 'kernel_compatible=%q\n' "${kernel_compatible}"
printf 'fallback_route=%q\n' "${fallback_route}"
printf 'execution_engine=%q\n' "${execution_engine}"
printf 'session_provider=%q\n' "${session_provider}"
printf 'route=%q\n' "${route}"
printf 'available=%q\n' "${available}"
printf 'requires_session=%q\n' "${requires_session}"
