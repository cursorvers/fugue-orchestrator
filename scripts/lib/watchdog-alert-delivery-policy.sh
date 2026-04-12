#!/usr/bin/env bash
set -euo pipefail

discord_sent="false"
discord_attempted="false"
line_sent="false"
line_attempted="false"
line_status="unknown"
line_transport="unknown"
line_delivery_state="unknown"
format="json"

usage() {
  cat <<'EOF'
Usage:
  scripts/lib/watchdog-alert-delivery-policy.sh [options]

Options:
  --discord-sent <true|false>
  --discord-attempted <true|false>
  --line-sent <true|false>
  --line-attempted <true|false>
  --line-status <text>
  --line-transport <push|broadcast|webhook|notify|unknown>
  --line-delivery-state <delivered|accepted-upstream|unknown>
  --format <json|env>
  -h, --help
EOF
}

to_bool() {
  local value
  value="$(printf '%s' "${1:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${value}" == "true" || "${value}" == "1" || "${value}" == "yes" || "${value}" == "on" ]]; then
    printf '%s' "true"
  else
    printf '%s' "false"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --discord-sent) discord_sent="${2:-}"; shift 2 ;;
    --discord-attempted) discord_attempted="${2:-}"; shift 2 ;;
    --line-sent) line_sent="${2:-}"; shift 2 ;;
    --line-attempted) line_attempted="${2:-}"; shift 2 ;;
    --line-status) line_status="${2:-}"; shift 2 ;;
    --line-transport) line_transport="${2:-}"; shift 2 ;;
    --line-delivery-state) line_delivery_state="${2:-}"; shift 2 ;;
    --format) format="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

discord_sent="$(to_bool "${discord_sent}")"
discord_attempted="$(to_bool "${discord_attempted}")"
line_sent="$(to_bool "${line_sent}")"
line_attempted="$(to_bool "${line_attempted}")"
line_status="$(printf '%s' "${line_status}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
line_transport="$(printf '%s' "${line_transport}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
line_delivery_state="$(printf '%s' "${line_delivery_state}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"

line_delivery_confirmed="false"
line_reason="not-sent"

if [[ "${line_sent}" == "true" ]]; then
  case "${line_transport}" in
    push|broadcast|notify)
      if [[ "${line_status}" == "ok" ]]; then
        line_delivery_confirmed="true"
        line_reason="line-${line_transport}-ok"
      else
        line_reason="line-${line_transport}-status-${line_status:-unknown}"
      fi
      ;;
    webhook)
      if [[ "${line_status}" == "ok" && "${line_delivery_state}" == "delivered" ]]; then
        line_delivery_confirmed="true"
        line_reason="line-webhook-delivered"
      else
        line_reason="line-webhook-${line_delivery_state:-unknown}"
      fi
      ;;
    *)
      line_reason="line-${line_transport:-unknown}"
      ;;
  esac
fi

persist_allowed="false"
persist_reason="no-confirmed-delivery"
if [[ "${discord_sent}" == "true" ]]; then
  persist_allowed="true"
  persist_reason="discord-delivered"
elif [[ "${line_sent}" == "true" && "${line_status}" == "ok" ]]; then
  persist_allowed="true"
  persist_reason="line-accepted"
  if [[ "${line_delivery_confirmed}" == "true" ]]; then
    persist_reason="${line_reason}"
  fi
fi

if [[ "${format}" == "env" ]]; then
  cat <<EOF
discord_sent=${discord_sent}
discord_attempted=${discord_attempted}
line_sent=${line_sent}
line_attempted=${line_attempted}
line_delivery_confirmed=${line_delivery_confirmed}
persist_allowed=${persist_allowed}
persist_reason=${persist_reason}
line_reason=${line_reason}
EOF
  exit 0
fi

jq -cn \
  --arg discord_sent "${discord_sent}" \
  --arg line_sent "${line_sent}" \
  --arg line_delivery_confirmed "${line_delivery_confirmed}" \
  --arg persist_allowed "${persist_allowed}" \
  --arg persist_reason "${persist_reason}" \
  --arg line_reason "${line_reason}" \
  '{
    discord_sent: ($discord_sent == "true"),
    line_sent: ($line_sent == "true"),
    line_delivery_confirmed: ($line_delivery_confirmed == "true"),
    persist_allowed: ($persist_allowed == "true"),
    persist_reason: $persist_reason,
    line_reason: $line_reason
  }'
