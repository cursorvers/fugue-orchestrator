#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECOVERY_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-run-recovery.sh"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
COMPACT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-compact-artifact.sh"
GUARD_BIN="${KERNEL_GUARD_BIN_UNDER_TEST:-${ROOT_DIR}/scripts/codex-kernel-guard.sh}"
TMP_DIR="$(mktemp -d)"
SESSION_HEALTHY="fugue-orchestrator__runtime-enforcement"
SESSION_STALE="fugue-orchestrator__auto-compact"
SESSION_LEGACY="fugue-orchestrator__legacy-purpose"
trap 'tmux kill-session -t "${SESSION_HEALTHY}" >/dev/null 2>&1 || true; tmux kill-session -t "${SESSION_STALE}" >/dev/null 2>&1 || true; tmux kill-session -t "${SESSION_LEGACY}" >/dev/null 2>&1 || true; rm -rf "${TMP_DIR}"' EXIT

export KERNEL_ROOT="${ROOT_DIR}"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/optional-ledger.json"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_RECOVERY_LAUNCH_CODEX_THREAD=false
export TMUX_TMPDIR="${TMP_DIR}/tmux"
export KERNEL_STALE_HOURS=24
export FUGUE_BIN=printf

mkdir -p "${TMUX_TMPDIR}"

mkdir -p "${KERNEL_COMPACT_DIR}"

cat >"${KERNEL_COMPACT_DIR}/run-stale.json" <<EOF
{"run_id":"run-stale","project":"fugue-orchestrator","purpose":"auto-compact","current_phase":"critique","mode":"degraded","runtime":"fugue","tmux_session":"${SESSION_STALE}","owner":"codex","active_models":["codex","gemini-cli","cursor-cli"],"blocking_reason":"glm unavailable","phase_artifacts":{"critic_report_path":"/tmp/run-stale-critic.md","todo_report_path":"/tmp/run-stale-todo.md"},"next_action":["regenerate compact session"],"decisions":["use degraded shape"],"summary":["resume from compact"],"last_event":"status_changed","updated_at":"2026-03-20T00:05:00Z"}
EOF

cat >"${KERNEL_COMPACT_DIR}/run-plan.json" <<EOF
{"run_id":"run-plan","project":"fugue-orchestrator","purpose":"plan-surface","current_phase":"plan","mode":"healthy","runtime":"kernel","tmux_session":"fugue-orchestrator__plan-surface","owner":"codex","active_models":["codex","glm","gemini-cli"],"next_action":["review-plan"],"updated_at":"2026-03-21T00:00:00Z"}
EOF

cat >"${KERNEL_COMPACT_DIR}/run-implementation.json" <<EOF
{"run_id":"run-implementation","project":"fugue-orchestrator","purpose":"implementation-surface","current_phase":"implementation","mode":"healthy","runtime":"kernel","tmux_session":"fugue-orchestrator__implementation-surface","owner":"codex","active_models":["codex","glm","gemini-cli"],"phase_artifacts":{"implementation_report_path":"/tmp/run-implementation-report.md"},"next_action":["verify-implementation"],"updated_at":"2026-03-21T00:10:00Z"}
EOF

cat >"${KERNEL_COMPACT_DIR}/adhoc_Mac-mini-M1-for-Otawara-M-7_legacy-project_legacy-purpose_20260331T000000_999.json" <<EOF
{"run_id":"adhoc:Mac-mini-M1-for-Otawara-M-7:legacy-project:legacy-purpose:20260331T000000:999","current_phase":"critique","mode":"healthy","runtime":"kernel","tmux_session":"${SESSION_LEGACY}","owner":"codex","active_models":["codex","glm","gemini-cli"],"next_action":["repair-legacy-identity"],"updated_at":"2026-03-21T00:15:00Z"}
EOF

export KERNEL_RUN_ID="run-healthy"
export KERNEL_PROJECT="fugue-orchestrator"
export KERNEL_PURPOSE="runtime-enforcement"
export KERNEL_PHASE="implement"
export KERNEL_OWNER="codex"
export KERNEL_RUNTIME="kernel"
export KERNEL_TMUX_SESSION="${SESSION_HEALTHY}"
export KERNEL_NEXT_ACTIONS="wire-provider-evidence"
export KERNEL_IMPLEMENTATION_REPORT_PATH="/tmp/run-healthy-implement.md"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
bash "${LEDGER_SCRIPT}" record-provider codex success launch >/dev/null
bash "${LEDGER_SCRIPT}" record-provider glm success critique >/dev/null
bash "${LEDGER_SCRIPT}" record-provider gemini-cli success specialist >/dev/null
bash "${LEDGER_SCRIPT}" transition healthy "bootstrap-valid" >/dev/null

tmux new-session -d -s "${SESSION_HEALTHY}" >/dev/null 2>&1 || true
bash "${COMPACT_SCRIPT}" update manual_snapshot "continue runtime enforcement" >/dev/null
healthy_fingerprint="$(jq -r '.session_fingerprint // ""' "${KERNEL_COMPACT_DIR}/run-healthy.json")"
tmux_run_id="$(tmux show-options -t "${SESSION_HEALTHY}" -v @kernel_run_id 2>/dev/null || true)"
tmux_fingerprint="$(tmux show-options -t "${SESSION_HEALTHY}" -v @kernel_session_fingerprint 2>/dev/null || true)"
[[ "${tmux_run_id}" == "run-healthy" ]]
[[ -n "${healthy_fingerprint}" && "${tmux_fingerprint}" == "${healthy_fingerprint}" ]]

