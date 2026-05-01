#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-task-router.yml"

grep -Fq 'elif [[ "${GITHUB_EVENT_NAME}" == "issues" ]]; then' "${WORKFLOW}" || {
  echo "FAIL: task router must treat issues.opened as intake-only" >&2
  exit 1
}
grep -Fq 'SKIP_REASON="intake-only-issue-opened"' "${WORKFLOW}" || {
  echo "FAIL: task router missing intake-only skip reason" >&2
  exit 1
}
grep -Fq "(github.event_name == 'issue_comment' || github.event_name == 'workflow_dispatch' || github.event_name == 'workflow_call')" "${WORKFLOW}" || {
  echo "FAIL: task router handoff must require a trusted start-signal event" >&2
  exit 1
}
grep -Fq "steps.ctx.outputs.should_run == 'true' && steps.ctx.outputs.trusted == 'true'" "${WORKFLOW}" || {
  echo "FAIL: task router project annotation must require trusted context" >&2
  exit 1
}
grep -Fq "&& steps.ctx.outputs.trusted == 'true' }}" "${WORKFLOW}" || {
  echo "FAIL: task router handoff must require trust after /vote parsing" >&2
  exit 1
}
grep -Fq 'ROUTER_COMMENT_BODY: ${{ inputs.comment_body' "${WORKFLOW}" || {
  echo "FAIL: task router must pass comment body through step env" >&2
  exit 1
}
grep -Fq 'COMMENT_BODY="${ROUTER_COMMENT_BODY:-}"' "${WORKFLOW}" || {
  echo "FAIL: task router must read comment body from env to avoid shell interpolation" >&2
  exit 1
}
if grep -Fq 'COMMENT_BODY="${{ inputs.comment_body' "${WORKFLOW}"; then
  echo "FAIL: task router must not interpolate comment body directly into run script" >&2
  exit 1
fi

echo "PASS [task-router-start-signal]"
