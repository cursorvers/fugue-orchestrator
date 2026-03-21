#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHASE_GATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-phase-gate.sh"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
GLM_STATE_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"

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
  bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider codex success launch >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider glm success critique >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider gemini-cli success specialist >/dev/null
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
  bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider codex success simulation >/dev/null
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
  bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider codex success launch >/dev/null
  bash "${LEDGER_SCRIPT}" record-provider glm success implementation >/dev/null
  if bash "${PHASE_GATE_SCRIPT}" check implement --uiux >/dev/null 2>&1; then
    echo "expected uiux gate to fail without gemini evidence" >&2
    exit 1
  fi
  bash "${LEDGER_SCRIPT}" record-provider gemini-cli success uiux >/dev/null
  out="$(bash "${PHASE_GATE_SCRIPT}" complete implement --uiux)"
  grep -Fq 'passed: true' <<<"${out}"
  compact_out="$(bash "${COMPACT_SCRIPT}" status phase-impl-uiux)"
  grep -Fq 'last event: phase_completed' <<<"${compact_out}"
  grep -Fq 'phase: implement' <<<"${compact_out}"
}

run_requirements_normal
run_critique_degraded
run_simulation_gate
run_implementation_uiux_gate

echo "kernel phase gate check passed"
