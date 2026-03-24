#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOOP_SCRIPT="${ROOT_DIR}/scripts/local/kernel-runtime-loop.sh"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
export KERNEL_RUN_ID="runtime-loop-run"
export KERNEL_PROJECT="fugue-orchestrator"
export KERNEL_PURPOSE="runtime-loop"
export KERNEL_RUNTIME="kernel"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export FUGUE_APPROVED_WORKSPACE_ROOTS="${ROOT_DIR}/.fugue:${TMP_DIR}/approved"
export KERNEL_RUNTIME_WORKSPACE_ROOT="${TMP_DIR}/approved/runtime-workspaces"
export KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR="${TMP_DIR}/approved/runtime-receipts"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"

bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
bash "${LEDGER_SCRIPT}" record-provider codex success launch >/dev/null
bash "${LEDGER_SCRIPT}" record-provider glm success critique >/dev/null
bash "${LEDGER_SCRIPT}" record-provider gemini-cli success specialist >/dev/null

out="$(KERNEL_RUNTIME_LOOP_ONCE=true bash "${LOOP_SCRIPT}")"
grep -Fq 'state: healthy' <<<"${out}"

ledger_out="$(bash "${LEDGER_SCRIPT}" status)"
grep -Fq 'lifecycle state: live-running' <<<"${ledger_out}"
grep -Fq 'scheduler state: running' <<<"${ledger_out}"
grep -Fq 'scheduler reason: live-running' <<<"${ledger_out}"

workspace_receipt="$(bash "${WORKSPACE_SCRIPT}" receipt-path)"
grep -Fq "workspace receipt path: ${workspace_receipt}" <<<"${ledger_out}"

stop_file="$(bash "${WORKSPACE_SCRIPT}" path)/stop"
touch "${stop_file}"
out="$(KERNEL_RUNTIME_LOOP_ONCE=false KERNEL_RUNTIME_LOOP_INTERVAL_SEC=1 bash "${LOOP_SCRIPT}")"
[[ -z "${out}" ]]

ledger_out="$(bash "${LEDGER_SCRIPT}" status)"
grep -Fq 'lifecycle state: terminal' <<<"${ledger_out}"
grep -Fq 'scheduler state: terminal' <<<"${ledger_out}"
grep -Fq 'scheduler reason: stop-file-detected' <<<"${ledger_out}"

echo "kernel runtime loop check passed"
