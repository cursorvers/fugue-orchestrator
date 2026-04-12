#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/scripts/harness/googleworkspace-preflight-enrich.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fake_adapter="${tmp_dir}/googleworkspace-cli-adapter.sh"
cat > "${fake_adapter}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

action=""
run_dir=""
credentials_file=""

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --action)
      action="${2:-}"
      shift 2
      ;;
    --run-dir)
      run_dir="${2:-}"
      shift 2
      ;;
    --credentials-file)
      credentials_file="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

mkdir -p "${run_dir}/googleworkspace"
if [[ -n "${TMP_ADAPTER_CALLS_LOG:-}" ]]; then
  printf '%s\n' "${action}" >> "${TMP_ADAPTER_CALLS_LOG}"
fi
if [[ -n "${credentials_file}" && -n "${TMP_ADAPTER_CREDENTIALS_LOG:-}" ]]; then
  printf '%s\t%s\n' "${action}" "$(tr -d '\n' < "${credentials_file}")" >> "${TMP_ADAPTER_CREDENTIALS_LOG}"
fi

meta_file="${run_dir}/googleworkspace/${action}-meta.json"
raw_file="${run_dir}/googleworkspace/${action}.json"

case "${action}" in
  meeting-prep)
    printf '%s' '{"summary":"next meeting at 10:00","meetingCount":1}' > "${raw_file}"
    printf '%s' '{"status":"ok","message":"ok"}' > "${meta_file}"
    cat "${raw_file}"
    ;;
  weekly-digest)
    if [[ -n "${credentials_file}" ]] && grep -q '"type":"authorized_user"' "${credentials_file}"; then
      printf '%s' '{"summary":"meetingCount=6, unreadEmails=14","meetingCount":6,"unreadEmails":14}' > "${raw_file}"
      printf '%s' '{"status":"ok","message":"ok"}' > "${meta_file}"
      cat "${raw_file}"
    else
      printf '%s' '{"status":"error","message":"mailbox unavailable"}' > "${meta_file}"
      echo "mailbox unavailable" >&2
      exit 1
    fi
    ;;
  gmail-triage)
    if [[ -n "${credentials_file}" ]] && grep -q '"type":"authorized_user"' "${credentials_file}"; then
      printf '%s' '{"resultSizeEstimate":3}' > "${raw_file}"
      printf '%s' '{"status":"ok","message":"ok"}' > "${meta_file}"
      cat "${raw_file}"
    else
      printf '%s' '{"status":"error","message":"mailbox unavailable"}' > "${meta_file}"
      echo "mailbox unavailable" >&2
      exit 1
    fi
    ;;
  *)
    printf '%s' '{"status":"error","message":"unsupported action"}' > "${meta_file}"
    echo "unsupported action" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${fake_adapter}"

assert_ok() {
  local test_name="$1"
  shift
  total=$((total + 1))
  if "$@"; then
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  else
    echo "FAIL [${test_name}]"
    failed=$((failed + 1))
  fi
}

test_skips_without_credentials() {
  local work_dir="${tmp_dir}/skip"
  local home_dir="${work_dir}/home"
  local calls_log="${work_dir}/calls.log"
  local output_file="${work_dir}/github-output.txt"
  local report_path="${work_dir}/report.md"

  mkdir -p "${work_dir}" "${home_dir}"

  env \
    HOME="${home_dir}" \
    TMP_ADAPTER_CALLS_LOG="${calls_log}" \
    ISSUE_NUMBER="41" \
    ISSUE_TITLE="Skip test" \
    WORKSPACE_ACTIONS="meeting-prep" \
    WORKSPACE_REASON="meeting context requested" \
    WORKSPACE_SUGGESTED_PHASES="preflight-enrich" \
    REPORT_PATH="${report_path}" \
    OUT_DIR="${work_dir}" \
    RUN_DIR="${work_dir}/run" \
    GITHUB_OUTPUT="${output_file}" \
    ADAPTER="${fake_adapter}" \
    bash "${SCRIPT}" >/dev/null

  grep -q '^workspace_preflight_status=skipped$' "${output_file}" &&
    grep -q 'No Google Workspace credentials were available for readonly preflight\.' "${report_path}" &&
    [[ ! -s "${calls_log}" ]]
}

