#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
GUARD_BIN="${KERNEL_GUARD_BIN:-${ROOT_DIR}/scripts/codex-kernel-guard.sh}"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
SESSION_A="fugue-orchestrator__alpha"
SESSION_B="fugue-orchestrator__beta"
trap 'tmux kill-session -t "${SESSION_A}" >/dev/null 2>&1 || true; tmux kill-session -t "${SESSION_B}" >/dev/null 2>&1 || true; rm -rf "${TMP_DIR}"' EXIT

export KERNEL_ROOT="${ROOT_DIR}"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/optional-ledger.json"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_RUNTIME_LEDGER_AUTO_COMPACT=false
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
{"run_id":"run-alpha","project":"fugue-orchestrator","purpose":"alpha","current_phase":"plan","mode":"healthy","runtime":"kernel","tmux_session":"${SESSION_A}","owner":"codex","active_models":["codex","glm","gemini-cli"],"blocking_reason":"","scheduler_state":"retry_queued","scheduler_reason":"doctor-alpha","workspace_receipt_path":"/tmp/run-alpha-workspace.json","phase_artifacts":{"plan_report_path":"/tmp/run-alpha-plan.md","critic_report_path":"/tmp/run-alpha-critic.md"},"next_action":["implement-a"],"decisions":["d1"],"summary":["s1"],"last_event":"status_changed","updated_at":"${OLDER_TS}"}
EOF
cat >"${KERNEL_COMPACT_DIR}/run-beta.json" <<EOF
{"run_id":"run-beta","project":"fugue-orchestrator","purpose":"beta","current_phase":"implement","mode":"degraded","runtime":"fugue","tmux_session":"${SESSION_B}","owner":"codex","active_models":["codex","cursor-cli"],"blocking_reason":"","scheduler_state":"running","scheduler_reason":"doctor-beta","workspace_receipt_path":"/tmp/run-beta-workspace.json","next_action":["implement-b"],"decisions":["d1"],"summary":["s1"],"last_event":"status_changed","updated_at":"${NEWER_TS}"}
EOF

KERNEL_RUN_ID="run-alpha" bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
KERNEL_RUN_ID="run-alpha" bash "${LEDGER_SCRIPT}" scheduler-state retry_queued "doctor-alpha" "/tmp/run-alpha-workspace.json" >/dev/null

out="$("${GUARD_BIN}" doctor)"
grep -Fq 'active runs:' <<<"${out}"
beta_line="$(printf '%s\n' "${out}" | awk '/^  - run_id=run-beta /{print; exit}')"
grep -Fq 'purpose=beta' <<<"${beta_line}"
grep -Fq 'runtime=fugue' <<<"${beta_line}"
grep -Fq 'scheduler_state=running' <<<"${beta_line}"
grep -Fq 'workspace_receipt=false' <<<"${beta_line}"
grep -Fq 'bootstrap receipt status:' <<<"${out}"
grep -Fq 'present: false' <<<"${out}"
grep -Fq 'runtime health status:' <<<"${out}"
grep -Fq 'compact artifact status:' <<<"${out}"

out="$("${GUARD_BIN}" doctor --run run-alpha)"
grep -Fq 'doctor scope run id: run-alpha' <<<"${out}"
grep -Fq 'run detail:' <<<"${out}"
grep -Fq 'scheduler_state_compact: retry_queued' <<<"${out}"
grep -Fq 'workspace_receipt_path_compact: /tmp/run-alpha-workspace.json' <<<"${out}"
grep -Fq 'phase_artifacts: plan_report_path=/tmp/run-alpha-plan.md | critic_report_path=/tmp/run-alpha-critic.md' <<<"${out}"
grep -Fq 'bootstrap receipt:' <<<"${out}"
grep -Fq '  - run id: run-alpha' <<<"${out}"
grep -Fq 'runtime ledger:' <<<"${out}"
grep -Fq 'scheduler state: retry_queued' <<<"${out}"
grep -Fq 'workspace receipt path: /tmp/run-alpha-workspace.json' <<<"${out}"
grep -Fq 'compact artifact:' <<<"${out}"
grep -Fq 'project: fugue-orchestrator' <<<"${out}"

echo "codex kernel guard doctor check passed"
