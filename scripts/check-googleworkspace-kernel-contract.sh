#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY_FILE="${ROOT_DIR}/config/integrations/googleworkspace-kernel-policy.json"
FEED_POLICY_FILE="${ROOT_DIR}/config/integrations/googleworkspace-feed-policy.json"
DESIGN_DOC="${ROOT_DIR}/docs/kernel-googleworkspace-integration-design.md"
FEED_DOC="${ROOT_DIR}/docs/googleworkspace-feed-sync-design.md"
ADAPTER="${ROOT_DIR}/scripts/lib/googleworkspace-cli-adapter.sh"

format="table"

usage() {
  cat <<'EOF'
Usage:
  scripts/check-googleworkspace-kernel-contract.sh [options]

Validate the local Kernel Google Workspace contract for Issues 3-5 and confirm
that the FUGUE-facing cached feed path remains non-blocking.

Checks include:
- machine-readable auth / receipt / extension policy
- docs coverage for receipt contract, extension triage, and FUGUE boundary
- runtime adapter receipt normalization using a fake `gws` binary

Options:
  --format <table|json>   Output format (default: table)
  -h, --help              Show help.
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
    --format)
      format="${2:-table}"
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
  table|json) ;;
  *) fail "invalid --format=${format}" ;;
esac

require_cmd jq
require_cmd rg
require_cmd mktemp

[[ -f "${POLICY_FILE}" ]] || fail "missing policy file: ${POLICY_FILE}"
[[ -f "${FEED_POLICY_FILE}" ]] || fail "missing feed policy file: ${FEED_POLICY_FILE}"
[[ -f "${DESIGN_DOC}" ]] || fail "missing design doc: ${DESIGN_DOC}"
[[ -f "${FEED_DOC}" ]] || fail "missing feed sync doc: ${FEED_DOC}"
[[ -f "${ADAPTER}" ]] || fail "missing adapter: ${ADAPTER}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
results_file="${tmp_dir}/results.jsonl"

record_check() {
  local id="$1"
  local category="$2"
  local status="$3"
  local message="$4"
  jq -cn \
    --arg id "${id}" \
    --arg category "${category}" \
    --arg status "${status}" \
    --arg message "${message}" \
    '{id:$id, category:$category, status:$status, message:$message}' >> "${results_file}"
}

run_static_check() {
  local id="$1"
  local category="$2"
  local message="$3"
  shift 3
  if "$@" >/dev/null 2>&1; then
    record_check "${id}" "${category}" "ok" "${message}"
  else
    record_check "${id}" "${category}" "error" "${message}"
  fi
}

run_policy_jq() {
  local expr="$1"
  jq -e "${expr}" "${POLICY_FILE}"
}

run_feed_policy_jq() {
  local expr="$1"
  jq -e "${expr}" "${FEED_POLICY_FILE}"
}

run_doc_rg() {
  local pattern="$1"
  local file="$2"
  rg -q "${pattern}" "${file}"
}

run_static_check "auth-profiles" "policy" \
  "policy defines service, user, write, and extension auth profiles" \
  run_policy_jq '.auth_profiles["service-account-readonly"] and .auth_profiles["user-oauth-readonly"] and .auth_profiles["user-oauth-write"] and .auth_profiles["extension-only"]'

run_static_check "receipt-contract" "policy" \
  "policy defines normalized write receipt fields" \
  run_policy_jq '.receipt_contract.required_common_fields == ["action","artifact_type","primary_id"] and .receipt_contract.per_action["gmail-send"].required_receipt_fields == ["primary_id","message_id"] and .receipt_contract.per_action["drive-upload"].required_receipt_fields == ["primary_id","file_id"] and .receipt_contract.per_action["docs-create"].required_receipt_fields == ["primary_id","document_id"] and .receipt_contract.per_action["sheets-append"].required_receipt_fields == ["primary_id","spreadsheet_id","updated_range"]'

run_static_check "write-meta-contract" "policy" \
  "policy defines machine-readable write metadata fields and dispositions" \
  run_policy_jq '.write_meta_contract.required_common_meta_fields == ["side_effect","write_disposition","ok_to_execute","human_approved","approval_source","receipt"] and .write_meta_contract.allowed_write_dispositions == ["preview","applied","blocked","readonly","resolved"]'