test_partial_report_and_outputs() {
  local work_dir="${tmp_dir}/partial"
  local home_dir="${work_dir}/home"
  local calls_log="${work_dir}/calls.log"
  local credentials_log="${work_dir}/credentials.json"
  local output_file="${work_dir}/github-output.txt"
  local report_path="${work_dir}/report.md"

  mkdir -p "${work_dir}" "${home_dir}"

  env \
    HOME="${home_dir}" \
    TMP_ADAPTER_CALLS_LOG="${calls_log}" \
    TMP_ADAPTER_CREDENTIALS_LOG="${credentials_log}" \
    GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON='{"type":"service_account","project_id":"demo"}' \
    ISSUE_NUMBER="42" \
    ISSUE_TITLE="Meeting and inbox context" \
    ISSUE_BODY="Need meeting prep and inbox triage." \
    WORKSPACE_ACTIONS="meeting-prep,gmail-triage,docs-create" \
    WORKSPACE_DOMAINS="calendar,drive,docs,gmail" \
    WORKSPACE_REASON="Issue mentions meetings and unread mail." \
    WORKSPACE_SUGGESTED_PHASES="preflight-enrich" \
    REPORT_PATH="${report_path}" \
    OUT_DIR="${work_dir}" \
    RUN_DIR="${work_dir}/run" \
    GITHUB_OUTPUT="${output_file}" \
    ADAPTER="${fake_adapter}" \
    bash "${SCRIPT}" >/dev/null

  grep -q '^workspace_preflight_status=partial$' "${output_file}" &&
    grep -q '^workspace_report_path='"${report_path}"'$' "${output_file}" &&
    grep -q 'meeting-prep: next meeting at 10:00' "${output_file}" &&
    grep -q -- '- status: partial' "${report_path}" &&
    grep -q '| meeting-prep | ok | next meeting at 10:00 |' "${report_path}" &&
    grep -q '| gmail-triage | error | mailbox unavailable |' "${report_path}" &&
    ! grep -q 'docs-create' "${report_path}" &&
    grep -q '^meeting-prep$' "${calls_log}" &&
    grep -q '^gmail-triage$' "${calls_log}" &&
    ! grep -q 'docs-create' "${calls_log}" &&
    grep -q $'^meeting-prep\t.*"type":"service_account"' "${credentials_log}" &&
    grep -q $'^gmail-triage\t.*"type":"service_account"' "${credentials_log}"
}

test_prefers_user_oauth_for_mailbox_actions() {
  local work_dir="${tmp_dir}/user-oauth"
  local home_dir="${work_dir}/home"
  local calls_log="${work_dir}/calls.log"
  local credentials_log="${work_dir}/credentials.log"
  local output_file="${work_dir}/github-output.txt"
  local report_path="${work_dir}/report.md"

  mkdir -p "${work_dir}" "${home_dir}"

  env \
    HOME="${home_dir}" \
    TMP_ADAPTER_CALLS_LOG="${calls_log}" \
    TMP_ADAPTER_CREDENTIALS_LOG="${credentials_log}" \
    GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON='{"type":"service_account","project_id":"demo"}' \
    GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON='{"type":"authorized_user","client_id":"abc","client_secret":"def","refresh_token":"ghi"}' \
    ISSUE_NUMBER="43" \
    ISSUE_TITLE="Meeting and inbox context" \
    ISSUE_BODY="Need meeting prep and inbox triage." \
    WORKSPACE_ACTIONS="meeting-prep,gmail-triage" \
    WORKSPACE_DOMAINS="calendar,gmail" \
    WORKSPACE_REASON="Issue mentions meetings and unread mail." \
    WORKSPACE_SUGGESTED_PHASES="preflight-enrich" \
    REPORT_PATH="${report_path}" \
    OUT_DIR="${work_dir}" \
    RUN_DIR="${work_dir}/run" \
    GITHUB_OUTPUT="${output_file}" \
    ADAPTER="${fake_adapter}" \
    bash "${SCRIPT}" >/dev/null

  grep -q '^workspace_preflight_status=ok$' "${output_file}" &&
    grep -q 'meeting-prep: next meeting at 10:00' "${output_file}" &&
    grep -q 'gmail-triage: resultSizeEstimate=3' "${output_file}" &&
    grep -q -- '- status: ok' "${report_path}" &&
    grep -q '| meeting-prep | ok | next meeting at 10:00 |' "${report_path}" &&
    grep -q '| gmail-triage | ok | resultSizeEstimate=3 |' "${report_path}" &&
    grep -q $'^meeting-prep\t.*"type":"service_account"' "${credentials_log}" &&
    grep -q $'^gmail-triage\t.*"type":"authorized_user"' "${credentials_log}"
}

