#!/usr/bin/env bash
set -euo pipefail

action=""
format="table"
calendar="primary"
max_results="10"
credentials_file=""
resolve_only="false"
dry_run="false"
email_to=""
subject=""
body=""
file_path=""
target_name=""
parent_id=""
event_json=""
title=""
document_id=""
spreadsheet_id=""
sheet_range=""
values_json=""
text=""
run_dir=""
ok_to_execute="false"
human_approved="false"
approval_source="none"
explicit_human_approved="false"
consensus_receipt_path=""
CONSENSUS_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/kernel-consensus-evidence.sh"

usage() {
  cat <<'EOF'
Usage: googleworkspace-cli-adapter.sh --action <id> [options]

Actions:
  smoke
  gmail-triage
  gmail-send
  drive-upload
  calendar-insert
  docs-create
  docs-insert-text
  sheets-create
  sheets-append
  meeting-prep
  standup-report
  weekly-digest

Options:
  --format <json|table|yaml|csv>   Output format for gws workflow commands.
  --calendar <id>                  Calendar ID for meeting-prep (default: primary).
  --max <n>                        Max unread items for gmail-triage (default: 10).
  --to <email>                     Recipient email for gmail-send.
  --subject <text>                 Subject for gmail-send.
  --body <text>                    Body for gmail-send.
  --file <path>                    Local file path for drive-upload.
  --name <text>                    Optional target filename for drive-upload.
  --parent <id>                    Optional parent folder ID for drive-upload.
  --event-json <json>              Calendar event JSON body for calendar-insert.
  --title <text>                   Title for docs-create or sheets-create.
  --document-id <id>               Document ID for docs-insert-text.
  --spreadsheet-id <id>            Spreadsheet ID for sheets-append.
  --range <a1>                     A1 range for sheets-append.
  --values-json <json>             Sheets values JSON body for sheets-append.
  --text <text>                    Text payload for docs-insert-text.
  --run-dir <path>                 Write raw outputs and receipt metadata under <run-dir>/googleworkspace.
  --ok-to-execute <true|false>     Gate write actions on Kernel approval state.
  --human-approved <true|false>    Gate write actions on explicit human approval.
                                   For non-critical runs, approved Kernel consensus can satisfy this gate.
  --credentials-file <path>        Use a specific service account or exported credential file.
                                   Fallback order when omitted:
                                   FUGUE_GWS_CREDENTIALS_FILE
                                   KERNEL_GWS_CREDENTIALS_FILE
                                   GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE
  --resolve-only                   Print the resolved gws command and exit.
  --dry-run                        For write actions, pass through to gws. For read-only actions, alias for --resolve-only.
  -h, --help                       Show this help.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

validate_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || fail "expected positive integer, got: $1"
}

require_non_empty() {
  local value="$1"
  local label="$2"
  [[ -n "${value}" ]] || fail "${label} is required"
}

normalize_bool() {
  local value
  value="$(printf '%s' "${1:-false}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${value}" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

is_write_action() {
  case "${1:-}" in
    gmail-send|drive-upload|calendar-insert|docs-create|docs-insert-text|sheets-create|sheets-append)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

format_extension() {
  case "${1:-table}" in
    json)
      printf 'json'
      ;;
    yaml)
      printf 'yaml'
      ;;
    csv)
      printf 'csv'
      ;;
    *)
      printf 'txt'
      ;;
  esac
}