run_static_check "extension-decisions" "policy" \
  "policy defines explicit keep/defer/drop decisions for extension lanes" \
  run_policy_jq '.extension_lane_policy.tasks.decision == "defer" and .extension_lane_policy.pubsub.decision == "drop" and .extension_lane_policy.presentations.decision == "defer"'

run_static_check "extension-runtime-enforcement" "policy" \
  "policy keeps extension actions out of default core phases" \
  run_policy_jq '
    . as $root |
    ($root.runtime_enforcement.extension_actions == ["tasks","pubsub","presentations"]) and
    (
      [ $root.phase_policy[]
        | select(.phase as $phase | $root.runtime_enforcement.core_phases_excluding_extensions | index($phase) != null)
        | (.allowed_actions // [])[]?
        | select(IN("tasks","pubsub","presentations"))
      ] | length
    ) == 0 and
    (
      [ $root.phase_policy[]
        | select(.phase as $phase | $root.runtime_enforcement.core_phases_excluding_extensions | index($phase) != null)
        | (.auth_profiles // [])[]?
        | select(. == "extension-only")
      ] | length
    ) == 0
  '

run_static_check "fugue-compatibility" "policy" \
  "policy marks FUGUE access as non-blocking" \
  run_policy_jq '.compatibility.fugue_access.non_blocking == true and .compatibility.fugue_access.shared_feed_profiles == ["morning-brief-shared"]'

run_static_check "feed-policy-separation" "feed-policy" \
  "feed policy keeps shared and personal profiles separated for Kernel/FUGUE" \
  run_feed_policy_jq '(.profiles["morning-brief-shared"].summary_purpose | contains("Kernel/FUGUE")) and .profiles["morning-brief-shared"].workflow_target == "shared" and .profiles["morning-brief-personal"].workflow_target == "personal" and .profiles["weekly-digest-personal"].workflow_target == "personal"'

run_static_check "design-receipt-contract" "docs" \
  "design doc captures the workspace write receipt contract" \
  run_doc_rg '## Workspace Write Receipt Contract' "${DESIGN_DOC}"

run_static_check "design-extension-triage" "docs" \
  "design doc captures extension lane triage" \
  run_doc_rg '## Extension Lane Triage' "${DESIGN_DOC}"

run_static_check "design-fugue-boundary" "docs" \
  "design doc captures the FUGUE compatibility boundary" \
  run_doc_rg '## FUGUE Compatibility Boundary' "${DESIGN_DOC}"

run_static_check "feed-doc-kernel-fugue" "docs" \
  "feed sync doc still documents Kernel/FUGUE reflection" \
  run_doc_rg '## Reflection Into Kernel/FUGUE' "${FEED_DOC}"

fake_bin_dir="${tmp_dir}/bin"
mkdir -p "${fake_bin_dir}"
fake_gws="${fake_bin_dir}/gws"
cat > "${fake_gws}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  "gmail +send --to flux@example.com --subject Test --body Hello --format json --dry-run")
    printf '%s\n' '{"id":"msg-preview-123"}'
    ;;
  "drive +upload "*" --format json --name proof.txt --dry-run")
    printf '%s\n' '{"id":"file-preview-123","name":"proof.txt"}'
    ;;
  "docs documents create --json {\"title\":\"Write proof\"} --format json")
    printf '%s\n' '{"documentId":"doc-123"}'
    ;;
  "docs documents batchUpdate --params {\"documentId\":\"doc-123\"} --json {\"requests\":[{\"insertText\":{\"location\":{\"index\":1},\"text\":\"Proof\"}}]} --format json")
    printf '%s\n' '{"documentId":"doc-123"}'
    ;;
  "sheets spreadsheets values append --params {\"spreadsheetId\":\"sheet-123\",\"range\":\"Sheet1!A1:B1\",\"valueInputOption\":\"RAW\"} --json [[\"x\",\"y\"]] --format json")
    printf '%s\n' '{"spreadsheetId":"sheet-123","updates":{"updatedRange":"Sheet1!A1:B1"}}'
    ;;
  *)
    printf 'unexpected command: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${fake_gws}"

