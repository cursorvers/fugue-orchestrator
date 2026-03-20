#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADOPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-session-adopt.sh"
TMP_DIR="$(mktemp -d)"
trap 'tmux kill-session -t "cmux" >/dev/null 2>&1 || true; tmux kill-session -t "fugue-orchestrator__gws" >/dev/null 2>&1 || true; tmux kill-session -t "fugue-orchestrator__fugue-review" >/dev/null 2>&1 || true; rm -rf "${TMP_DIR}"' EXIT

export KERNEL_ROOT="${ROOT_DIR}"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_ADOPT_LAUNCH_CODEX_THREAD=false
export TMUX_TMPDIR="${TMP_DIR}/tmux"
export FUGUE_BIN=printf
mkdir -p "${KERNEL_COMPACT_DIR}" "${TMUX_TMPDIR}"

tmux new-session -d -s cmux -n gws >/dev/null
tmux send-keys -t '=cmux:gws' 'echo gws-work' C-m

out="$(cd "${ROOT_DIR}" && bash "${ADOPT_SCRIPT}" adopt cmux:gws)"
grep -Fq 'kernel session adopted:' <<<"${out}"
grep -Fq 'purpose: gws' <<<"${out}"
grep -Fq 'tmux session: fugue-orchestrator__gws' <<<"${out}"

windows="$(tmux list-windows -t '=fugue-orchestrator__gws' -F '#W' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
[[ "${windows}" == "main logs review ops" ]]

ls "${KERNEL_COMPACT_DIR}"/*.json >/dev/null
grep -Fq '"purpose": "gws"' "${KERNEL_COMPACT_DIR}"/*.json
grep -Fq '"tmux_session": "fugue-orchestrator__gws"' "${KERNEL_COMPACT_DIR}"/*.json

tmux new-session -d -s cmux -n claude >/dev/null
tmux send-keys -t '=cmux:claude' 'echo fugue-work' C-m
export KERNEL_ADOPT_RUNTIME=fugue
export KERNEL_ADOPT_LAUNCH_CODEX_THREAD=true
out="$(cd "${ROOT_DIR}" && bash "${ADOPT_SCRIPT}" adopt cmux:claude fugue-review)"
grep -Fq 'runtime: fugue' <<<"${out}"
grep -Fq 'tmux session: fugue-orchestrator__fugue-review' <<<"${out}"
sleep 0.3
pane_out="$(tmux capture-pane -p -t '=fugue-orchestrator__fugue-review:main')"
pane_compact="$(printf '%s' "${pane_out}" | tr '\n' ' ')"
grep -Fq 'FUGUE_RUNTIME=fugue' <<<"${pane_compact}"
grep -Fq 'printf Resume\ FUGUE' <<<"${pane_compact}"

echo "kernel session adopt check passed"
