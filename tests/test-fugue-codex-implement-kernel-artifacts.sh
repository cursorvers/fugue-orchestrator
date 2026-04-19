#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-codex-implement.yml"
CALLER_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-tutti-caller.yml"

grep -q '^      kernel_run_id:$' "${WORKFLOW}" || {
  echo "workflow_call must accept optional kernel_run_id input" >&2
  exit 1
}

grep -q '^      task_size_tier:$' "${WORKFLOW}" || {
  echo "workflow_call must accept task_size_tier for critical confirmation policy" >&2
  exit 1
}

grep -q '^      - name: Update Kernel compact artifact$' "${WORKFLOW}" || {
  echo "workflow must include compact artifact propagation step" >&2
  exit 1
}

grep -q "steps.codex.outputs.exit_code == '0' && inputs.kernel_run_id != ''" "${WORKFLOW}" || {
  echo "compact artifact propagation must be gated on successful codex execution and kernel_run_id" >&2
  exit 1
}

grep -q '^          KERNEL_RUN_ID: ${{ inputs.kernel_run_id }}$' "${WORKFLOW}" || {
  echo "workflow must thread kernel_run_id into codex and propagation steps" >&2
  exit 1
}

grep -q '^          KERNEL_PHASE: implement$' "${WORKFLOW}" || {
  echo "compact artifact propagation must stamp implement phase" >&2
  exit 1
}

grep -q '^          KERNEL_IMPLEMENTATION_REPORT_PATH: ${{ steps.codex.outputs.implementation_report_path }}$' "${WORKFLOW}" || {
  echo "workflow must propagate implementation artifact path to Kernel compact artifact" >&2
  exit 1
}

grep -q 'implementation_report_path="${KERNEL_IMPLEMENTATION_REPORT_PATH:-}"' "${WORKFLOW}" || {
  echo "workflow must resolve required implementation artifact path before propagation" >&2
  exit 1
}

grep -q 'if \[\[ -z "${implementation_report_path}" \]\]; then' "${WORKFLOW}" || {
  echo "workflow must no-op when implementation artifact path is empty" >&2
  exit 1
}

grep -q 'if \[\[ ! -f "${implementation_report_path}" \]\]; then' "${WORKFLOW}" || {
  echo "workflow must no-op when implementation artifact file does not exist" >&2
  exit 1
}

grep -q 'compact_path="$(bash scripts/lib/kernel-compact-artifact.sh path)"' "${WORKFLOW}" || {
  echo "workflow must resolve compact artifact path before propagation" >&2
  exit 1
}

grep -q 'if \[\[ ! -f "${compact_path}" \]\]; then' "${WORKFLOW}" || {
  echo "workflow must skip propagation when the compact artifact does not exist" >&2
  exit 1
}

grep -q 'bash scripts/lib/kernel-compact-artifact.sh update manual_snapshot "implement artifact paths propagated"' "${WORKFLOW}" || {
  echo "workflow must update Kernel compact artifact through a bounded non-completion event" >&2
  exit 1
}

grep -q 'human_confirmation_required="true"' "${WORKFLOW}" || {
  echo "workflow must compute critical/high-risk human confirmation requirement" >&2
  exit 1
}

grep -q 'human_confirmation_required}" == "true" && "${HAS_IMPLEMENT_CONFIRMED}" != "true"' "${WORKFLOW}" || {
  echo "workflow must require implement-confirmed only when human confirmation is mandatory" >&2
  exit 1
}

grep -q '^      kernel_run_id:$' "${CALLER_WORKFLOW}" || {
  echo "tutti caller must accept optional kernel_run_id input" >&2
  exit 1
}

grep -q '^      kernel_run_id: "${{ github.event.inputs.kernel_run_id || '\'''\'' }}"$' "${CALLER_WORKFLOW}" || {
  echo "tutti caller must forward kernel_run_id to fugue-codex-implement" >&2
  exit 1
}

grep -q '^      task_size_tier: "${{ needs.ctx.outputs.task_size_tier }}"$' "${CALLER_WORKFLOW}" || {
  echo "tutti caller must forward task_size_tier to fugue-codex-implement" >&2
  exit 1
}

grep -q "needs.ctx.outputs.implementation_human_confirmation_required != 'true'" "${CALLER_WORKFLOW}" || {
  echo "tutti caller must allow non-critical consensus-approved implementation without implement-confirmed" >&2
  exit 1
}

echo "PASS [fugue-codex-implement-kernel-artifacts]"
