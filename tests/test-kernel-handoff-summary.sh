#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/kernel-handoff-summary.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR="${TMP_DIR}/workspace-receipts"
mkdir -p "${KERNEL_COMPACT_DIR}" "${KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR}"

cat >"${KERNEL_COMPACT_DIR}/run-one.json" <<'EOF'
{
  "run_id": "run-one",
  "project": "fugue-orchestrator",
  "purpose": "runtime-enforcement",
  "current_phase": "implementation",
  "mode": "healthy",
  "runtime": "kernel",
  "tmux_session": "fugue-orchestrator__runtime-enforcement",
  "codex_thread_title": "fugue-orchestrator:runtime-enforcement",
  "active_models": ["codex", "glm", "gemini-cli"],
  "lifecycle_state": "live-running",
  "scheduler_state": "running",
  "scheduler_reason": "live-running",
  "next_action": ["verify-implementation"],
  "decisions": ["keep-kernel-sovereign", "bounded-handoff"],
  "phase_artifacts": {
    "implementation_report_path": "/tmp/run-one-implementation.md"
  },
  "summary": ["Implementation locked", "Verification pending"],
  "updated_at": "2026-03-23T06:10:00Z",
  "workspace_receipt_path": "TMP_WORKSPACE_RECEIPT"
}
EOF

workspace_receipt="${KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR}/run-one.json"
cat >"${workspace_receipt}" <<'EOF'
{
  "run_id": "run-one",
  "workspace_dir": "/tmp/kernel-workspaces/fugue-orchestrator/run-one",
  "artifacts_dir": "/tmp/kernel-workspaces/fugue-orchestrator/run-one/artifacts",
  "logs_dir": "/tmp/kernel-workspaces/fugue-orchestrator/run-one/logs",
  "traces_dir": "/tmp/kernel-workspaces/fugue-orchestrator/run-one/traces",
  "bootstrap_receipt_path": "/tmp/kernel/bootstrap/run-one.json",
  "runtime_ledger_path": "/tmp/kernel/runtime-ledger.json",
  "consensus_receipt_path": "/tmp/kernel/consensus/run-one.json"
}
EOF

perl -0pi -e 's|TMP_WORKSPACE_RECEIPT|'"${workspace_receipt}"'|g' "${KERNEL_COMPACT_DIR}/run-one.json"

sleep 1
cat >"${KERNEL_COMPACT_DIR}/run-two.json" <<'EOF'
{
  "run_id": "run-two",
  "project": "fugue-orchestrator",
  "purpose": "plan-surface",
  "current_phase": "plan",
  "mode": "degraded",
  "runtime": "fugue",
  "tmux_session": "fugue-orchestrator__plan-surface",
  "codex_thread_title": "fugue-orchestrator:plan-surface",
  "active_models": ["codex", "cursor-cli"],
  "lifecycle_state": "retry-queued",
  "scheduler_state": "retry_queued",
  "scheduler_reason": "awaiting-recovery",
  "next_action": ["review-plan"],
  "decisions": [],
  "phase_artifacts": {
    "plan_report_path": "/tmp/run-two-plan.md"
  },
  "summary": ["Plan exists"],
  "updated_at": "2026-03-23T06:11:00Z"
}
EOF

out="$(bash "${SCRIPT}" --run-id run-one)"
grep -Fq 'run id: run-one' <<<"${out}"
grep -Fq 'phase: implementation' <<<"${out}"
grep -Fq 'lifecycle state: live-running' <<<"${out}"
grep -Fq 'phase artifact focus: implementation_report_path=/tmp/run-one-implementation.md' <<<"${out}"
grep -Fq 'workspace receipt path: '"${workspace_receipt}" <<<"${out}"
grep -Fq 'runtime ledger path: /tmp/kernel/runtime-ledger.json' <<<"${out}"
grep -Fq 'recover command: codex-kernel-guard recover-run run-one' <<<"${out}"
grep -Fq 'codex prompt command: bash '"${ROOT_DIR}"'/scripts/lib/kernel-codex-thread.sh prompt run-one' <<<"${out}"

out="$(bash "${SCRIPT}" --compact-path "${KERNEL_COMPACT_DIR}/run-two.json")"
grep -Fq 'run id: run-two' <<<"${out}"
grep -Fq 'runtime: fugue' <<<"${out}"
grep -Fq 'lifecycle state: retry-queued' <<<"${out}"
grep -Fq 'phase artifact focus: plan_report_path=/tmp/run-two-plan.md' <<<"${out}"
grep -Fq 'workspace receipt path: ' <<<"${out}"

out="$(bash "${SCRIPT}")"
grep -Fq 'run id: run-two' <<<"${out}"

echo "kernel handoff summary check passed"
