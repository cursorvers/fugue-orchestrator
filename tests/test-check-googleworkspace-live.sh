#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/scripts/check-googleworkspace-live.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

bin_dir="${tmp_dir}/bin"
mkdir -p "${bin_dir}"

gws_log="${tmp_dir}/gws.log"
fake_gws="${bin_dir}/gws"
cat > "${fake_gws}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\t%s\n' "$*" "${GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE:-}" >> "${TMP_FAKE_GWS_LOG}"

case "$*" in
  "calendar calendarList list --params {\"maxResults\":1} --format json")
    printf '%s\n' '{"items":[]}'
    ;;
  "workflow +meeting-prep --format json")
    printf '%s\n' '{"summary":"next meeting at 10:00"}'
    ;;
  "workflow +standup-report --format json")
    printf '%s\n' 'Warning: tasks API unavailable'
    ;;
  "workflow +weekly-digest --format json")
    printf '%s\n' 'PERMISSION_DENIED: gmail.googleapis.com API not enabled' >&2
    exit 1
    ;;
  "drive files list --params {\"pageSize\":1} --format json")
    printf '%s\n' '{"files":[]}'
    ;;
  "gmail +triage --max 1 --format json")
    printf '%s\n' 'serviceusage.services.use missing for caller' >&2
    exit 1
    ;;
  *)
    printf 'unexpected command: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${fake_gws}"

assert_ok() {
  local name="$1"
  shift
  total=$((total + 1))
  if "$@"; then
    echo "ok - ${name}"
    passed=$((passed + 1))
  else
    echo "not ok - ${name}"
    failed=$((failed + 1))
  fi
}

test_json_output_and_classification() {
  local credentials_file="${tmp_dir}/service-account.json"
  local output_file="${tmp_dir}/live.json"

  printf '%s' '{"type":"service_account"}' > "${credentials_file}"
  : > "${gws_log}"

  env \
    PATH="${bin_dir}:${PATH}" \
    TMP_FAKE_GWS_LOG="${gws_log}" \
    bash "${SCRIPT}" --credentials-file "${credentials_file}" > "${output_file}"

  jq -e --arg creds "${credentials_file}" '.credentials_file == $creds' "${output_file}" >/dev/null &&
    jq -e '.checks | length == 6' "${output_file}" >/dev/null &&
    jq -e '.checks[] | select(.id == "meeting_prep" and .status == "ok")' "${output_file}" >/dev/null &&
    jq -e '.checks[] | select(.id == "standup_report" and .status == "partial")' "${output_file}" >/dev/null &&
    jq -e '.checks[] | select(.id == "weekly_digest" and .status == "blocked" and .reason == "gmail_api_disabled")' "${output_file}" >/dev/null &&
    jq -e '.checks[] | select(.id == "gmail_triage" and .status == "blocked" and .reason == "serviceusage_consumer_missing")' "${output_file}" >/dev/null &&
    [[ "$(wc -l < "${gws_log}")" -eq 6 ]] &&
    awk -F '\t' -v creds="${credentials_file}" 'NF >= 2 && $2 == creds { ok += 1 } END { exit !(ok == 6) }' "${gws_log}"
}

test_env_fallback_and_table_output() {
  local credentials_file="${tmp_dir}/env-creds.json"
  local output_file="${tmp_dir}/live.tsv"

  printf '%s' '{"type":"service_account"}' > "${credentials_file}"
  : > "${gws_log}"

  env \
    PATH="${bin_dir}:${PATH}" \
    TMP_FAKE_GWS_LOG="${gws_log}" \
    KERNEL_GWS_CREDENTIALS_FILE="${credentials_file}" \
    bash "${SCRIPT}" --format table > "${output_file}"

  grep -q $'^id\tstatus\treason\tdescription$' "${output_file}" &&
    grep -q $'^meeting_prep\tok\tunknown\tNext meeting workflow$' "${output_file}" &&
    grep -q $'^weekly_digest\tblocked\tgmail_api_disabled\tMeetings plus unread mail workflow$' "${output_file}" &&
    grep -q $'^gmail_triage\tblocked\tserviceusage_consumer_missing\tUnread inbox triage$' "${output_file}"
}

echo "=== check-googleworkspace-live.sh unit tests ==="
echo ""

assert_ok "json-output-and-classification" test_json_output_and_classification
assert_ok "env-fallback-and-table-output" test_env_fallback_and_table_output

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
