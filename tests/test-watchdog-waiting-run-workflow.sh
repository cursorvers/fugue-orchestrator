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

echo "watchdog waiting-run workflow check passed"
