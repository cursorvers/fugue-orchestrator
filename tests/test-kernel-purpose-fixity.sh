#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_RUN_ID="purpose-fixity"
export KERNEL_PROJECT="fugue-orchestrator"
export KERNEL_PURPOSE="secret-plane"
export KERNEL_PHASE="plan"
export KERNEL_OWNER="codex"
export KERNEL_TMUX_SESSION="fugue-orchestrator__secret-plane"
export KERNEL_NEXT_ACTIONS="continue-plan"

bash "${SCRIPT}" update manual_snapshot "initial" >/dev/null

export KERNEL_PURPOSE="runtime-enforcement"
if bash "${SCRIPT}" update manual_snapshot "should fail" >/dev/null 2>&1; then
  echo "purpose change should fail for existing run" >&2
  exit 1
fi

echo "kernel purpose fixity check passed"
