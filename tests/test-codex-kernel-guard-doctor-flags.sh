#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
GUARD_BIN="${KERNEL_GUARD_BIN:-${ROOT_DIR}/scripts/codex-kernel-guard.sh}"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_ROOT="${ROOT_DIR}"
export KERNEL_SUBSTRATE_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/optional-ledger.json"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_RUNTIME_LEDGER_AUTO_COMPACT=false
export KERNEL_RUN_ID="doctor-flags"
export GEMINI_BIN=printf
export CODEX_BIN=printf
export CLAUDE_BIN=printf
export CURSOR_BIN=false
export COPILOT_BIN=false
export ZAI_API_KEY="dummy"
export OPENAI_API_KEY=""
export GEMINI_API_KEY=""
export XAI_API_KEY=""
export KERNEL_DOCTOR_SKIP_TMUX_CHECK=true
export KERNEL_STALE_HOURS=24

portable_utc_ts() {
  local gnu_expr="$1"
  local bsd_flag="$2"
  if date -u -d "${gnu_expr}" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
    date -u -d "${gnu_expr}" '+%Y-%m-%dT%H:%M:%SZ'
  else
    date -u "${bsd_flag}" '+%Y-%m-%dT%H:%M:%SZ'
  fi
}

mkdir -p "${KERNEL_COMPACT_DIR}"
empty_out="$("${GUARD_BIN}" doctor --all-runs)"
grep -Fq 'all runs:' <<<"${empty_out}"
grep -Fq '  - none' <<<"${empty_out}"
grep -Fq 'kernel run id: none' <<<"${empty_out}"
grep -Fq 'run context status:' <<<"${empty_out}"
grep -Fq '  - resolved: false' <<<"${empty_out}"
grep -Fq '  - reason: no-active-run-context' <<<"${empty_out}"
grep -Fq 'runtime status surface:' <<<"${empty_out}"
if grep -Fq 'unknown-run' <<<"${empty_out}"; then
  echo "doctor should not fabricate unknown-run when no run context exists" >&2
  exit 1
fi
if grep -Fq 'bootstrap receipt status:' <<<"${empty_out}"; then
  echo "doctor should skip per-run bootstrap diagnostics when no run context exists" >&2
  exit 1
fi

NOW_TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
MID_TS="$(portable_utc_ts '1 hour ago' '-v-1H')"
OLD_TS="$(portable_utc_ts '2 days ago' '-v-2d')"
cat >"${KERNEL_COMPACT_DIR}/run-live.json" <<EOF
{"run_id":"run-live","project":"fugue-orchestrator","purpose":"runtime-enforcement","current_phase":"implement","mode":"healthy","runtime":"kernel","tmux_session":"fugue-orchestrator__runtime-enforcement","owner":"codex","active_models":["codex","glm","gemini-cli"],"blocking_reason":"","next_action":["wire-provider-evidence"],"decisions":["d1"],"summary":["live summary"],"last_event":"status_changed","updated_at":"${NOW_TS}"}
EOF
cat >"${KERNEL_COMPACT_DIR}/run-mid.json" <<EOF
{"run_id":"run-mid","project":"fugue-orchestrator","purpose":"doctor-handoff","current_phase":"plan","mode":"degraded","runtime":"fugue","tmux_session":"fugue-orchestrator__doctor-handoff","owner":"codex","active_models":["codex","gemini-cli","cursor-cli"],"blocking_reason":"glm recovery in flight","next_action":["review compact state"],"decisions":["d1"],"summary":["mid summary"],"last_event":"status_changed","updated_at":"${MID_TS}"}
EOF
cat >"${KERNEL_COMPACT_DIR}/run-old.json" <<EOF
{"run_id":"run-old","project":"fugue-orchestrator","purpose":"secret-plane","current_phase":"plan","mode":"blocked","runtime":"kernel","tmux_session":"fugue-orchestrator__secret-plane","owner":"codex","active_models":["codex","cursor-cli"],"blocking_reason":"awaiting secret rotation","next_action":["rotate bundle"],"decisions":["d1"],"summary":["line1","line2"],"last_event":"status_changed","updated_at":"${OLD_TS}"}
EOF