test_prefers_user_oauth_for_weekly_digest() {
  local work_dir="${tmp_dir}/weekly-digest"
  local home_dir="${work_dir}/home"
  local calls_log="${work_dir}/calls.log"
  local credentials_log="${work_dir}/credentials.log"
  local output_file="${work_dir}/github-output.txt"
  local report_path="${work_dir}/report.md"

  mkdir -p "${work_dir}" "${home_dir}"

  env \
    HOME="${home_dir}" \
    TMP_ADAPTER_CALLS_LOG="${calls_log}" \
    TMP_ADAPTER_CREDENTIALS_LOG="${credentials_log}" \
    GOOGLE_WORKSPACE_CLI_CREDENTIALS_JSON='{"type":"service_account","project_id":"demo"}' \
    GOOGLE_WORKSPACE_USER_CREDENTIALS_JSON='{"type":"authorized_user","client_id":"abc","client_secret":"def","refresh_token":"ghi"}' \
    ISSUE_NUMBER="44" \
    ISSUE_TITLE="Weekly digest context" \
    ISSUE_BODY="Need weekly digest and meeting prep." \
    WORKSPACE_ACTIONS="meeting-prep,weekly-digest" \
    WORKSPACE_DOMAINS="calendar,gmail,drive" \
    WORKSPACE_REASON="Issue mentions weekly digest and meeting context." \
    WORKSPACE_SUGGESTED_PHASES="preflight-enrich" \
    REPORT_PATH="${report_path}" \
    OUT_DIR="${work_dir}" \
    RUN_DIR="${work_dir}/run" \
    GITHUB_OUTPUT="${output_file}" \
    ADAPTER="${fake_adapter}" \
    bash "${SCRIPT}" >/dev/null

  grep -q '^workspace_preflight_status=ok$' "${output_file}" &&
    grep -q 'meeting-prep: next meeting at 10:00' "${output_file}" &&
    grep -q 'weekly-digest: meetingCount=6, unreadEmails=14' "${output_file}" &&
    grep -q -- '- status: ok' "${report_path}" &&
    grep -q '| meeting-prep | ok | next meeting at 10:00 |' "${report_path}" &&
    grep -q '| weekly-digest | ok | meetingCount=6, unreadEmails=14 |' "${report_path}" &&
    grep -q $'^meeting-prep\t.*"type":"service_account"' "${credentials_log}" &&
    grep -q $'^weekly-digest\t.*"type":"authorized_user"' "${credentials_log}" &&
    grep -q '^meeting-prep$' "${calls_log}" &&
    grep -q '^weekly-digest$' "${calls_log}"
}

echo "=== googleworkspace-preflight-enrich.sh unit tests ==="
echo ""

assert_ok "skips-without-credentials" test_skips_without_credentials
assert_ok "partial-report-and-outputs" test_partial_report_and_outputs
assert_ok "prefers-user-oauth-for-mailbox-actions" test_prefers_user_oauth_for_mailbox_actions
assert_ok "prefers-user-oauth-for-weekly-digest" test_prefers_user_oauth_for_weekly_digest

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
