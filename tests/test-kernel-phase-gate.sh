#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHASE_GATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-phase-gate.sh"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
GLM_STATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
CONSENSUS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-consensus-evidence.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

MILESTONE_RUNNER="${TMP_DIR}/milestone-runner.sh"
MILESTONE_LOG="${TMP_DIR}/milestone.log"
cat > "${MILESTONE_RUNNER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${KERNEL_MILESTONE_RECORD_LOG}"
EOF
chmod +x "${MILESTONE_RUNNER}"

export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_RUNTIME_LEDGER_AUTO_COMPACT=false
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_MILESTONE_RECORD_RUNNER_SCRIPT="${MILESTONE_RUNNER}"
export KERNEL_MILESTONE_RECORD_LOG="${MILESTONE_LOG}"
export KERNEL_AUTO_RECORD_NO_GHA=true
export KERNEL_AUTO_RECORD_DRY_RUN=true
export FUGUE_APPROVED_WORKSPACE_ROOTS="${ROOT_DIR}/.fugue:${TMP_DIR}/approved"
export KERNEL_RUNTIME_WORKSPACE_ROOT="${TMP_DIR}/approved/runtime-workspaces"
export KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR="${TMP_DIR}/approved/runtime-receipts"

run_requirements_normal() {
  export KERNEL_RUN_ID="phase-req"
  export KERNEL_PHASE="requirements"
  export KERNEL_PROJECT="fugue-orchestrator"
  export KERNEL_PURPOSE="runtime-enforcement"
  export KERNEL_TMUX_SESSION="fugue-orchestrator__runtime-enforcement"
  export KERNEL_NEXT_ACTIONS="write-plan"
  export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
  export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
  export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
  export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
  export KERNEL_TASK_SIZE_TIER="medium"
  bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider codex success launch >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider glm success critique >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider gemini-cli success specialist >/dev/null
  if bash "${PHASE_GATE_SCRIPT}" check requirements >/dev/null 2>&1; then
    echo "expected requirements gate to fail without local consensus evidence" >&2
    exit 1
  fi
  bash "${CONSENSUS_SCRIPT}" record approved vote "requirements consensus" >/dev/null
  out="$(bash "${PHASE_GATE_SCRIPT}" check requirements)"
  grep -Fq 'passed: true' <<<"${out}"
}

run_critique_degraded() {
  export KERNEL_RUN_ID="phase-critique-degraded"
  export KERNEL_PHASE="critique"
  export KERNEL_PROJECT="fugue-orchestrator"
  export KERNEL_PURPOSE="auto-compact"
  export KERNEL_TMUX_SESSION="fugue-orchestrator__auto-compact"
  export KERNEL_NEXT_ACTIONS="recover-glm"
  export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,gemini-cli,cursor-cli"
  export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
  export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
  export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
  export KERNEL_TASK_SIZE_TIER="critical"
  bash "${GLM_STATE_SCRIPT}" fail one >/dev/null
  bash "${GLM_STATE_SCRIPT}" fail two >/dev/null
  bash "${RECEIPT_SCRIPT}" write 6 codex,gemini-cli,cursor-cli degraded-allowed >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider codex success launch >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider gemini-cli success specialist >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider cursor-cli success specialist >/dev/null
  out="$(bash "${PHASE_GATE_SCRIPT}" check critique)"
  grep -Fq 'passed: true' <<<"${out}"
}

run_simulation_gate() {
  export KERNEL_RUN_ID="phase-sim"
  export KERNEL_PHASE="simulate"
  export KERNEL_PROJECT="fugue-orchestrator"
  export KERNEL_PURPOSE="simulation"
  export KERNEL_TMUX_SESSION="fugue-orchestrator__simulation"
  export KERNEL_NEXT_ACTIONS="critique-plan"
  export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,gpt-5.3-codex-spark,glm"
  export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
  export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
  export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
  export KERNEL_TASK_SIZE_TIER="medium"
  bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider codex success simulation >/dev/null
  bash "${CONSENSUS_SCRIPT}" record approved vote "simulation consensus" >/dev/null
  out="$(bash "${PHASE_GATE_SCRIPT}" check simulate)"
  grep -Fq 'passed: true' <<<"${out}"
}

run_implementation_uiux_gate() {
  export KERNEL_RUN_ID="phase-impl-uiux"
  export KERNEL_PHASE="implement"
  export KERNEL_PROJECT="fugue-orchestrator"
  export KERNEL_PURPOSE="ui-refresh"
  export KERNEL_TMUX_SESSION="fugue-orchestrator__ui-refresh"
  export KERNEL_NEXT_ACTIONS="apply-gemini-feedback"
  export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
  export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
  export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
  export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
  export KERNEL_TASK_SIZE_TIER="medium"
  export IMPLEMENTATION_REPORT_PATH="${TMP_DIR}/phase-impl-uiux-implementation.md"
  bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider codex success launch >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider glm success implementation >/dev/null
  bash "${CONSENSUS_SCRIPT}" record approved vote "implementation consensus" >/dev/null
  if bash "${PHASE_GATE_SCRIPT}" check implement --uiux >/dev/null 2>&1; then
    echo "expected uiux gate to fail without gemini evidence" >&2
    exit 1
  fi
  bash "${LEDGER_SCRIPT}" record-provider gemini-cli success uiux >/dev/null
  if bash "${PHASE_GATE_SCRIPT}" complete implement --uiux >/dev/null 2>&1; then
    echo "expected implement completion to fail without implementation artifact" >&2
    exit 1
  fi
  printf '## Round 1\n### Implementer Proposal\nx\n### Critic Challenge\ny\n### Integrator Decision\nz\n### Applied Change\na\n### Verification\nb\n' >"${IMPLEMENTATION_REPORT_PATH}"
  if bash "${PHASE_GATE_SCRIPT}" complete implement --uiux >/dev/null 2>&1; then
    echo "expected implement completion to fail without grounding sections" >&2
    exit 1
  fi
  printf '\n### Evidence Quotes\nq\n### Quote-Bounded Analysis\nqa\n### Unsupported Claims Removed\nnone\n' >>"${IMPLEMENTATION_REPORT_PATH}"
  out="$(bash "${PHASE_GATE_SCRIPT}" complete implement --uiux)"
  grep -Fq 'passed: true' <<<"${out}"
  grep -Fq -- '--source kernel-phase-complete' "${MILESTONE_LOG}"
  grep -Fq -- '--summary phase=implement completed' "${MILESTONE_LOG}"
  compact_out="$(bash "${COMPACT_SCRIPT}" status phase-impl-uiux)"
  grep -Fq 'last event: phase_completed' <<<"${compact_out}"
  grep -Fq 'phase: implement' <<<"${compact_out}"
  workspace_receipt_path="$(jq -r '.workspace_receipt_path' "${KERNEL_COMPACT_DIR}/phase-impl-uiux.json")"
  [[ -f "${workspace_receipt_path}" ]]
  implementation_report_path="$(jq -r '.phase_artifacts.implementation_report_path' "${KERNEL_COMPACT_DIR}/phase-impl-uiux.json")"
  [[ "${implementation_report_path}" == "${IMPLEMENTATION_REPORT_PATH}" ]]
}

run_requirements_normal
run_critique_degraded
run_simulation_gate
run_implementation_uiux_gate

echo "kernel phase gate check passed"
