#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/scripts/check-googleworkspace-kernel-contract.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

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

test_table_output_contains_key_checks() {
  local out_file="${tmp_dir}/contract.tsv"
  bash "${SCRIPT}" --format table > "${out_file}"

  grep -q $'^category\tid\tstatus\tmessage$' "${out_file}" &&
    grep -q $'^policy\tauth-profiles\tok\tpolicy defines service, user, write, and extension auth profiles$' "${out_file}" &&
    grep -q $'^policy\twrite-meta-contract\tok\tpolicy defines machine-readable write metadata fields and dispositions$' "${out_file}" &&
    grep -q $'^policy\textension-runtime-enforcement\tok\tpolicy keeps extension actions out of default core phases$' "${out_file}" &&
    grep -q $'^policy\tfugue-compatibility\tok\tpolicy marks FUGUE access as non-blocking$' "${out_file}" &&
    grep -q $'^runtime\tadapter-gmail-send-preview\tok\tgmail-send preview emits normalized receipt$' "${out_file}" &&
    grep -q $'^runtime\tadapter-sheets-append\tok\tsheets-append emits normalized receipt$' "${out_file}"
}

test_json_output_reports_success() {
  local out_file="${tmp_dir}/contract.json"
  bash "${SCRIPT}" --format json > "${out_file}"

  jq -e '.ok == true' "${out_file}" >/dev/null &&
    jq -e '.checks[] | select(.id == "write-meta-contract" and .status == "ok")' "${out_file}" >/dev/null &&
    jq -e '.checks[] | select(.id == "extension-runtime-enforcement" and .status == "ok")' "${out_file}" >/dev/null &&
    jq -e '.checks[] | select(.id == "extension-decisions" and .status == "ok")' "${out_file}" >/dev/null &&
    jq -e '.checks[] | select(.id == "feed-policy-separation" and .status == "ok")' "${out_file}" >/dev/null
}

echo "=== check-googleworkspace-kernel-contract.sh unit tests ==="
echo ""

assert_ok "table-output-contains-key-checks" test_table_output_contains_key_checks
assert_ok "json-output-reports-success" test_json_output_reports_success

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
