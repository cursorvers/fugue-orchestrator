#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-watchdog.yml"

grep -Fq 'id: waiting_runs' "${WORKFLOW}"
grep -Fq -- '--status waiting' "${WORKFLOW}"
grep -Fq -- '--limit 200' "${WORKFLOW}"
grep -Fq 'waiting-run-query-failed' "${WORKFLOW}"
grep -Fq 'query_failed="true"' "${WORKFLOW}"
grep -Fq 'max_age_minutes="60"' "${WORKFLOW}"

if grep -Fq "2>/dev/null || printf '[]'" "${WORKFLOW}"; then
  echo "FAIL: waiting run query must not silently collapse failures to an empty list" >&2
  exit 1
fi

grep -Fq 'workflow-waiting' "${ROOT_DIR}/scripts/lib/watchdog-alert-policy.sh"
grep -Fq 'Persist watchdog alert recovery state' "${WORKFLOW}"
grep -Fq "steps.decide.outputs.should_alert != 'true'" "${WORKFLOW}"
grep -Fq "steps.decide.outputs.watchdog_alert_persist == 'true'" "${WORKFLOW}"
grep -Fq "steps.decide.outputs.watchdog_alert_state_update_required == 'true'" "${WORKFLOW}"
grep -Fq 'refusing to overwrite FUGUE_WATCHDOG_ALERT_STATE' "${WORKFLOW}"

echo "watchdog waiting-run workflow check passed"
