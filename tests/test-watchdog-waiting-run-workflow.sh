#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-watchdog.yml"
DRILL="${ROOT_DIR}/scripts/harness/run-watchdog-waiting-run-drill.sh"

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL: ${label}: expected=${expected} actual=${actual}" >&2
    exit 1
  fi
}

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
grep -Fq 'run-watchdog-waiting-run-drill.sh' "${ROOT_DIR}/docs/runbook/fugue-watchdog-waiting-run-drill.md"

alert_json="$(bash "${DRILL}" --waiting-run-count 1 --waiting-run-age-minutes 61 --waiting-run-oldest 'drill-workflow/123')"
if ! jq -e '.active_reasons | index("workflow-waiting") != null' <<<"${alert_json}" >/dev/null; then
  echo "FAIL: waiting run drill must include workflow-waiting active reason" >&2
  echo "${alert_json}" >&2
  exit 1
fi
grep -Fq 'drill-workflow/123' <<<"$(jq -r '.message' <<<"${alert_json}")"

quiet_json="$(bash "${DRILL}" --waiting-run-count 0 --waiting-run-age-minutes 0)"
assert_eq "$(jq -r '.should_alert' <<<"${quiet_json}")" "false" "quiet waiting run should not alert"

echo "watchdog waiting-run workflow check passed"