out="$("${GUARD_BIN}" doctor)"
grep -Fq 'active runs:' <<<"${out}"
grep -Fq 'purpose=runtime-enforcement' <<<"${out}"
grep -Fq 'purpose=doctor-handoff' <<<"${out}"
grep -Fq 'runtime=kernel' <<<"${out}"
grep -Fq 'runtime=fugue' <<<"${out}"
first_active_line="$(printf '%s\n' "${out}" | awk '/^active runs:/{getline; print; exit}')"
grep -Fq 'purpose=runtime-enforcement' <<<"${first_active_line}"
if grep -Fq 'purpose=secret-plane' <<<"${out}"; then
  echo "stale run should not appear in default doctor output" >&2
  exit 1
fi
grep -Fq 'runtime status surface:' <<<"${out}"

out="$("${GUARD_BIN}" doctor --all-runs)"
grep -Fq 'all runs:' <<<"${out}"
grep -Fq 'run_id=run-live' <<<"${out}"
grep -Fq 'run_id=run-old' <<<"${out}"
grep -Fq 'age=' <<<"${out}"
grep -Fq 'stale=true' <<<"${out}"
grep -Fq 'runtime=fugue' <<<"${out}"
grep -Fq 'doctor summary:' <<<"${out}"
grep -Fq 'oldest_stale_run: run-old' <<<"${out}"
grep -Fq 'recovery hints:' <<<"${out}"
grep -Fq 'codex-kernel-guard recover-run run-old' <<<"${out}"

out="$("${GUARD_BIN}" doctor --run run-old)"
grep -Fq 'run detail:' <<<"${out}"
grep -Fq 'run_id: run-old' <<<"${out}"
grep -Fq 'runtime: kernel' <<<"${out}"
grep -Fq 'active_models: codex,cursor-cli' <<<"${out}"
grep -Fq 'blocking_reason: awaiting secret rotation' <<<"${out}"
grep -Fq 'codex_thread_title: fugue-orchestrator:secret-plane' <<<"${out}"
grep -Fq 'summary: line1 || line2' <<<"${out}"
grep -Fq 'updated_age: ' <<<"${out}"
grep -Fq 'stale: true' <<<"${out}"

KERNEL_RUN_ID=run-old bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" record-event cc-pocket "kn select" "interactive-selector" >/dev/null
KERNEL_RUN_ID=run-old bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" scheduler-state retry_queued "awaiting-recovery" "/tmp/run-old-workspace.json" >/dev/null
out="$("${GUARD_BIN}" doctor --run run-old)"
grep -Fq 'recent events:' <<<"${out}"
grep -Fq 'scheduler state: retry_queued' <<<"${out}"
grep -Fq 'scheduler reason: awaiting-recovery' <<<"${out}"
grep -Fq 'workspace receipt path: /tmp/run-old-workspace.json' <<<"${out}"
grep -Fq 'actor=cc-pocket' <<<"${out}"
grep -Fq 'command=kn select' <<<"${out}"
grep -Fq 'summary=interactive-selector' <<<"${out}"

FAKE_BIN_DIR="${TMP_DIR}/fake-bin"
mkdir -p "${FAKE_BIN_DIR}"
cat >"${FAKE_BIN_DIR}/bash" <<EOF
#!/bin/sh
if [ "\${1:-}" = "${ROOT_DIR}/tests/test-codex-kernel-prompt.sh" ]; then
  sleep 3
fi
if [ "\${1:-}" = "${ROOT_DIR}/scripts/lib/kernel-runtime-health.sh" ]; then
  sleep 3
fi
exec /bin/bash "\$@"
EOF
chmod +x "${FAKE_BIN_DIR}/bash"

set +e
out="$(PATH="${FAKE_BIN_DIR}:$PATH" DOCTOR_STATIC_CHECK_TIMEOUT_SEC=1 KERNEL_DOCTOR_SUMMARY_TIMEOUT_SEC=1 "${GUARD_BIN}" doctor --run run-old)"
rc=$?
set -e
[[ "${rc}" -ne 0 ]]
grep -Fq 'static contract: fail' <<<"${out}"
grep -Fq 'shared secrets status:' <<<"${out}"
grep -Fq 'ZAI_API_KEY: present (process-env, len=5)' <<<"${out}"
grep -Fq 'OPENAI_API_KEY:' <<<"${out}"
grep -Fq 'runtime health status:' <<<"${out}"
grep -Fq 'runtime status surface:' <<<"${out}"
grep -Fq '  - timeout after 1s' <<<"${out}"
grep -Fq 'recovery hints:' <<<"${out}"
grep -Fq 'run detail:' <<<"${out}"

echo "codex kernel guard doctor flags check passed"
