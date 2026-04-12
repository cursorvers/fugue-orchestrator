#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"
CONSENSUS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-consensus-evidence.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
export KERNEL_RUN_ID="workspace-run-42"
export KERNEL_PROJECT="fugue-orchestrator"
export KERNEL_PURPOSE="runtime-substrate"
export KERNEL_RUNTIME="kernel"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/bootstrap-receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_STATE_ROOT="${TMP_DIR}/state"
export FUGUE_APPROVED_WORKSPACE_ROOTS="${ROOT_DIR}/.fugue:${TMP_DIR}/approved"
export KERNEL_RUNTIME_WORKSPACE_ROOT="${TMP_DIR}/approved/runtime-workspaces"
export KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR="${TMP_DIR}/approved/runtime-receipts"

KERNEL_TASK_SIZE_TIER="medium" bash "${CONSENSUS_SCRIPT}" record approved vote "workspace receipt consensus" >/dev/null

workspace_key="$(bash "${SCRIPT}" key)"
[[ "${workspace_key}" == "fugue-orchestrator--workspace-run-42" ]]

workspace_dir="$(bash "${SCRIPT}" ensure)"
receipt_path="$(bash "${SCRIPT}" receipt-path)"
[[ -d "${workspace_dir}" ]]
[[ -d "${workspace_dir}/artifacts" ]]
[[ -d "${workspace_dir}/logs" ]]
[[ -d "${workspace_dir}/traces" ]]
[[ -f "${receipt_path}" ]]

status_out="$(bash "${SCRIPT}" status)"
grep -Fq "workspace key: ${workspace_key}" <<<"${status_out}"
grep -Fq "workspace dir: ${workspace_dir}" <<<"${status_out}"
grep -Fq "runtime ledger path: ${TMP_DIR}/runtime-ledger.json" <<<"${status_out}"
grep -Fq "consensus receipt path: ${TMP_DIR}/state/consensus-receipts/workspace-run-42.json" <<<"${status_out}"

consensus_receipt_path="$(jq -r '.consensus_receipt_path' "${receipt_path}")"
[[ "${consensus_receipt_path}" == "${TMP_DIR}/state/consensus-receipts/workspace-run-42.json" ]]

workspace_dir_again="$(bash "${SCRIPT}" ensure)"
[[ "${workspace_dir_again}" == "${workspace_dir}" ]]

echo "kernel runtime workspace check passed"
