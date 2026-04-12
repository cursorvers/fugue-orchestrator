#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-launch.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/bin"
export KERNEL_BIN="${HOME}/bin/kernel"
export FUGUE_BIN="${HOME}/bin/fugue"

kernel_new="$(bash "${SCRIPT}" command new kernel run-k fugue-orchestrator secret-plane fugue-orchestrator__secret-plane focus-text)"
grep -Fq "${HOME}/bin/kernel" <<<"${kernel_new}"
grep -Fq 'KERNEL_RUNTIME=kernel' <<<"${kernel_new}"
grep -Fq 'focus-text' <<<"${kernel_new}"

kernel_resume="$(bash "${SCRIPT}" command resume kernel run-k fugue-orchestrator secret-plane fugue-orchestrator__secret-plane)"
grep -Fq 'kernel-codex-thread.sh' <<<"${kernel_resume}"
grep -Fq 'launch run-k' <<<"${kernel_resume}"

fugue_new="$(bash "${SCRIPT}" command new fugue run-f fugue-orchestrator handoff fugue-orchestrator__handoff review session)"
grep -Fq "${HOME}/bin/fugue" <<<"${fugue_new}"
grep -Fq 'KERNEL_RUNTIME=fugue' <<<"${fugue_new}"
grep -Fq 'FUGUE_RUNTIME=fugue' <<<"${fugue_new}"
grep -Fq 'review' <<<"${fugue_new}"

fugue_resume="$(bash "${SCRIPT}" command resume fugue run-f fugue-orchestrator handoff fugue-orchestrator__handoff)"
grep -Fq "${HOME}/bin/fugue" <<<"${fugue_resume}"
grep -Fq 'Resume\ FUGUE\ orchestration\ for\ Kernel\ run\ run-f.' <<<"${fugue_resume}"

echo "kernel runtime launch check passed"
