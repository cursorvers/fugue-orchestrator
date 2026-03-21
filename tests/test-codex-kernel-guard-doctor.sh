#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
SESSION_A="fugue-orchestrator__alpha"
SESSION_B="fugue-orchestrator__beta"
trap 'tmux kill-session -t "${SESSION_A}" >/dev/null 2>&1 || true; tmux kill-session -t "${SESSION_B}" >/dev/null 2>&1 || true; rm -rf "${TMP_DIR}"' EXIT

export KERNEL_ROOT="${ROOT_DIR}"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/optional-ledger.json"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_RUN_ID="doctor-missing-receipt"
export GEMINI_BIN=printf
export CODEX_BIN=printf
export CLAUDE_BIN=printf
export CURSOR_BIN=false
export COPILOT_BIN=false
export ZAI_API_KEY="dummy"
export KERNEL_DOCTOR_SKIP_TMUX_CHECK=true

tmux new-session -d -s "${SESSION_A}" >/dev/null 2>&1 || true
tmux new-session -d -s "${SESSION_B}" >/dev/null 2>&1 || true

mkdir -p "${KERNEL_COMPACT_DIR}"
NEWER_TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
OLDER_TS="$(date -u -v-1M '+%Y-%m-%dT%H:%M:%SZ')"
cat >"${KERNEL_COMPACT_DIR}/run-alpha.json" <<EOF
{"run_id":"run-alpha","project":"fugue-orchestrator","purpose":"alpha","current_phase":"plan","mode":"healthy","runtime":"kernel","tmux_session":"${SESSION_A}","owner":"codex","active_models":["codex","glm","gemini-cli"],"blocking_reason":"","next_action":["implement-a"],"decisions":["d1"],"summary":["s1"],"last_event":"status_changed","updated_at":"${OLDER_TS}"}
EOF
cat >"${KERNEL_COMPACT_DIR}/run-beta.json" <<EOF
{"run_id":"run-beta","project":"fugue-orchestrator","purpose":"beta","current_phase":"implement","mode":"degraded","runtime":"fugue","tmux_session":"${SESSION_B}","owner":"codex","active_models":["codex","cursor-cli"],"blocking_reason":"","next_action":["implement-b"],"decisions":["d1"],"summary":["s1"],"last_event":"status_changed","updated_at":"${NEWER_TS}"}
EOF

out="$(/Users/masayuki_otawara/bin/codex-kernel-guard doctor)"
grep -Fq 'active runs:' <<<"${out}"
first_active_line="$(printf '%s\n' "${out}" | awk '/^  - run_id=/{print; exit}')"
grep -Fq 'run_id=run-beta' <<<"${first_active_line}"
grep -Fq 'purpose=beta' <<<"${first_active_line}"
grep -Fq 'runtime=fugue' <<<"${first_active_line}"
grep -Fq 'bootstrap receipt status:' <<<"${out}"
grep -Fq 'present: false' <<<"${out}"
grep -Fq 'runtime health status:' <<<"${out}"
grep -Fq 'compact artifact status:' <<<"${out}"

echo "codex kernel guard doctor check passed"
