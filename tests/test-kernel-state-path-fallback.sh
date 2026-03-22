#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
GLM_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
BUDGET_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-budget.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
STATE_PATH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-state-paths.sh"
TMP_DIR="$(mktemp -d)"
trap 'chmod 0700 "${HOME}" 2>/dev/null || true; rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/locked-home"
mkdir -p "${HOME}"
chmod 0500 "${HOME}"

export KERNEL_ROOT="${TMP_DIR}/kernel-root"
mkdir -p "${KERNEL_ROOT}"
export KERNEL_RUN_ID="kernel-state-fallback"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
unset KERNEL_STATE_ROOT
unset KERNEL_BOOTSTRAP_RECEIPT_DIR
unset KERNEL_RUNTIME_LEDGER_FILE
unset KERNEL_GLM_RUN_STATE_FILE
unset KERNEL_OPTIONAL_LANE_LEDGER_FILE
unset KERNEL_COMPACT_DIR

state_root="$(bash "${STATE_PATH_SCRIPT}" state-root)"
[[ "${state_root}" == "${KERNEL_ROOT}/.fugue/kernel-state" ]]

bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
receipt_path="${state_root}/bootstrap-receipts/kernel-state-fallback.json"
ledger_path="${state_root}/runtime-ledger.json"
[[ -f "${receipt_path}" ]]
[[ -f "${ledger_path}" ]]

bash "${GLM_SCRIPT}" fail one >/dev/null
[[ -f "${state_root}/glm-run-state.json" ]]

bash "${BUDGET_SCRIPT}" consume gemini-cli 1 fallback-test >/dev/null
[[ -f "${state_root}/optional-lane-usage.json" ]]

export KERNEL_RUNTIME_LEDGER_AUTO_COMPACT=false
bash "${COMPACT_SCRIPT}" update manual_snapshot "fallback-test" >/dev/null
[[ -f "${state_root}/compact/kernel-state-fallback.json" ]]

echo "kernel state path fallback check passed"
