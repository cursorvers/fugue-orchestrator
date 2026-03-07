#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
ADAPTER="${SCRIPT_DIR}/scripts/lib/googleworkspace-cli-adapter.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fake_gws="${tmp_dir}/gws"
cat > "${fake_gws}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
  echo "gws help"
  exit 0
fi

case "${1:-}" in
  gmail)
    if [[ "${2:-}" == "+send" ]]; then
      echo '{"id":"msg-123","labelIds":["SENT"]}'
      exit 0
    fi
    if [[ "${2:-}" == "+triage" ]]; then
      echo '{"resultSizeEstimate":3}'
      exit 0
    fi
    ;;
  workflow)
    if [[ "${2:-}" == "+meeting-prep" ]]; then
      echo '{"summary":"meeting prep ok","meetingCount":1}'
      exit 0
    fi
    ;;
esac

echo '{"status":"unexpected","argv":'"$(printf '%s\n' "$@" | jq -R . | jq -s .)"'}'
EOF
chmod +x "${fake_gws}"

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

test_write_gate_blocked() {
  local run_dir="${tmp_dir}/blocked"
  mkdir -p "${run_dir}"
  if env PATH="${tmp_dir}:${PATH}" "${ADAPTER}" \
    --action gmail-send \
    --to flux@example.com \
    --subject "Test" \
    --body "Hello" \
    --format json \
    --run-dir "${run_dir}" >/dev/null 2>"${run_dir}/stderr.log"; then
    return 1
  fi
  jq -e '.status == "skipped" and .side_effect == true and .ok_to_execute == false and .human_approved == false' \
    "${run_dir}/googleworkspace/gmail-send-meta.json" >/dev/null
}

test_write_receipt_logged() {
  local run_dir="${tmp_dir}/write-ok"
  mkdir -p "${run_dir}"
  local output
  output="$(env PATH="${tmp_dir}:${PATH}" "${ADAPTER}" \
    --action gmail-send \
    --to flux@example.com \
    --subject "Test" \
    --body "Hello" \
    --format json \
    --run-dir "${run_dir}" \
    --ok-to-execute true \
    --human-approved true)"
  echo "${output}" | jq -e '.id == "msg-123"' >/dev/null
  jq -e '.status == "ok" and .receipt.id == "msg-123" and .side_effect == true' \
    "${run_dir}/googleworkspace/gmail-send-meta.json" >/dev/null
}

test_readonly_evidence_written() {
  local run_dir="${tmp_dir}/readonly"
  mkdir -p "${run_dir}"
  local output
  output="$(env PATH="${tmp_dir}:${PATH}" "${ADAPTER}" \
    --action meeting-prep \
    --format json \
    --run-dir "${run_dir}")"
  echo "${output}" | jq -e '.meetingCount == 1' >/dev/null
  jq -e '.status == "ok" and .side_effect == false' \
    "${run_dir}/googleworkspace/meeting-prep-meta.json" >/dev/null
  test -s "${run_dir}/googleworkspace/meeting-prep.json"
}

echo "=== googleworkspace-cli-adapter.sh unit tests ==="
echo ""

assert_ok "write-gate-blocked" test_write_gate_blocked
assert_ok "write-receipt-logged" test_write_receipt_logged
assert_ok "readonly-evidence-written" test_readonly_evidence_written

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
