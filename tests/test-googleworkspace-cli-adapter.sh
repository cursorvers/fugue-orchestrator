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

if [[ "${GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE+x}" == "x" && -z "${GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE}" ]]; then
  echo '{"error":"empty-credentials-env"}' >&2
  exit 11
fi

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
  drive)
    if [[ "${2:-}" == "+upload" ]]; then
      echo '{"id":"file-123","name":"artifact.txt"}'
      exit 0
    fi
    ;;
  docs)
    if [[ "${2:-}" == "documents" && "${3:-}" == "create" ]]; then
      echo '{"documentId":"doc-123"}'
      exit 0
    fi
    if [[ "${2:-}" == "documents" && "${3:-}" == "batchUpdate" ]]; then
      echo '{"documentId":"doc-123"}'
      exit 0
    fi
    ;;
  sheets)
    if [[ "${2:-}" == "spreadsheets" && "${3:-}" == "values" && "${4:-}" == "append" ]]; then
      echo '{"spreadsheetId":"sheet-123","updates":{"updatedRange":"Sheet1!A1:B1"}}'
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
  jq -e '.status == "skipped" and .side_effect == true and .ok_to_execute == false and .human_approved == false and .write_disposition == "blocked"' \
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
  jq -e '.status == "ok" and .receipt.primary_id == "msg-123" and .receipt.message_id == "msg-123" and .receipt.artifact_type == "gmail-message" and .side_effect == true and .write_disposition == "applied"' \
    "${run_dir}/googleworkspace/gmail-send-meta.json" >/dev/null
}

test_write_preview_receipt_logged() {
  local run_dir="${tmp_dir}/write-preview"
  mkdir -p "${run_dir}"
  local output
  output="$(env PATH="${tmp_dir}:${PATH}" "${ADAPTER}" \
    --action gmail-send \
    --to flux@example.com \
    --subject "Test" \
    --body "Hello" \
    --format json \
    --dry-run \
    --run-dir "${run_dir}")"
  echo "${output}" | jq -e '.id == "msg-123"' >/dev/null
  jq -e '.status == "ok" and .receipt.message_id == "msg-123" and .receipt.artifact_type == "gmail-message" and .side_effect == true and .write_disposition == "preview"' \
    "${run_dir}/googleworkspace/gmail-send-meta.json" >/dev/null
}

test_drive_upload_receipt_logged() {
  local run_dir="${tmp_dir}/drive"
  local upload_file="${tmp_dir}/artifact.txt"
  mkdir -p "${run_dir}"
  printf 'artifact\n' > "${upload_file}"
  env PATH="${tmp_dir}:${PATH}" "${ADAPTER}" \
    --action drive-upload \
    --file "${upload_file}" \
    --format json \
    --name artifact.txt \
    --dry-run \
    --run-dir "${run_dir}" >/dev/null
  jq -e '.status == "ok" and .receipt.file_id == "file-123" and .receipt.primary_id == "file-123" and .receipt.artifact_type == "drive-file" and .write_disposition == "preview"' \
    "${run_dir}/googleworkspace/drive-upload-meta.json" >/dev/null
}

test_docs_receipts_logged() {
  local create_dir="${tmp_dir}/docs-create"
  local insert_dir="${tmp_dir}/docs-insert"
  mkdir -p "${create_dir}" "${insert_dir}"
  env PATH="${tmp_dir}:${PATH}" "${ADAPTER}" \
    --action docs-create \
    --title "Proof" \
    --format json \
    --run-dir "${create_dir}" \
    --ok-to-execute true \
    --human-approved true >/dev/null
  env PATH="${tmp_dir}:${PATH}" "${ADAPTER}" \
    --action docs-insert-text \
    --document-id doc-123 \
    --text "Proof" \
    --format json \
    --run-dir "${insert_dir}" \
    --ok-to-execute true \
    --human-approved true >/dev/null
  jq -e '.status == "ok" and .receipt.document_id == "doc-123" and .receipt.artifact_type == "google-doc" and .write_disposition == "applied"' \
    "${create_dir}/googleworkspace/docs-create-meta.json" >/dev/null &&
    jq -e '.status == "ok" and .receipt.document_id == "doc-123" and .receipt.artifact_type == "google-doc" and .write_disposition == "applied"' \
      "${insert_dir}/googleworkspace/docs-insert-text-meta.json" >/dev/null
}

test_sheets_append_receipt_logged() {
  local run_dir="${tmp_dir}/sheets"
  mkdir -p "${run_dir}"
  env PATH="${tmp_dir}:${PATH}" "${ADAPTER}" \
    --action sheets-append \
    --spreadsheet-id sheet-123 \
    --range Sheet1!A1:B1 \
    --values-json '[["a","b"]]' \
    --format json \
    --run-dir "${run_dir}" \
    --ok-to-execute true \
    --human-approved true >/dev/null
  jq -e '.status == "ok" and .receipt.spreadsheet_id == "sheet-123" and .receipt.updated_range == "Sheet1!A1:B1" and .receipt.artifact_type == "google-sheet-range" and .write_disposition == "applied"' \
    "${run_dir}/googleworkspace/sheets-append-meta.json" >/dev/null
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
  jq -e '.status == "ok" and .side_effect == false and .write_disposition == "readonly"' \
    "${run_dir}/googleworkspace/meeting-prep-meta.json" >/dev/null
  test -s "${run_dir}/googleworkspace/meeting-prep.json"
}

test_readonly_clears_empty_ambient_credentials_env() {
  local run_dir="${tmp_dir}/ambient-empty"
  mkdir -p "${run_dir}"
  local output
  output="$(env PATH="${tmp_dir}:${PATH}" GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE="" "${ADAPTER}" \
    --action gmail-triage \
    --format json \
    --run-dir "${run_dir}")"
  echo "${output}" | jq -e '.resultSizeEstimate == 3' >/dev/null
  jq -e '.status == "ok" and .exit_code == 0' \
    "${run_dir}/googleworkspace/gmail-triage-meta.json" >/dev/null
}

echo "=== googleworkspace-cli-adapter.sh unit tests ==="
echo ""

assert_ok "write-gate-blocked" test_write_gate_blocked
assert_ok "write-receipt-logged" test_write_receipt_logged
assert_ok "write-preview-receipt-logged" test_write_preview_receipt_logged
assert_ok "drive-upload-receipt-logged" test_drive_upload_receipt_logged
assert_ok "docs-receipts-logged" test_docs_receipts_logged
assert_ok "sheets-append-receipt-logged" test_sheets_append_receipt_logged
assert_ok "readonly-evidence-written" test_readonly_evidence_written
assert_ok "readonly-clears-empty-ambient-credentials-env" test_readonly_clears_empty_ambient_credentials_env

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
