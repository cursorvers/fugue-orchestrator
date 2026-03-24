#!/usr/bin/env bash
set -euo pipefail

MODE="smoke"
RUN_DIR=""
REQUIRED_ON_EXECUTE="${DISCORD_NOTIFY_REQUIRED_ON_EXECUTE:-true}"
SMOKE_SEND="${DISCORD_NOTIFY_SMOKE_SEND:-false}"
ALLOW_SYSTEM_WEBHOOK="${DISCORD_NOTIFY_ALLOW_SYSTEM_WEBHOOK:-false}"

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
  DISCORD_SYSTEM_WEBHOOK      System-alert-only webhook URL (blocked by default here)
  DISCORD_NOTIFY_ALLOW_SYSTEM_WEBHOOK=true|false
                             If true, allow fallback to DISCORD_SYSTEM_WEBHOOK.
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
ALLOW_SYSTEM_WEBHOOK="$(to_bool "${ALLOW_SYSTEM_WEBHOOK}")"

WEBHOOK_URL="${DISCORD_NOTIFY_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-}}"
if [[ -z "${WEBHOOK_URL}" && "${ALLOW_SYSTEM_WEBHOOK}" == "true" ]]; then
  WEBHOOK_URL="${DISCORD_SYSTEM_WEBHOOK:-}"
fi

if [[ -z "${WEBHOOK_URL}" ]]; then
  if [[ "${MODE}" == "execute" && "${REQUIRED_ON_EXECUTE}" == "true" ]]; then
    echo "discord-notify: webhook is required in execute mode (set DISCORD_NOTIFY_WEBHOOK_URL or DISCORD_WEBHOOK_URL)." >&2
    echo "discord-notify: DISCORD_SYSTEM_WEBHOOK is reserved for system alerts unless DISCORD_NOTIFY_ALLOW_SYSTEM_WEBHOOK=true." >&2
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
content="${message_head}"$'\n'"${message_body}"

# Discord content field limit is 2000 characters.
if (( ${#content} > 2000 )); then
  content="${content:0:1997}..."
fi

if [[ "${should_send}" == "true" ]]; then
  payload="$(jq -n --arg content "${content}" '{content:$content}')"

  http_status=""
  curl_exit_code=0
  max_attempts=3
  attempt=1
  retry_count=0

  while :; do
    set +e
    http_status="$(curl -sS -X POST "${WEBHOOK_URL}" \
      --connect-timeout 5 \
      --max-time 20 \
      -o /dev/null \
      --write-out '%{http_code}' \
      -H "Content-Type: application/json" \
      -d "${payload}")"
    curl_exit_code=$?
    set -e

    if (( curl_exit_code == 0 )) && [[ "${http_status}" =~ ^2[0-9]{2}$ ]]; then
      break
    fi

    if (( attempt < max_attempts )); then
      retry_reason=""
      case "${curl_exit_code}" in
        6|7|28|52|56) retry_reason="curl-exit-${curl_exit_code}" ;;
      esac
      if [[ -z "${retry_reason}" ]]; then
        case "${http_status:-}" in
          408|429|500|502|503|504) retry_reason="http-${http_status}" ;;
        esac
      fi
      if [[ -n "${retry_reason}" ]]; then
        retry_count=$((retry_count + 1))
        sleep_seconds=$((1 << (attempt - 1)))
        if (( sleep_seconds > 4 )); then sleep_seconds=4; fi
        echo "discord-notify: transient failure (${retry_reason}); retry ${attempt}/${max_attempts} after ${sleep_seconds}s."
        attempt=$((attempt + 1))
        sleep "${sleep_seconds}"
        continue
      fi
    fi

    break
  done

  if (( curl_exit_code == 0 )) && [[ "${http_status}" =~ ^2[0-9]{2}$ ]]; then
    if (( retry_count > 0 )); then
      echo "discord-notify: recovered after ${retry_count} retries."
    fi
    echo "discord-notify: delivered (${MODE})."
    if [[ -n "${RUN_DIR}" ]]; then
      mkdir -p "${RUN_DIR}"
      {
        echo "system=discord-notify"
        echo "mode=${MODE}"
        echo "status=ok"
        echo "sent=true"
        echo "http_code=${http_status}"
        echo "retry_count=${retry_count}"
      } > "${RUN_DIR}/discord-notify.meta"
    fi
  else
    echo "discord-notify: delivery failed (${MODE}): http=${http_status:-N/A} curl_exit=${curl_exit_code}." >&2
    if [[ -n "${RUN_DIR}" ]]; then
      mkdir -p "${RUN_DIR}"
      {
        echo "system=discord-notify"
        echo "mode=${MODE}"
        echo "status=error"
        echo "sent=false"
        echo "http_code=${http_status:-N/A}"
        echo "curl_exit_code=${curl_exit_code}"
        echo "retry_count=${retry_count}"
      } > "${RUN_DIR}/discord-notify.meta"
    fi
    exit 1
  fi
else
  echo "discord-notify: smoke validation only (send disabled)."
  if [[ -n "${RUN_DIR}" ]]; then
    mkdir -p "${RUN_DIR}"
    {
      echo "system=discord-notify"
      echo "mode=${MODE}"
      echo "status=ok"
      echo "sent=false"
    } > "${RUN_DIR}/discord-notify.meta"
  fi
fi
