#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_RUN_ID="receipt-test"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
export FUGUE_APPROVED_WORKSPACE_ROOTS="${ROOT_DIR}/.fugue:${TMP_DIR}/approved"
export KERNEL_RUNTIME_WORKSPACE_ROOT="${TMP_DIR}/approved/runtime-workspaces"
export KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR="${TMP_DIR}/approved/runtime-receipts"

out="$(bash "${SCRIPT}" write 6 codex,glm,gemini-cli normal smoke)"
grep -Fq 'present: true' <<<"${out}"
grep -Fq 'lane count: 6' <<<"${out}"
grep -Fq 'active model count: 3' <<<"${out}"
grep -Fq 'manifest lane count: 6' <<<"${out}"
grep -Fq 'has agent labels: true' <<<"${out}"
grep -Fq 'has subagent labels: true' <<<"${out}"
grep -Fq 'specialist count: 1' <<<"${out}"

path="$(bash "${SCRIPT}" path)"
test -f "${path}"
jq -e '
  .run_id == "receipt-test" and
  .mode == "normal" and
  .has_codex == true and
  .has_glm == true and
  .specialist_count == 1 and
  .manifest_lane_count == 6 and
  .has_agent_labels == true and
  .has_subagent_labels == true
' "${path}" >/dev/null

ledger_out="$(bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" status)"
grep -Fq 'state: running' <<<"${ledger_out}"
workspace_receipt_path="$(bash "${WORKSPACE_SCRIPT}" receipt-path)"
[[ -f "${workspace_receipt_path}" ]]

echo "kernel bootstrap receipt check passed"