credentials_file="${tmp_dir}/creds.json"
printf '%s' '{"type":"authorized_user"}' > "${credentials_file}"
upload_file="${tmp_dir}/proof.txt"
printf 'proof\n' > "${upload_file}"
runtime_dir="${tmp_dir}/runtime"
mkdir -p "${runtime_dir}"

run_adapter_check() {
  local id="$1"
  local message="$2"
  shift 2
  local meta_file="$1"
  shift
  if env PATH="${fake_bin_dir}:${PATH}" GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE="${credentials_file}" bash "${ADAPTER}" "$@" >/dev/null 2>"${tmp_dir}/${id}.stderr"; then
    if jq -e --arg action_id "${id}" '
      if $action_id == "adapter-gmail-send-preview" then
        .status == "ok" and .write_disposition == "preview" and .receipt.artifact_type == "gmail-message" and .receipt.primary_id == "msg-preview-123" and .receipt.message_id == "msg-preview-123"
      elif $action_id == "adapter-drive-upload-preview" then
        .status == "ok" and .write_disposition == "preview" and .receipt.artifact_type == "drive-file" and .receipt.primary_id == "file-preview-123" and .receipt.file_id == "file-preview-123"
      elif $action_id == "adapter-docs-create" then
        .status == "ok" and .write_disposition == "applied" and .receipt.artifact_type == "google-doc" and .receipt.document_id == "doc-123"
      elif $action_id == "adapter-docs-insert-text" then
        .status == "ok" and .write_disposition == "applied" and .receipt.artifact_type == "google-doc" and .receipt.document_id == "doc-123"
      elif $action_id == "adapter-sheets-append" then
        .status == "ok" and .write_disposition == "applied" and .receipt.artifact_type == "google-sheet-range" and .receipt.spreadsheet_id == "sheet-123" and .receipt.updated_range == "Sheet1!A1:B1"
      else
        false
      end
    ' "${meta_file}" >/dev/null 2>&1; then
      record_check "${id}" "runtime" "ok" "${message}"
    else
      record_check "${id}" "runtime" "error" "${message}"
    fi
  else
    record_check "${id}" "runtime" "error" "${message}"
  fi
}

run_adapter_check "adapter-gmail-send-preview" "gmail-send preview emits normalized receipt" \
  "${runtime_dir}/gmail/googleworkspace/gmail-send-meta.json" \
  --action gmail-send --to flux@example.com --subject Test --body Hello --format json --dry-run --run-dir "${runtime_dir}/gmail"

run_adapter_check "adapter-drive-upload-preview" "drive-upload preview emits normalized receipt" \
  "${runtime_dir}/drive/googleworkspace/drive-upload-meta.json" \
  --action drive-upload --file "${upload_file}" --name proof.txt --format json --dry-run --run-dir "${runtime_dir}/drive"

run_adapter_check "adapter-docs-create" "docs-create emits normalized receipt" \
  "${runtime_dir}/docs-create/googleworkspace/docs-create-meta.json" \
  --action docs-create --title "Write proof" --format json --run-dir "${runtime_dir}/docs-create" --ok-to-execute true --human-approved true

run_adapter_check "adapter-docs-insert-text" "docs-insert-text emits normalized receipt" \
  "${runtime_dir}/docs-insert/googleworkspace/docs-insert-text-meta.json" \
  --action docs-insert-text --document-id doc-123 --text Proof --format json --run-dir "${runtime_dir}/docs-insert" --ok-to-execute true --human-approved true

run_adapter_check "adapter-sheets-append" "sheets-append emits normalized receipt" \
  "${runtime_dir}/sheets/googleworkspace/sheets-append-meta.json" \
  --action sheets-append --spreadsheet-id sheet-123 --range Sheet1!A1:B1 --values-json '[["x","y"]]' --format json --run-dir "${runtime_dir}/sheets" --ok-to-execute true --human-approved true

if [[ "${format}" == "json" ]]; then
  jq -s '{checks:., ok: (all(.[]; .status == "ok"))}' "${results_file}"
  exit 0
fi

jq -r '[.category, .id, .status, .message] | @tsv' "${results_file}" \
  | awk 'BEGIN { print "category\tid\tstatus\tmessage" } { print }'
