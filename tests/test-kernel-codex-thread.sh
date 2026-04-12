#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THREAD_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-codex-thread.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_RUN_ID="thread-test"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_PROJECT="fugue-orchestrator"
export KERNEL_PURPOSE="thread separation"
export KERNEL_PHASE="implement"
export KERNEL_OWNER="codex"
export KERNEL_RUNTIME="fugue"
export KERNEL_TMUX_SESSION="fugue-orchestrator__thread-separation"
export KERNEL_NEXT_ACTIONS="resume-threaded-implementation"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"

bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
bash "${LEDGER_SCRIPT}" transition healthy "bootstrap-valid" >/dev/null
bash "${COMPACT_SCRIPT}" update manual_snapshot "Thread-aware recovery ready" >/dev/null

title="$(bash "${THREAD_SCRIPT}" title)"
[[ "${title}" == "fugue-orchestrator:thread separation" ]]

prompt="$(bash "${THREAD_SCRIPT}" prompt)"
grep -Fq 'Kernel thread: fugue-orchestrator:thread separation' <<<"${prompt}"
grep -Fq 'Continue Kernel run thread-test.' <<<"${prompt}"
grep -Fq 'Runtime: fugue' <<<"${prompt}"
grep -Fq 'Next action: resume-threaded-implementation' <<<"${prompt}"

echo "kernel codex thread check passed"