out="$(bash "${RECOVERY_SCRIPT}" status run-healthy)"
grep -Fq 'strategy: continue-phase' <<<"${out}"
grep -Fq 'current phase: implement' <<<"${out}"
grep -Fq 'resume phase: implement' <<<"${out}"
grep -Fq "tmux session: ${SESSION_HEALTHY}" <<<"${out}"
grep -Fq 'runtime: kernel' <<<"${out}"
grep -Fq 'codex thread: fugue-orchestrator:runtime-enforcement' <<<"${out}"
grep -Fq 'phase artifacts: implementation_report_path=/tmp/run-healthy-implement.md' <<<"${out}"
grep -Fq 'phase artifact focus: implementation_report_path=/tmp/run-healthy-implement.md' <<<"${out}"

out="$(bash "${RECOVERY_SCRIPT}" status run-stale)"
grep -Fq 'strategy: phase-entry' <<<"${out}"
grep -Fq 'current phase: critique' <<<"${out}"
grep -Fq 'resume phase: critique' <<<"${out}"
grep -Fq 'mode: degraded' <<<"${out}"
grep -Fq 'runtime: fugue' <<<"${out}"
grep -Fq 'codex thread: fugue-orchestrator:auto-compact' <<<"${out}"
grep -Fq 'phase artifacts: critic_report_path=/tmp/run-stale-critic.md | todo_report_path=/tmp/run-stale-todo.md' <<<"${out}"
grep -Fq 'phase artifact focus: critic_report_path=/tmp/run-stale-critic.md' <<<"${out}"

out="$(bash "${RECOVERY_SCRIPT}" status run-plan)"
grep -Fq 'current phase: plan' <<<"${out}"
grep -Fq 'phase artifacts: none' <<<"${out}"
grep -Fq 'phase artifact focus: plan_report_path=none' <<<"${out}"

out="$(bash "${RECOVERY_SCRIPT}" status run-implementation)"
grep -Fq 'current phase: implementation' <<<"${out}"
grep -Fq 'resume phase: implementation' <<<"${out}"
grep -Fq 'phase artifact focus: implementation_report_path=/tmp/run-implementation-report.md' <<<"${out}"

tmux kill-session -t "${SESSION_STALE}" >/dev/null 2>&1 || true
export KERNEL_RECOVERY_LAUNCH_CODEX_THREAD=true
out="$(bash "${RECOVERY_SCRIPT}" recover run-stale)"
grep -Fq 'strategy: phase-entry' <<<"${out}"
grep -Fq "tmux session: ${SESSION_STALE}" <<<"${out}"
grep -Fq 'mode: degraded' <<<"${out}"
grep -Fq 'phase artifact focus: critic_report_path=/tmp/run-stale-critic.md' <<<"${out}"
sleep 0.3
pane_out="$(tmux capture-pane -p -t "=${SESSION_STALE}:main")"
grep -Fq 'Resume FUGUE orchestration for Kernel run run-stale.' <<<"${pane_out}"

windows="$(tmux list-windows -t "=${SESSION_STALE}" -F '#W' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
[[ "${windows}" == "main logs review ops" ]]

updated_at="$(jq -r '.updated_at' "${KERNEL_COMPACT_DIR}/run-stale.json")"
if [[ "${updated_at}" == "2026-03-20T00:05:00Z" ]]; then
  echo "recover should refresh compact updated_at for stale runs" >&2
  exit 1
fi

tmux kill-session -t "${SESSION_STALE}" >/dev/null 2>&1 || true
tmux new-session -d -s "${SESSION_STALE}" -n main >/dev/null 2>&1 || true
out="$(bash "${RECOVERY_SCRIPT}" recover run-stale)"
grep -Fq "tmux session: ${SESSION_STALE}" <<<"${out}"
sleep 0.3
pane_out="$(tmux capture-pane -p -t "=${SESSION_STALE}:main")"
grep -Fq 'Resume FUGUE orchestration for Kernel run run-stale.' <<<"${pane_out}"

tmux new-session -d -s "${SESSION_LEGACY}" -n main >/dev/null 2>&1 || true
out="$(KERNEL_RECOVERY_LAUNCH_CODEX_THREAD=false bash "${RECOVERY_SCRIPT}" recover "adhoc:Mac-mini-M1-for-Otawara-M-7:legacy-project:legacy-purpose:20260331T000000:999")"
grep -Fq "tmux session: ${SESSION_LEGACY}" <<<"${out}"
grep -Fq 'codex thread: legacy-project:legacy-purpose' <<<"${out}"
legacy_path="${KERNEL_COMPACT_DIR}/adhoc_Mac-mini-M1-for-Otawara-M-7_legacy-project_legacy-purpose_20260331T000000_999.json"
legacy_project="$(jq -r '.project' "${legacy_path}")"
legacy_purpose="$(jq -r '.purpose' "${legacy_path}")"
[[ "${legacy_project}" == "legacy-project" ]]
[[ "${legacy_purpose}" == "legacy-purpose" ]]

out="$("${GUARD_BIN}" doctor)"
grep -Fq 'purpose=auto-compact' <<<"${out}"
grep -Fq 'runtime=fugue' <<<"${out}"

tmux set-option -q -t "${SESSION_HEALTHY}" @kernel_run_id run-other >/dev/null 2>&1
if bash "${RECOVERY_SCRIPT}" recover run-healthy >/dev/null 2>&1; then
  echo "recover should fail when an existing tmux session belongs to another run" >&2
  exit 1
fi

echo "kernel run recovery check passed"
