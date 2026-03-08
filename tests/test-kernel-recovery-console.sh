#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/kernel-recovery-console.yml"
MOBILE_WORKFLOW="${ROOT_DIR}/.github/workflows/kernel-mobile-progress.yml"
SCRIPT="${ROOT_DIR}/scripts/harness/run-recovery-console.sh"
RUNBOOK="${ROOT_DIR}/docs/kernel-recovery-runbook.md"

grep -q -- '- mobile-progress' "${WORKFLOW}" || {
  echo "FAIL: kernel-recovery-console workflow missing mobile-progress mode" >&2
  exit 1
}
grep -q 'name: kernel-mobile-progress' "${MOBILE_WORKFLOW}" || {
  echo "FAIL: missing kernel-mobile-progress workflow" >&2
  exit 1
}
grep -q 'RECOVERY_MODE: mobile-progress' "${MOBILE_WORKFLOW}" || {
  echo "FAIL: kernel-mobile-progress workflow should dispatch mobile-progress mode" >&2
  exit 1
}
grep -q 'mobile_progress()' "${SCRIPT}" || {
  echo "FAIL: recovery console script missing mobile_progress helper" >&2
  exit 1
}
grep -q 'ensure_status_issue()' "${SCRIPT}" || {
  echo "FAIL: recovery console script missing status-thread helper" >&2
  exit 1
}
grep -q 'gh issue comment "${status_issue}"' "${SCRIPT}" || {
  echo "FAIL: mobile-progress should post into the status issue" >&2
  exit 1
}
REROUTE_BLOCK="$(sed -n '/reroute_issue()/,/^}/p' "${SCRIPT}")"
printf '%s' "${REROUTE_BLOCK}" | grep -q '"fugue-caller.yml"' || {
  echo "FAIL: reroute-issue should dispatch fugue-caller.yml" >&2
  exit 1
}
if printf '%s' "${REROUTE_BLOCK}" | grep -q '"fugue-task-router.yml"'; then
  echo "FAIL: reroute-issue should not dispatch fugue-task-router.yml directly" >&2
  exit 1
fi
grep -q 'gh workflow run fugue-caller.yml' "${ROOT_DIR}/.github/workflows/fugue-watchdog.yml" || {
  echo "FAIL: watchdog should dispatch fugue-caller.yml for pending issues" >&2
  exit 1
}
grep -q '### `mobile-progress`' "${RUNBOOK}" || {
  echo "FAIL: recovery runbook missing mobile-progress section" >&2
  exit 1
}
grep -q 'kernel-mobile-progress' "${RUNBOOK}" || {
  echo "FAIL: recovery runbook should describe automatic mobile progress publishing" >&2
  exit 1
}

echo "PASS [kernel-recovery-console-mobile-progress]"