print_command() {
  local cmd=("$@")
  if [[ -n "${credentials_file}" ]]; then
    printf 'env -u GOOGLE_API_KEY -u GOOGLE_APPLICATION_CREDENTIALS -u GOOGLE_CLOUD_PROJECT -u GCLOUD_PROJECT -u GOOGLE_CREDENTIALS_PATH GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=%q ' "${credentials_file}"
  fi
  printf '%q' "${cmd[0]}"
  local i
  for (( i = 1; i < ${#cmd[@]}; i++ )); do
    printf ' %q' "${cmd[i]}"
  done
  printf '\n'
}

run_gws_command() {
  local stdout_path="${1:-}"
  local stderr_path="${2:-}"
  shift 2
  local cmd=("$@")
  local env_cmd=(
    env
    -u GOOGLE_API_KEY
    -u GOOGLE_APPLICATION_CREDENTIALS
    -u GOOGLE_CLOUD_PROJECT
    -u GCLOUD_PROJECT
    -u GOOGLE_CREDENTIALS_PATH
    -u GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE
    -u FUGUE_GWS_CREDENTIALS_FILE
    -u KERNEL_GWS_CREDENTIALS_FILE
  )
  if [[ -n "${credentials_file}" ]]; then
    env_cmd+=("GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=${credentials_file}")
  fi

  if [[ -n "${stdout_path}" ]]; then
    "${env_cmd[@]}" "${cmd[@]}" > "${stdout_path}" 2> "${stderr_path}"
  else
    "${env_cmd[@]}" "${cmd[@]}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      action="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-table}"
      shift 2
      ;;
    --calendar)
      calendar="${2:-primary}"
      shift 2
      ;;
    --max)
      max_results="${2:-10}"
      shift 2
      ;;
    --to)
      email_to="${2:-}"
      shift 2
      ;;
    --subject)
      subject="${2:-}"
      shift 2
      ;;
    --body)
      body="${2:-}"
      shift 2
      ;;
    --file)
      file_path="${2:-}"
      shift 2
      ;;
    --name)
      target_name="${2:-}"
      shift 2
      ;;
    --parent)
      parent_id="${2:-}"
      shift 2
      ;;
    --event-json)
      event_json="${2:-}"
      shift 2
      ;;
    --title)
      title="${2:-}"
      shift 2
      ;;
    --document-id)
      document_id="${2:-}"
      shift 2
      ;;
    --spreadsheet-id)
      spreadsheet_id="${2:-}"
      shift 2
      ;;
    --range)
      sheet_range="${2:-}"
      shift 2
      ;;
    --values-json)
      values_json="${2:-}"
      shift 2
      ;;
    --text)
      text="${2:-}"
      shift 2
      ;;
    --run-dir)
      run_dir="${2:-}"
      shift 2
      ;;
    --ok-to-execute)
      ok_to_execute="${2:-false}"
      shift 2
      ;;
    --human-approved)
      human_approved="${2:-false}"
      shift 2
      ;;
    --credentials-file)
      credentials_file="${2:-}"
      shift 2
      ;;
    --resolve-only)
      resolve_only="true"
      shift
      ;;
    --dry-run)
      dry_run="true"
      shift
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

[[ -n "${action}" ]] || fail "--action is required"

case "${format}" in
  json|table|yaml|csv) ;;
  *)
    fail "invalid --format=${format}"
    ;;
esac

validate_positive_int "${max_results}"
ok_to_execute="$(normalize_bool "${ok_to_execute}")"
human_approved="$(normalize_bool "${human_approved}")"
explicit_human_approved="${human_approved}"

if [[ -z "${credentials_file}" ]]; then
  credentials_file="${FUGUE_GWS_CREDENTIALS_FILE:-${KERNEL_GWS_CREDENTIALS_FILE:-${GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE:-}}}"
fi

if [[ -n "${credentials_file}" && ! -f "${credentials_file}" ]]; then
  fail "credentials file not found: ${credentials_file}"
fi

