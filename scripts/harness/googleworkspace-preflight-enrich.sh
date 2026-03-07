#!/usr/bin/env bash
set -euo pipefail

ISSUE_NUMBER="${ISSUE_NUMBER:-}"
ISSUE_TITLE="${ISSUE_TITLE:-}"
ISSUE_BODY="${ISSUE_BODY:-}"
WORKSPACE_ACTIONS="${WORKSPACE_ACTIONS:-}"
WORKSPACE_DOMAINS="${WORKSPACE_DOMAINS:-}"
WORKSPACE_REASON="${WORKSPACE_REASON:-}"
WORKSPACE_SUGGESTED_PHASES="${WORKSPACE_SUGGESTED_PHASES:-}"
OUT_DIR="${OUT_DIR:-.fugue/pre-implement}"
RUN_DIR="${RUN_DIR:-${OUT_DIR}/googleworkspace-run}"
REPORT_PATH="${REPORT_PATH:-${OUT_DIR}/issue-${ISSUE_NUMBER}-googleworkspace.md}"
ADAPTER="${ADAPTER:-scripts/lib/googleworkspace-cli-adapter.sh}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

append_csv_unique() {
  local current="$1"
  local value="$2"
  if [[ -z "${value}" ]]; then
    printf '%s' "${current}"
    return 0
  fi
  case ",${current}," in
    *,"${value}",*)
      printf '%s' "${current}"
      ;;
    *)
      if [[ -z "${current}" ]]; then
        printf '%s' "${value}"
      else
        printf '%s,%s' "${current}" "${value}"
      fi
      ;;
  esac
}

sanitize_summary() {
  printf '%s' "${1:-}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+|[[:space:]]+$//g'
}

is_mailbox_action() {
  case "${1:-}" in
    gmail-triage|weekly-digest)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

select_credentials_file() {
  local action="$1"

  if is_mailbox_action "${action}"; then
    if [[ -n "${user_credentials_file}" ]]; then
      printf '%s' "${user_credentials_file}"
      return 0
    fi
    if [[ -n "${service_credentials_file}" ]]; then
      printf '%s' "${service_credentials_file}"
      return 0
    fi
  else
    if [[ -n "${service_credentials_file}" ]]; then
      printf '%s' "${service_credentials_file}"
      return 0
    fi
    if [[ -n "${user_credentials_file}" ]]; then
      printf '%s' "${user_credentials_file}"
      return 0
    fi
  fi

  printf ''
}

extract_summary() {
  local action="$1"
  local raw_file="$2"
  if [[ ! -s "${raw_file}" ]]; then
    printf ''
    return 0
  fi
  if ! jq empty "${raw_file}" >/dev/null 2>&1; then
    head -c 300 "${raw_file}" | tr '\n' ' '
    return 0
  fi
  case "${action}" in
    meeting-prep)
      jq -r '(.summary // ("meetingCount=" + ((.meetingCount // 0)|tostring)))' "${raw_file}" 2>/dev/null || true
      ;;
    standup-report)
      jq -r '(.summary // ("meetings=" + ((.meetingCount // (.meetings|length) // 0)|tostring)))' "${raw_file}" 2>/dev/null || true
      ;;
    weekly-digest)
      jq -r '(.summary // ("meetingCount=" + ((.meetingCount // 0)|tostring) + ", unreadEmails=" + ((.unreadEmails // 0)|tostring)))' "${raw_file}" 2>/dev/null || true
      ;;
    gmail-triage)
      jq -r '("resultSizeEstimate=" + ((.resultSizeEstimate // 0)|tostring))' "${raw_file}" 2>/dev/null || true
      ;;
    *)
      jq -r '(.summary // .message // .status // "ok")' "${raw_file}" 2>/dev/null || true
      ;;
  esac
}

require_cmd jq
[[ -n "${ISSUE_NUMBER}" ]] || fail "ISSUE_NUMBER is required"
[[ -x "${ADAPTER}" ]] || fail "adapter missing or not executable: ${ADAPTER}"

mkdir -p "${OUT_DIR}" "${RUN_DIR}"

service_credentials_file="${GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE:-}"
service_tmp_credentials=""
if [[ -z "${service_credentials_file}" && -n "${GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON:-}" ]]; then
  service_tmp_credentials="$(mktemp)"
  printf '%s' "${GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON}" > "${service_tmp_credentials}"
  service_credentials_file="${service_tmp_credentials}"
fi

user_credentials_file="${GOOGLE_WORKSPACE_USER_CREDENTIALS_FILE:-}"
user_tmp_credentials=""
if [[ -z "${user_credentials_file}" && -n "${GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON:-}" ]]; then
  user_tmp_credentials="$(mktemp)"
  printf '%s' "${GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON}" > "${user_tmp_credentials}"
  user_credentials_file="${user_tmp_credentials}"
fi

credentials_available="false"
local_oauth_available="false"
if [[ -n "${service_credentials_file}" || -n "${user_credentials_file}" ]]; then
  credentials_available="true"
elif [[ -f "${HOME}/.config/gws/credentials.enc" && -f "${HOME}/.config/gws/client_secret.json" ]]; then
  credentials_available="true"
  local_oauth_available="true"
fi

