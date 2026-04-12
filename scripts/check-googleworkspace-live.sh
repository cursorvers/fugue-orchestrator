#!/usr/bin/env bash
set -euo pipefail

credentials_file=""
format="json"

usage() {
  cat <<'EOF'
Usage:
  scripts/check-googleworkspace-live.sh [options]

Options:
  --credentials-file <path>   Service account or exported credentials file.
                              Fallback order when omitted:
                              FUGUE_GWS_CREDENTIALS_FILE
                              KERNEL_GWS_CREDENTIALS_FILE
                              GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE
  --format <json|table>       Output format (default: json)
  -h, --help                  Show help.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --credentials-file)
      credentials_file="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-json}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

case "${format}" in
  json|table) ;;
  *)
    fail "invalid --format=${format}"
    ;;
esac

if [[ -z "${credentials_file}" ]]; then
  credentials_file="${FUGUE_GWS_CREDENTIALS_FILE:-${KERNEL_GWS_CREDENTIALS_FILE:-${GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE:-}}}"
fi

[[ -n "${credentials_file}" ]] || fail "credentials file is required"
[[ -f "${credentials_file}" ]] || fail "credentials file not found: ${credentials_file}"

require_cmd gws
require_cmd jq
require_cmd mktemp

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

results_file="${tmp_dir}/results.jsonl"

classify_result() {
  local rc="$1"
  local output_file="$2"

  if [[ "${rc}" == "0" ]]; then
    if rg -q '^Warning:' "${output_file}"; then
      printf 'partial\n'
    else
      printf 'ok\n'
    fi
    return 0
  fi

  if rg -q 'accessNotConfigured|SERVICE_DISABLED|API not enabled' "${output_file}"; then
    printf 'blocked\n'
    return 0
  fi

  if rg -q 'serviceusage\.services\.use|serviceUsageConsumer' "${output_file}"; then
    printf 'blocked\n'
    return 0
  fi

  if rg -q 'FAILED_PRECONDITION|failedPrecondition|Precondition check failed' "${output_file}"; then
    printf 'blocked\n'
    return 0
  fi

  if rg -q 'PERMISSION_DENIED|permission denied' "${output_file}"; then
    printf 'blocked\n'
    return 0
  fi

  printf 'error\n'
}

extract_reason() {
  local output_file="$1"

  if rg -q 'gmail.googleapis.com' "${output_file}"; then
    printf 'gmail_api_disabled\n'
    return 0
  fi
  if rg -q 'drive.googleapis.com' "${output_file}"; then
    printf 'drive_api_disabled\n'
    return 0
  fi
  if rg -q 'tasks.googleapis.com' "${output_file}"; then
    printf 'tasks_api_disabled\n'
    return 0
  fi
  if rg -q 'calendar' "${output_file}"; then
    printf 'calendar_related\n'
    return 0
  fi
  if rg -q 'PERMISSION_DENIED|permission denied' "${output_file}"; then
    printf 'permission_denied\n'
    return 0
  fi
  if rg -q 'serviceusage\.services\.use|serviceUsageConsumer' "${output_file}"; then
    printf 'serviceusage_consumer_missing\n'
    return 0
  fi
  if rg -q 'FAILED_PRECONDITION|failedPrecondition|Precondition check failed' "${output_file}"; then
    printf 'failed_precondition\n'
    return 0
  fi
  if rg -q 'No upcoming meetings found' "${output_file}"; then
    printf 'no_upcoming_meetings\n'
    return 0
  fi
  printf 'unknown\n'
}

run_check() {
  local id="$1"
  local description="$2"
  shift 2

  local output_file="${tmp_dir}/${id}.out"
  local rc=0

  set +e
  env -u GOOGLE_API_KEY \
    -u GOOGLE_APPLICATION_CREDENTIALS \
    -u GOOGLE_CLOUD_PROJECT \
    -u GCLOUD_PROJECT \
    -u GOOGLE_CREDENTIALS_PATH \
    GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE="${credentials_file}" \
    "$@" >"${output_file}" 2>&1
  rc=$?
  set -e

  local status
  status="$(classify_result "${rc}" "${output_file}")"
  local reason
  reason="$(extract_reason "${output_file}")"

  jq -cn \
    --arg id "${id}" \
    --arg description "${description}" \
    --arg status "${status}" \
    --arg reason "${reason}" \
    --arg command "$(printf '%q ' "$@")" \
    '{
      id:$id,
      description:$description,
      status:$status,
      reason:$reason,
      command:$command
    }' >> "${results_file}"
}

run_check "calendar_raw" "Direct calendar list" \
  gws calendar calendarList list --params '{"maxResults":1}' --format json
run_check "meeting_prep" "Next meeting workflow" \
  gws workflow +meeting-prep --format json
run_check "standup_report" "Meetings plus tasks workflow" \
  gws workflow +standup-report --format json
run_check "weekly_digest" "Meetings plus unread mail workflow" \
  gws workflow +weekly-digest --format json
run_check "drive_list" "Drive file listing" \
  gws drive files list --params '{"pageSize":1}' --format json
run_check "gmail_triage" "Unread inbox triage" \
  gws gmail +triage --max 1 --format json

if [[ "${format}" == "table" ]]; then
  jq -r '[.id, .status, .reason, .description] | @tsv' "${results_file}" \
    | awk 'BEGIN { print "id\tstatus\treason\tdescription" } { print }'
  exit 0
fi

jq -s \
  --arg credentials_file "${credentials_file}" \
  '{
    credentials_file:$credentials_file,
    checks:.
  }' "${results_file}"
