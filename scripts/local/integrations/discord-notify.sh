#!/usr/bin/env bash
set -euo pipefail

MODE="smoke"
RUN_DIR=""
WEBHOOK_URL="${DISCORD_NOTIFY_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-${DISCORD_SYSTEM_WEBHOOK:-}}}"
REQUIRED_ON_EXECUTE="${DISCORD_NOTIFY_REQUIRED_ON_EXECUTE:-true}"
SMOKE_SEND="${DISCORD_NOTIFY_SMOKE_SEND:-false}"

usage() {
  cat <<'EOF'
Usage: discord-notify.sh [options]

Options:
  --mode <smoke|execute>   Run mode (default: smoke)
  --run-dir <path>         FUGUE run directory (optional)
  -h, --help               Show help

Environment:
  DISCORD_NOTIFY_WEBHOOK_URL  Discord webhook URL (preferred)
  DISCORD_WEBHOOK_URL         Fallback webhook URL
  DISCORD_SYSTEM_WEBHOOK      Legacy fallback webhook URL
  DISCORD_NOTIFY_REQUIRED_ON_EXECUTE=true|false
                             If true (default), execute mode fails when webhook is missing.
  DISCORD_NOTIFY_SMOKE_SEND=true|false
                             If true, smoke mode also sends a test message.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --run-dir)
      RUN_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${MODE}" != "smoke" && "${MODE}" != "execute" ]]; then
  echo "Error: --mode must be smoke|execute" >&2
  exit 2
fi

to_bool() {
  local v
  v="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${v}" == "true" || "${v}" == "1" || "${v}" == "yes" || "${v}" == "on" ]]; then
    printf '%s' "true"
  else
    printf '%s' "false"
  fi
}

REQUIRED_ON_EXECUTE="$(to_bool "${REQUIRED_ON_EXECUTE}")"
SMOKE_SEND="$(to_bool "${SMOKE_SEND}")"

if [[ -z "${WEBHOOK_URL}" ]]; then
  if [[ "${MODE}" == "execute" && "${REQUIRED_ON_EXECUTE}" == "true" ]]; then
    echo "discord-notify: webhook is required in execute mode (set DISCORD_NOTIFY_WEBHOOK_URL or DISCORD_WEBHOOK_URL or DISCORD_SYSTEM_WEBHOOK)." >&2
    exit 1
  fi
  echo "discord-notify: webhook is not configured; skipping (${MODE})."
  if [[ -n "${RUN_DIR}" ]]; then
    mkdir -p "${RUN_DIR}"
    {
      echo "system=discord-notify"
      echo "mode=${MODE}"
      echo "status=skipped-missing-config"
    } > "${RUN_DIR}/discord-notify.meta"
  fi
  exit 0
fi

should_send="false"
if [[ "${MODE}" == "execute" || "${SMOKE_SEND}" == "true" ]]; then
  should_send="true"
fi

issue_number="${FUGUE_ISSUE_NUMBER:-unknown}"
issue_title="${FUGUE_ISSUE_TITLE:-}"
issue_url="${FUGUE_ISSUE_URL:-}"
message_head="FUGUE Discord notify (${MODE})"
message_body="issue=#${issue_number} title=${issue_title}"
if [[ -n "${issue_url}" ]]; then
  message_body="${message_body} url=${issue_url}"
fi
content="${message_head}\n${message_body}"

if [[ "${should_send}" == "true" ]]; then
  payload="$(jq -n --arg content "${content}" '{content:$content}')"
  curl -fsS -X POST "${WEBHOOK_URL}" \
    -H "Content-Type: application/json" \
    -d "${payload}" >/dev/null
  echo "discord-notify: delivered (${MODE})."
else
  echo "discord-notify: smoke validation only (send disabled)."
fi

if [[ -n "${RUN_DIR}" ]]; then
  mkdir -p "${RUN_DIR}"
  {
    echo "system=discord-notify"
    echo "mode=${MODE}"
    echo "status=ok"
    echo "sent=${should_send}"
  } > "${RUN_DIR}/discord-notify.meta"
fi
