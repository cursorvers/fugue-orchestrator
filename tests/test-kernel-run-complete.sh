#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_COMPLETE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-run-complete.sh"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

TOOLS_ROOT="${TMP_DIR}/codex-kernel-guard"
mkdir -p "${TOOLS_ROOT}/src/codex_kernel_guard"
cat > "${TOOLS_ROOT}/src/codex_kernel_guard/__init__.py" <<'EOF'
EOF
cat > "${TOOLS_ROOT}/src/codex_kernel_guard/cli.py" <<'EOF'
from __future__ import annotations
if __name__ == "__main__":
    raise SystemExit(0)
EOF

export TOOLS_ROOT="${TOOLS_ROOT}"
export STATE_ROOT="${TMP_DIR}/state"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_RUN_ID="run-complete-test"
export KERNEL_PROJECT="fugue-orchestrator"
export KERNEL_PURPOSE="doctor-handoff"
export KERNEL_TMUX_SESSION="fugue-orchestrator__doctor-handoff"
export KERNEL_PHASE="verify"
export KERNEL_NEXT_ACTIONS="publish-completion"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
export FUGUE_APPROVED_WORKSPACE_ROOTS="${ROOT_DIR}/.fugue:${TMP_DIR}/approved"
export KERNEL_RUNTIME_WORKSPACE_ROOT="${TMP_DIR}/approved/runtime-workspaces"
export KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR="${TMP_DIR}/approved/runtime-receipts"

bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
bash "${LEDGER_SCRIPT}" record-provider codex success launch >/dev/null
bash "${LEDGER_SCRIPT}" record-provider glm success verify >/dev/null
bash "${LEDGER_SCRIPT}" record-provider gemini-cli success specialist >/dev/null

out="$(bash "${RUN_COMPLETE_SCRIPT}" --summary "Kernel run completed" --no-gha --dry-run)"
grep -Fq 'run id: run-complete-test' <<<"${out}"
grep -Fq 'title: fugue-orchestrator:doctor-handoff' <<<"${out}"

compact_out="$(bash "${COMPACT_SCRIPT}" status)"
grep -Fq 'last event: run_completed' <<<"${compact_out}"
grep -Fq 'summary: Kernel run completed' <<<"${compact_out}"
workspace_receipt_path="$(jq -r '.workspace_receipt_path' "${KERNEL_COMPACT_DIR}/run-complete-test.json")"
[[ -f "${workspace_receipt_path}" ]]

echo "kernel run complete check passed"
