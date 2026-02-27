#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

MODE="smoke"
RUN_DIR=""

LINE_WEBHOOK_URL="${LINE_WEBHOOK_URL:-}"
LINE_CHANNEL_ACCESS_TOKEN="${LINE_CHANNEL_ACCESS_TOKEN:-}"
LINE_TO="${LINE_TO:-}"
LINE_PUSH_API_URL="${LINE_PUSH_API_URL:-https://api.line.me/v2/bot/message/push}"
LINE_NOTIFY_TOKEN="${LINE_NOTIFY_TOKEN:-${LINE_NOTIFY_ACCESS_TOKEN:-}}"
LINE_NOTIFY_API_URL="${LINE_NOTIFY_API_URL:-https://notify-api.line.me/api/notify}"
LINE_NOTIFY_REQUIRED_ON_EXECUTE="${LINE_NOTIFY_REQUIRED_ON_EXECUTE:-true}"
LINE_NOTIFY_SMOKE_SEND="${LINE_NOTIFY_SMOKE_SEND:-false}"
LINE_NOTIFY_MESSAGE="${LINE_NOTIFY_MESSAGE:-}"
LINE_NOTIFY_GUARD_ENABLED="${LINE_NOTIFY_GUARD_ENABLED:-true}"
LINE_NOTIFY_GUARD_FILE="${LINE_NOTIFY_GUARD_FILE:-${ROOT_DIR}/.fugue/state/line-notify-guard.json}"
LINE_NOTIFY_DEDUP_TTL_SECONDS="${LINE_NOTIFY_DEDUP_TTL_SECONDS:-21600}"
LINE_NOTIFY_FAILURE_COOLDOWN_SECONDS="${LINE_NOTIFY_FAILURE_COOLDOWN_SECONDS:-3600}"
LINE_NOTIFY_CONNECT_TIMEOUT_SECONDS="${LINE_NOTIFY_CONNECT_TIMEOUT_SECONDS:-5}"
LINE_NOTIFY_REQUEST_TIMEOUT_SECONDS="${LINE_NOTIFY_REQUEST_TIMEOUT_SECONDS:-20}"