cleanup() {
  if [[ -n "${service_tmp_credentials}" && -f "${service_tmp_credentials}" ]]; then
    rm -f "${service_tmp_credentials}"
  fi
  if [[ -n "${user_tmp_credentials}" && -f "${user_tmp_credentials}" ]]; then
    rm -f "${user_tmp_credentials}"
  fi
}
trap cleanup EXIT

actions_csv=""
IFS=',' read -r -a requested_actions <<< "${WORKSPACE_ACTIONS}"
for action in "${requested_actions[@]}"; do
  action="$(printf '%s' "${action}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  case "${action}" in
    meeting-prep|standup-report|weekly-digest|gmail-triage)
      actions_csv="$(append_csv_unique "${actions_csv}" "${action}")"
      ;;
  esac
done

report_status="ok"
summary_csv=""
rows=()

if [[ -z "${actions_csv}" ]]; then
  report_status="skipped"
  rows+=("| none | skipped | No readonly Google Workspace action was suggested. |")
  summary_csv="No readonly Google Workspace action was suggested."
elif [[ "${credentials_available}" != "true" ]]; then
  report_status="skipped"
  rows+=("| auth | skipped | No Google Workspace credentials were available for readonly preflight. |")
  summary_csv="No Google Workspace credentials were available for readonly preflight."
else
  IFS=',' read -r -a actions <<< "${actions_csv}"
  for action in "${actions[@]}"; do
    selected_credentials_file="$(select_credentials_file "${action}")"
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    set +e
    if [[ -n "${selected_credentials_file}" ]]; then
      bash "${ADAPTER}" \
        --action "${action}" \
        --format json \
        --run-dir "${RUN_DIR}" \
        --credentials-file "${selected_credentials_file}" \
        > "${stdout_file}" 2> "${stderr_file}"
    elif [[ "${local_oauth_available}" == "true" ]]; then
      bash "${ADAPTER}" \
        --action "${action}" \
        --format json \
        --run-dir "${RUN_DIR}" \
        > "${stdout_file}" 2> "${stderr_file}"
    else
      mkdir -p "${RUN_DIR}/googleworkspace"
      printf '%s' '{"status":"skipped","message":"no matching credentials available"}' > "${RUN_DIR}/googleworkspace/${action}-meta.json"
      echo "no matching credentials available" > "${stderr_file}"
      rc=1
    fi
    if [[ -z "${rc:-}" ]]; then rc=$?; fi
    set -e

    meta_file="${RUN_DIR}/googleworkspace/${action}-meta.json"
    raw_file="${RUN_DIR}/googleworkspace/${action}.json"
    status="error"
    message="command failed"
    if [[ -f "${meta_file}" ]]; then
      status="$(jq -r '.status // "error"' "${meta_file}")"
      message="$(jq -r '.message // ""' "${meta_file}")"
    fi
    summary="$(sanitize_summary "$(extract_summary "${action}" "${raw_file}")")"
    if [[ -z "${summary}" ]]; then
      summary="$(sanitize_summary "$(head -c 300 "${stderr_file}")")"
    fi
    if [[ -z "${summary}" ]]; then
      summary="${message}"
    fi
    rows+=("| ${action} | ${status} | ${summary} |")

    if [[ "${status}" == "ok" ]]; then
      summary_csv="$(append_csv_unique "${summary_csv}" "${action}: ${summary}")"
    elif [[ "${status}" == "error" && "${report_status}" == "ok" ]]; then
      report_status="partial"
    fi
    if (( rc != 0 )) && [[ "${report_status}" == "ok" ]]; then
      report_status="partial"
    fi
    unset rc

    rm -f "${stdout_file}" "${stderr_file}"
  done
fi

if [[ -z "${summary_csv}" ]]; then
  summary_csv="No successful Google Workspace preflight result."
fi

{
  echo "# Issue #${ISSUE_NUMBER} Google Workspace Artifact"
  echo
  echo "- status: ${report_status}"
  echo "- issue: ${ISSUE_TITLE}"
  echo "- suggested phases: ${WORKSPACE_SUGGESTED_PHASES:-none}"
  echo "- actions: ${actions_csv:-none}"
  echo "- domains: ${WORKSPACE_DOMAINS:-none}"
  echo "- reason: ${WORKSPACE_REASON:-none}"
  echo "- run dir: ${RUN_DIR}"
  echo
  echo "## Summary"
  echo
  echo "${summary_csv}"
  echo
  echo "## Action Results"
  echo
  echo "| action | status | summary |"
  echo "|---|---|---|"
  printf '%s\n' "${rows[@]}"
  echo
  echo "## Notes"
  echo
  echo "- Google Workspace remains peripheral evidence, not control-plane truth."
  echo "- Gmail and weekly digest actions prefer GOOGLE_WORKSPACE_USER_CREDENTIALS_FILE/JSON when supplied."
  echo "- Errors on Gmail actions under service-account mode are expected when mailbox access is unavailable."
} > "${REPORT_PATH}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "workspace_preflight_status=${report_status}"
    echo "workspace_report_path=${REPORT_PATH}"
    echo "workspace_run_dir=${RUN_DIR}"
    echo "workspace_summary<<EOF"
    echo "${summary_csv}"
    echo "EOF"
  } >> "${GITHUB_OUTPUT}"
fi
