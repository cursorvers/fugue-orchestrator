#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${ROOT_DIR}/.fugue"
TMP_DIR="$(mktemp -d "${ROOT_DIR}/.fugue/test-kernel-4pane-surface.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
SURFACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-4pane-surface.sh"
WORKSPACE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-workspace.sh"

export KERNEL_RUN_ID="4pane-surface"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_RUNTIME_WORKSPACE_ROOT="${ROOT_DIR}/.fugue/test-workspaces"
export KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR="${ROOT_DIR}/.fugue/test-workspace-receipts"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="gpt-5.3-codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"

mkdir -p "${KERNEL_COMPACT_DIR}"
cat > "${KERNEL_COMPACT_DIR}/4pane-surface.json" <<'EOF'
{
  "run_id": "4pane-surface",
  "project": "fugue-orchestrator-public",
  "purpose": "4pane-smoke",
  "runtime": "kernel",
  "current_phase": "implement",
  "mode": "normal",
  "next_action": ["verify 4-pane snapshot"],
  "summary": ["surface check"],
  "active_models": ["gpt-5.3-codex", "glm", "gemini-cli"],
  "tmux_session": "fugue-orchestrator-public__4pane-smoke",
  "updated_at": "2026-03-31T00:00:00Z"
}
EOF

bash "${WORKSPACE_SCRIPT}" write >/dev/null
bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
bash "${LEDGER_SCRIPT}" record-provider codex success launch >/dev/null
bash "${LEDGER_SCRIPT}" record-provider glm success critic >/dev/null
bash "${LEDGER_SCRIPT}" record-provider gemini-cli success specialist >/dev/null

snapshot="$(bash "${SURFACE_SCRIPT}" snapshot --write)"
grep -Fq '"run_id": "4pane-surface"' <<<"${snapshot}"
grep -Fq '"shape": "NORMAL"' <<<"${snapshot}"

snapshot_path="$(bash "${SURFACE_SCRIPT}" snapshot-path)"
[[ -f "${snapshot_path}" ]]

lanes="$(bash "${SURFACE_SCRIPT}" render-lanes)"
grep -Fq 'Kernel 4-pane lanes' <<<"${lanes}"
grep -Fq 'provider' <<<"${lanes}"
grep -Fq 'evidence' <<<"${lanes}"
grep -Fq 'codex' <<<"${lanes}"
grep -Fq 'gpt-5.3-codex' <<<"${lanes}"
grep -Fq 'gemini-cli' <<<"${lanes}"
grep -Fq 'projection source: bootstrap receipt + runtime ledger.' <<<"${lanes}"

health="$(bash "${SURFACE_SCRIPT}" render-health)"
grep -Fq 'Kernel 4-pane health' <<<"${health}"
grep -Fq 'status: NORMAL' <<<"${health}"

ship="$(bash "${SURFACE_SCRIPT}" render-ship)"
grep -Fq 'Kernel 4-pane ship' <<<"${ship}"
grep -Fq 'ship enabled: false' <<<"${ship}"

echo "kernel 4-pane surface check passed"