if [[ -n "${run_dir}" && "${run_dir}" != /* ]]; then
  run_dir="$(cd "${PWD}" && pwd)/${run_dir}"
fi

cmd=()
case "${action}" in
  smoke)
    cmd=(gws --help)
    ;;
  gmail-triage)
    cmd=(gws gmail +triage --max "${max_results}" --format "${format}")
    ;;
  gmail-send)
    require_non_empty "${email_to}" "--to"
    require_non_empty "${subject}" "--subject"
    require_non_empty "${body}" "--body"
    cmd=(gws gmail +send --to "${email_to}" --subject "${subject}" --body "${body}" --format "${format}")
    if [[ "${dry_run}" == "true" ]]; then
      cmd+=(--dry-run)
    fi
    ;;
  drive-upload)
    require_non_empty "${file_path}" "--file"
    [[ -f "${file_path}" ]] || fail "file not found: ${file_path}"
    cmd=(gws drive +upload "${file_path}" --format "${format}")
    if [[ -n "${target_name}" ]]; then
      cmd+=(--name "${target_name}")
    fi
    if [[ -n "${parent_id}" ]]; then
      cmd+=(--parent "${parent_id}")
    fi
    if [[ "${dry_run}" == "true" ]]; then
      cmd+=(--dry-run)
    fi
    ;;
  calendar-insert)
    require_non_empty "${event_json}" "--event-json"
    cmd=(gws calendar events insert --params "$(jq -cn --arg cal "${calendar}" '{"calendarId":$cal}')" --json "${event_json}" --format "${format}")
    if [[ "${dry_run}" == "true" ]]; then
      cmd+=(--dry-run)
    fi
    ;;
  docs-create)
    require_non_empty "${title}" "--title"
    cmd=(gws docs documents create --json "$(jq -cn --arg t "${title}" '{"title":$t}')" --format "${format}")
    ;;
  docs-insert-text)
    require_non_empty "${document_id}" "--document-id"
    require_non_empty "${text}" "--text"
    cmd=(gws docs documents batchUpdate --params "$(jq -cn --arg did "${document_id}" '{"documentId":$did}')" --json "$(jq -cn --arg t "${text}" '{"requests":[{"insertText":{"location":{"index":1},"text":$t}}]}')" --format "${format}")
    ;;
  sheets-create)
    require_non_empty "${title}" "--title"
    cmd=(gws sheets spreadsheets create --json "$(jq -cn --arg t "${title}" '{"properties":{"title":$t}}')" --format "${format}")
    ;;
  sheets-append)
    require_non_empty "${spreadsheet_id}" "--spreadsheet-id"
    require_non_empty "${sheet_range}" "--range"
    require_non_empty "${values_json}" "--values-json"
    cmd=(gws sheets spreadsheets values append --params "$(jq -cn --arg sid "${spreadsheet_id}" --arg r "${sheet_range}" '{"spreadsheetId":$sid,"range":$r,"valueInputOption":"RAW"}')" --json "${values_json}" --format "${format}")
    ;;
  meeting-prep)
    cmd=(gws workflow +meeting-prep --calendar "${calendar}" --format "${format}")
    ;;
  standup-report)
    cmd=(gws workflow +standup-report --format "${format}")
    ;;
  weekly-digest)
    cmd=(gws workflow +weekly-digest --format "${format}")
    ;;
  *)
    fail "unsupported --action=${action}"
    ;;
esac

write_action="false"
if is_write_action "${action}"; then
  write_action="true"
fi

consensus_path() {
  local path
  if [[ -n "${KERNEL_CONSENSUS_RECEIPT_PATH:-}" ]]; then
    path="${KERNEL_CONSENSUS_RECEIPT_PATH}"
  else
    path="$(bash "${CONSENSUS_SCRIPT}" path 2>/dev/null || true)"
  fi
  [[ -n "${path}" && -f "${path}" ]] || return 1
  printf '%s\n' "${path}"
}

consensus_json() {
  local path
  path="$(consensus_path)" || return 1
  consensus_receipt_path="${path}"
  jq -c '.' "${path}"
}

task_size_tier() {
  local tier
  tier="${KERNEL_TASK_SIZE_TIER:-}"
  if [[ -z "${tier}" ]]; then
    tier="$(consensus_json 2>/dev/null | jq -r '.task_size_tier // "medium"' 2>/dev/null || true)"
  fi
  tier="$(printf '%s' "${tier:-medium}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  case "${tier}" in
    small|medium|large|critical) printf '%s\n' "${tier}" ;;
    *) printf 'medium\n' ;;
  esac
}

consensus_satisfies_approval_gate() {
  local json path
  [[ "${ok_to_execute}" == "true" ]] || return 1
  [[ "$(task_size_tier)" != "critical" ]] || return 1
  path="$(consensus_path)" || return 1
  consensus_receipt_path="${path}"
  json="$(jq -c '.' "${path}")" || return 1
  [[ "$(jq -r '.decision // "unknown"' <<<"${json}")" == "approved" ]] || return 1
  [[ "$(jq -r '.ok_to_execute // false' <<<"${json}")" == "true" ]] || return 1
  [[ "$(jq -r '.weighted_vote_passed // false' <<<"${json}")" == "true" ]] || return 1
}

if [[ "${write_action}" == "true" ]]; then
  if [[ "${human_approved}" == "true" ]]; then
    approval_source="explicit-human"
  elif consensus_satisfies_approval_gate; then
    human_approved="true"
    approval_source="kernel-consensus"
  fi
else
  approval_source="readonly"
fi

resolved_command="$(print_command "${cmd[@]}")"
gw_dir=""
raw_output_path=""
stderr_output_path=""
meta_output_path=""
if [[ -n "${run_dir}" ]]; then
  gw_dir="${run_dir%/}/googleworkspace"
  mkdir -p "${gw_dir}"
  output_ext="$(format_extension "${format}")"
  raw_output_path="${gw_dir}/${action}.${output_ext}"
  stderr_output_path="${gw_dir}/${action}.stderr.log"
  meta_output_path="${gw_dir}/${action}-meta.json"
fi

write_meta() {
  local status="$1"
  local exit_code="$2"
  local message="$3"
  local receipt_json="${4:-}"
  local write_disposition
  if [[ -z "${receipt_json}" ]]; then
    receipt_json='{}'
  fi
  [[ -n "${meta_output_path}" ]] || return 0
  write_disposition="$(determine_write_disposition "${status}")"
  jq -n \
    --arg action "${action}" \
    --arg status "${status}" \
    --arg message "${message}" \
    --arg format "${format}" \
    --arg command "${resolved_command}" \
    --arg credentials_file "${credentials_file}" \
    --arg run_dir "${run_dir}" \
    --arg raw_output_path "${raw_output_path}" \
    --arg stderr_output_path "${stderr_output_path}" \
    --arg ok_to_execute "${ok_to_execute}" \
    --arg human_approved "${human_approved}" \
    --arg explicit_human_approved "${explicit_human_approved}" \
    --arg approval_source "${approval_source}" \
    --arg consensus_receipt_path "${consensus_receipt_path}" \
    --arg write_action "${write_action}" \
    --arg write_disposition "${write_disposition}" \
    --argjson exit_code "${exit_code}" \
    --argjson receipt "${receipt_json}" \
    '{
      action:$action,
      status:$status,
      message:$message,
      format:$format,
      command:$command,
      credentials_file:(if $credentials_file == "" then null else $credentials_file end),
      run_dir:(if $run_dir == "" then null else $run_dir end),
      raw_output_path:(if $raw_output_path == "" then null else $raw_output_path end),
      stderr_output_path:(if $stderr_output_path == "" then null else $stderr_output_path end),
      ok_to_execute:($ok_to_execute == "true"),
      human_approved:($human_approved == "true"),
      explicit_human_approved:($explicit_human_approved == "true"),
      approval_source:$approval_source,
      consensus_receipt_path:(if $consensus_receipt_path == "" then null else $consensus_receipt_path end),
      side_effect:($write_action == "true"),
      write_disposition:$write_disposition,
      exit_code:$exit_code,
      receipt:$receipt
    }' > "${meta_output_path}"
}

determine_write_disposition() {
  local status="${1:-unknown}"
  if [[ "${write_action}" != "true" ]]; then
    printf 'readonly'
    return 0
  fi

  if [[ "${resolve_only}" == "true" ]]; then
    printf 'resolved'
    return 0
  fi

  if [[ "${dry_run}" == "true" ]]; then
    printf 'preview'
    return 0
  fi

  if [[ "${status}" == "skipped" ]]; then
    printf 'blocked'
    return 0
  fi

  if [[ "${ok_to_execute}" == "true" && "${human_approved}" == "true" ]]; then
    printf 'applied'
    return 0
  fi

  printf 'write'
}

extract_receipt() {
  local output_file="$1"
  if [[ "${format}" != "json" || ! -s "${output_file}" ]]; then
    printf '{}'
    return 0
  fi
  if ! jq empty "${output_file}" >/dev/null 2>&1; then
    printf '{}'
    return 0
  fi
  case "${action}" in
    gmail-send)
      jq -c '
        if type == "object" then
          {
            action: "gmail-send",
            artifact_type: "gmail-message",
            primary_id: (.id // null),
            message_id: (.id // null)
          } | with_entries(select(.value != null and .value != ""))
        else
          {}
        end
      ' "${output_file}"
      ;;
    drive-upload)
      jq -c '
        if type == "object" then
          {
            action: "drive-upload",
            artifact_type: "drive-file",
            primary_id: (.id // null),
            file_id: (.id // null),
            name: (.name // null)
          } | with_entries(select(.value != null and .value != ""))
        else
          {}
        end
      ' "${output_file}"
      ;;
    calendar-insert)
      jq -c '
        if type == "object" then
          {
            action: "calendar-insert",
            artifact_type: "calendar-event",
            primary_id: (.id // null),
            event_id: (.id // null)
          } | with_entries(select(.value != null and .value != ""))
        else
          {}
        end
      ' "${output_file}"
      ;;
    docs-create|docs-insert-text)
      jq -c --arg action_name "${action}" '
        if type == "object" then
          {
            action: $action_name,
            artifact_type: "google-doc",
            primary_id: (.documentId // null),
            document_id: (.documentId // null)
          } | with_entries(select(.value != null and .value != ""))
        else
          {}
        end
      ' "${output_file}"
      ;;
    sheets-create)
      jq -c '
        if type == "object" then
          {
            action: "sheets-create",
            artifact_type: "google-sheet",
            primary_id: (.spreadsheetId // null),
            spreadsheet_id: (.spreadsheetId // null)
          } | with_entries(select(.value != null and .value != ""))
        else
          {}
        end
      ' "${output_file}"
      ;;
    sheets-append)
      jq -c '
        if type == "object" then
          {
            action: "sheets-append",
            artifact_type: "google-sheet-range",
            primary_id: (.spreadsheetId // .updates.updatedRange // .updatedRange // null),
            spreadsheet_id: (.spreadsheetId // null),
            updated_range: (.updatedRange // .updates.updatedRange // null)
          } | with_entries(select(.value != null and .value != ""))
        else
          {}
        end
      ' "${output_file}"
      ;;
    *)
      jq -c '
        if type == "object" then
          {
            id: (.id // null),
            documentId: (.documentId // null),
            spreadsheetId: (.spreadsheetId // null),
            updatedRange: (.updatedRange // .updates.updatedRange // null)
          } | with_entries(select(.value != null and .value != ""))
        else
          {}
        end
      ' "${output_file}"
      ;;
  esac
}

if [[ "${resolve_only}" == "true" ]]; then
  write_meta "resolved" 0 "resolved command" "{}"
  print_command "${cmd[@]}"
  exit 0
fi

if [[ "${dry_run}" == "true" ]]; then
  case "${action}" in
    smoke|gmail-triage|meeting-prep|standup-report|weekly-digest)
      write_meta "resolved" 0 "dry-run resolved command" "{}"
      print_command "${cmd[@]}"
      exit 0
      ;;
  esac
fi

if [[ "${write_action}" == "true" && "${dry_run}" != "true" ]]; then
  if [[ "${ok_to_execute}" != "true" || "${human_approved}" != "true" ]]; then
    write_meta "skipped" 4 "write action blocked by approval gate" "{}"
    echo "ERROR: write action requires --ok-to-execute true plus explicit human approval or approved non-critical Kernel consensus" >&2
    exit 4
  fi
fi

require_cmd gws

if [[ "${action}" == "smoke" ]]; then
  run_gws_command "/dev/null" "/dev/null" "${cmd[@]}"
  write_meta "ok" 0 "adapter ready" "{}"
  echo "googleworkspace-cli adapter ready"
  exit 0
fi

if [[ -z "${meta_output_path}" ]]; then
  run_gws_command "" "" "${cmd[@]}"
  exit 0
fi

set +e
run_gws_command "${raw_output_path}" "${stderr_output_path}" "${cmd[@]}"
rc=$?
set -e

receipt_json="$(extract_receipt "${raw_output_path}")"
status="ok"
message="command completed"
if (( rc != 0 )); then
  status="error"
  message="command failed"
fi
write_meta "${status}" "${rc}" "${message}" "${receipt_json}"

if [[ -s "${raw_output_path}" ]]; then
  cat "${raw_output_path}"
fi
if (( rc != 0 )); then
  if [[ -s "${stderr_output_path}" ]]; then
    cat "${stderr_output_path}" >&2
  fi
  exit "${rc}"
fi
