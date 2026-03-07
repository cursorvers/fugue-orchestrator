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
  cat "${credentials_file}" > "${TMP_ADAPTER_CREDENTIALS_LOG}"
fi

meta_file="${run_dir}/googleworkspace/${action}-meta.json"
raw_file="${run_dir}/googleworkspace/${action}.json"

case "${action}" in
  meeting-prep)
    printf '%s' '{"summary":"next meeting at 10:00","meetingCount":1}' > "${raw_file}"
    printf '%s' '{"status":"ok","message":"ok"}' > "${meta_file}"
    cat "${raw_file}"
    ;;
  gmail-triage)
    printf '%s' '{"status":"error","message":"mailbox unavailable"}' > "${meta_file}"
    echo "mailbox unavailable" >&2
    exit 1
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
    grep -q '"type":"service_account"' "${credentials_log}"
}

echo "=== googleworkspace-preflight-enrich.sh unit tests ==="
echo ""

assert_ok "skips-without-credentials" test_skips_without_credentials
assert_ok "partial-report-and-outputs" test_partial_report_and_outputs

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