usage() {
  cat <<'EOF'
Usage: line-notify.sh [options]

Options:
  --mode <smoke|execute>   Run mode (default: smoke)
  --run-dir <path>         FUGUE run directory (optional)
  -h, --help               Show help

Environment:
  LINE_WEBHOOK_URL             Generic webhook endpoint (preferred when available)
  LINE_CHANNEL_ACCESS_TOKEN    LINE Messaging API channel access token
  LINE_TO                      LINE user/group ID for push messages
  LINE_PUSH_API_URL            Override push endpoint (default: official LINE Messaging API)
  LINE_NOTIFY_TOKEN            Legacy LINE Notify token (fallback)
  LINE_NOTIFY_ACCESS_TOKEN     Legacy alias for LINE_NOTIFY_TOKEN
  LINE_NOTIFY_API_URL          Override legacy LINE Notify endpoint
  LINE_NOTIFY_REQUIRED_ON_EXECUTE=true|false
                               If true (default), execute mode fails when config is missing.
  LINE_NOTIFY_SMOKE_SEND=true|false
                               If true, smoke mode also sends a test message.
  LINE_NOTIFY_MESSAGE             Optional custom text payload. If unset, default FUGUE message is used.
  LINE_NOTIFY_GUARD_ENABLED=true|false
                                  Suppress duplicate payloads and recent repeated failures (default: true).
  LINE_NOTIFY_GUARD_FILE          Guard state file path (default: <repo>/.fugue/state/line-notify-guard.json).
  LINE_NOTIFY_DEDUP_TTL_SECONDS   Duplicate suppression window in seconds (default: 21600).
  LINE_NOTIFY_FAILURE_COOLDOWN_SECONDS
                                  Failure cooldown window in seconds (default: 3600).
  LINE_NOTIFY_CONNECT_TIMEOUT_SECONDS
                                  curl connect timeout seconds (default: 5).
  LINE_NOTIFY_REQUEST_TIMEOUT_SECONDS
                                  curl max-time seconds (default: 20).
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

normalize_non_negative_int() {
  local value="${1:-}"
  local fallback="${2:-0}"
  if [[ "${value}" =~ ^[0-9]+$ ]]; then
    printf '%s' "${value}"
  else
    printf '%s' "${fallback}"
  fi
}

hash_text() {
  local input="${1:-}"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "${input}" | shasum -a 256 | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    printf '%s' "${input}" | openssl dgst -sha256 | awk '{print $NF}'
    return 0
  fi
  printf '%s' "${input}" | cksum | awk '{print $1}'
}

write_meta() {
  local status="${1:-unknown}"
  shift || true
  if [[ -z "${RUN_DIR}" ]]; then
    return 0
  fi
  mkdir -p "${RUN_DIR}"
  {
    echo "system=line-notify"
    echo "mode=${MODE}"
    echo "status=${status}"
    while [[ $# -gt 0 ]]; do
      echo "$1"
      shift
    done
  } > "${RUN_DIR}/line-notify.meta"
}

read_guard_json() {
  if [[ -f "${LINE_NOTIFY_GUARD_FILE}" ]] && jq -e . "${LINE_NOTIFY_GUARD_FILE}" >/dev/null 2>&1; then
    cat "${LINE_NOTIFY_GUARD_FILE}"
    return 0
  fi
  printf '%s' '{"entries":{}}'
}

save_guard_json() {
  local json_input="${1:-}"
  local guard_dir
  local tmp_file
  guard_dir="$(dirname "${LINE_NOTIFY_GUARD_FILE}")"
  mkdir -p "${guard_dir}"
  tmp_file="$(mktemp "${guard_dir}/line-notify-guard.XXXXXX.tmp")"
  printf '%s' "${json_input}" > "${tmp_file}"
  mv "${tmp_file}" "${LINE_NOTIFY_GUARD_FILE}"
}

LINE_NOTIFY_REQUIRED_ON_EXECUTE="$(to_bool "${LINE_NOTIFY_REQUIRED_ON_EXECUTE}")"
LINE_NOTIFY_SMOKE_SEND="$(to_bool "${LINE_NOTIFY_SMOKE_SEND}")"
LINE_NOTIFY_GUARD_ENABLED="$(to_bool "${LINE_NOTIFY_GUARD_ENABLED}")"
LINE_NOTIFY_DEDUP_TTL_SECONDS="$(normalize_non_negative_int "${LINE_NOTIFY_DEDUP_TTL_SECONDS}" "21600")"
LINE_NOTIFY_FAILURE_COOLDOWN_SECONDS="$(normalize_non_negative_int "${LINE_NOTIFY_FAILURE_COOLDOWN_SECONDS}" "3600")"
LINE_NOTIFY_CONNECT_TIMEOUT_SECONDS="$(normalize_non_negative_int "${LINE_NOTIFY_CONNECT_TIMEOUT_SECONDS}" "5")"
LINE_NOTIFY_REQUEST_TIMEOUT_SECONDS="$(normalize_non_negative_int "${LINE_NOTIFY_REQUEST_TIMEOUT_SECONDS}" "20")"

transport="none"
if [[ -n "${LINE_WEBHOOK_URL}" ]]; then
  transport="webhook"
elif [[ -n "${LINE_CHANNEL_ACCESS_TOKEN}" && -n "${LINE_TO}" ]]; then
  transport="push"
elif [[ -n "${LINE_NOTIFY_TOKEN}" ]]; then
  transport="notify"
fi

if [[ "${transport}" == "none" ]]; then
  if [[ "${MODE}" == "execute" && "${LINE_NOTIFY_REQUIRED_ON_EXECUTE}" == "true" ]]; then
    echo "line-notify: missing config. Set LINE_WEBHOOK_URL or (LINE_CHANNEL_ACCESS_TOKEN + LINE_TO) or LINE_NOTIFY_TOKEN." >&2
    write_meta "error-missing-config" "sent=false"
    exit 1
  fi
  echo "line-notify: configuration is missing; skipping (${MODE})."
  write_meta "skipped-missing-config" "sent=false"
  exit 0
fi

should_send="false"
if [[ "${MODE}" == "execute" || "${LINE_NOTIFY_SMOKE_SEND}" == "true" ]]; then
  should_send="true"
fi

issue_number="${FUGUE_ISSUE_NUMBER:-unknown}"
issue_title="${FUGUE_ISSUE_TITLE:-}"
issue_url="${FUGUE_ISSUE_URL:-}"
if [[ -n "${LINE_NOTIFY_MESSAGE}" ]]; then
  message="${LINE_NOTIFY_MESSAGE}"
else
  message="FUGUE LINE notify (${MODE}) | issue=#${issue_number} | title=${issue_title}"
  if [[ -n "${issue_url}" ]]; then
    message="${message} | url=${issue_url}"
  fi
fi
# LINE text payload limit protection.
if (( ${#message} > 900 )); then
  message="${message:0:897}..."
fi

message_hash="$(hash_text "${transport}|${LINE_TO}|${LINE_WEBHOOK_URL}|${LINE_PUSH_API_URL}|${message}")"
guard_action="disabled"
epoch_now="$(date +%s)"

if [[ "${should_send}" == "true" && "${LINE_NOTIFY_GUARD_ENABLED}" == "true" ]]; then
  guard_action="checked"
  guard_json="$(read_guard_json)"
  last_sent_at="$(printf '%s' "${guard_json}" | jq -r --arg key "${message_hash}" '.entries[$key].last_sent_at // 0')"
  last_failure_at="$(printf '%s' "${guard_json}" | jq -r --arg key "${message_hash}" '.entries[$key].last_failure_at // 0')"
  failure_count="$(printf '%s' "${guard_json}" | jq -r --arg key "${message_hash}" '.entries[$key].failure_count // 0')"

  if (( LINE_NOTIFY_DEDUP_TTL_SECONDS > 0 )) && (( epoch_now - last_sent_at < LINE_NOTIFY_DEDUP_TTL_SECONDS )); then
    echo "line-notify: suppressed duplicate send (hash=${message_hash}, ttl=${LINE_NOTIFY_DEDUP_TTL_SECONDS}s)."
    write_meta "suppressed-duplicate" \
      "transport=${transport}" \
      "sent=false" \
      "message_hash=${message_hash}" \
      "guard=duplicate-ttl"
    exit 0
  fi

  if (( LINE_NOTIFY_FAILURE_COOLDOWN_SECONDS > 0 )) && (( epoch_now - last_failure_at < LINE_NOTIFY_FAILURE_COOLDOWN_SECONDS )); then
    echo "line-notify: suppressed retry after recent failure (hash=${message_hash}, cooldown=${LINE_NOTIFY_FAILURE_COOLDOWN_SECONDS}s, failures=${failure_count})."
    write_meta "suppressed-recent-failure" \
      "transport=${transport}" \
      "sent=false" \
      "message_hash=${message_hash}" \
      "failure_count=${failure_count}" \
      "guard=failure-cooldown"
    exit 0
  fi
fi

if [[ "${should_send}" == "true" ]]; then
  http_status=""
  curl_exit_code=0
  response_body=""
  line_request_id=""

  headers_file="$(mktemp)"
  body_file="$(mktemp)"
  trap 'rm -f "${headers_file}" "${body_file}"' EXIT

  set +e
  if [[ "${transport}" == "webhook" ]]; then
    payload="$(jq -n \
      --arg text "${message}" \
      --arg mode "${MODE}" \
      --arg issue_number "${issue_number}" \
      '{
        text:$text,
        message:$text,
        source:"fugue-line-notify",
        mode:$mode,
        issue_number:$issue_number
      }')"
    http_status="$(curl -sS -X POST "${LINE_WEBHOOK_URL}" \
      --connect-timeout "${LINE_NOTIFY_CONNECT_TIMEOUT_SECONDS}" \
      --max-time "${LINE_NOTIFY_REQUEST_TIMEOUT_SECONDS}" \
      -D "${headers_file}" \
      -o "${body_file}" \
      --write-out '%{http_code}' \
      -H "Content-Type: application/json" \
      -d "${payload}")"
    curl_exit_code=$?
  elif [[ "${transport}" == "push" ]]; then
    payload="$(jq -n --arg to "${LINE_TO}" --arg text "${message}" '{to:$to,messages:[{type:"text",text:$text}]}')"
    http_status="$(curl -sS -X POST "${LINE_PUSH_API_URL}" \
      --connect-timeout "${LINE_NOTIFY_CONNECT_TIMEOUT_SECONDS}" \
      --max-time "${LINE_NOTIFY_REQUEST_TIMEOUT_SECONDS}" \
      -D "${headers_file}" \
      -o "${body_file}" \
      --write-out '%{http_code}' \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${LINE_CHANNEL_ACCESS_TOKEN}" \
      -d "${payload}")"
    curl_exit_code=$?
  else
    http_status="$(curl -sS -X POST "${LINE_NOTIFY_API_URL}" \
      --connect-timeout "${LINE_NOTIFY_CONNECT_TIMEOUT_SECONDS}" \
      --max-time "${LINE_NOTIFY_REQUEST_TIMEOUT_SECONDS}" \
      -D "${headers_file}" \
      -o "${body_file}" \
      --write-out '%{http_code}' \
      -H "Authorization: Bearer ${LINE_NOTIFY_TOKEN}" \
      --data-urlencode "message=${message}")"
    curl_exit_code=$?
  fi
  set -e

  response_body="$(cat "${body_file}" 2>/dev/null || true)"
  line_request_id="$(awk 'BEGIN{IGNORECASE=1} /^x-line-request-id:/{gsub("\r","",$2); print $2; exit}' "${headers_file}")"
  code_display="N/A"
  if [[ "${http_status}" =~ ^[0-9]{3}$ ]] && [[ "${http_status}" != "000" ]]; then
    code_display="${http_status}"
  fi

  if (( curl_exit_code == 0 )) && [[ "${http_status}" =~ ^2[0-9]{2}$ ]]; then
    response_message="$(printf '%s' "${response_body}" | jq -r 'if type=="object" then (.message // .status // .result // empty) else empty end' 2>/dev/null || true)"
    delivery_state="delivered"
    if [[ "${transport}" == "webhook" && -z "${line_request_id}" ]]; then
      delivery_state="accepted-upstream"
      if [[ -n "${response_message}" ]]; then
        echo "line-notify: upstream webhook accepted request (${response_message}); downstream LINE delivery must be confirmed by webhook system logs."
      else
        echo "line-notify: upstream webhook accepted request; downstream LINE delivery must be confirmed by webhook system logs."
      fi
    fi
    if [[ "${LINE_NOTIFY_GUARD_ENABLED}" == "true" ]]; then
      guard_json="$(read_guard_json)"
      updated_guard="$(printf '%s' "${guard_json}" | jq --arg key "${message_hash}" --argjson now "${epoch_now}" '
        .entries[$key] = ((.entries[$key] // {}) + {last_sent_at:$now, last_failure_at:0, failure_count:0})
      ')"
      save_guard_json "${updated_guard}"
      guard_action="recorded-success"
    fi
    echo "line-notify: delivered (${MODE}) via ${transport} (code=${code_display})."
    write_meta "ok" \
      "transport=${transport}" \
      "sent=true" \
      "http_code=${code_display}" \
      "line_request_id=${line_request_id}" \
      "delivery_state=${delivery_state}" \
      "response_message=${response_message}" \
      "message_hash=${message_hash}" \
      "guard=${guard_action}"
  else
    error_message="$(printf '%s' "${response_body}" | jq -r 'if type=="object" then (.message // .error // .error_description // .detail // .title // empty) else empty end' 2>/dev/null || true)"
    if [[ -z "${error_message}" ]]; then
      error_message="$(printf '%s' "${response_body}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | cut -c1-220)"
    fi
    if [[ -z "${error_message}" ]]; then
      error_message="LINE API応答異常"
    fi

    if [[ "${LINE_NOTIFY_GUARD_ENABLED}" == "true" ]]; then
      guard_json="$(read_guard_json)"
      updated_guard="$(printf '%s' "${guard_json}" | jq --arg key "${message_hash}" --argjson now "${epoch_now}" '
        .entries[$key] = ((.entries[$key] // {}) + {
          last_failure_at:$now,
          failure_count:((.entries[$key].failure_count // 0) + 1)
        })
      ')"
      save_guard_json "${updated_guard}"
      guard_action="recorded-failure"
      failure_count="$(printf '%s' "${updated_guard}" | jq -r --arg key "${message_hash}" '.entries[$key].failure_count // 1')"
    else
      failure_count="1"
    fi

    write_meta "error" \
      "transport=${transport}" \
      "sent=false" \
      "http_code=${code_display}" \
      "curl_exit_code=${curl_exit_code}" \
      "line_request_id=${line_request_id}" \
      "message_hash=${message_hash}" \
      "failure_count=${failure_count}" \
      "error_message=${error_message}" \
      "guard=${guard_action}"
    echo "line-notify: delivery failed (${MODE}) via ${transport}: ${error_message} (code: ${code_display}, curl_exit: ${curl_exit_code})." >&2
    exit 1
  fi
else
  echo "line-notify: smoke validation only (send disabled), transport=${transport}."
  write_meta "ok" \
    "transport=${transport}" \
    "sent=false" \
    "message_hash=${message_hash}" \
    "guard=${guard_action}"
fi
