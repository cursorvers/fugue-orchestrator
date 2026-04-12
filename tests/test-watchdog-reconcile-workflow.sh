#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-watchdog.yml"
SCRIPT="${ROOT_DIR}/scripts/lib/watchdog-reconcile-claim-policy.sh"

bash -n "${SCRIPT}"

grep -Fq 'FUGUE_RECONCILE_CLAIM_STATE' "${WORKFLOW}" || {
  echo "FAIL: watchdog workflow missing reconcile claim state variable wiring" >&2
  exit 1
}
grep -Fq 'bash scripts/lib/watchdog-reconcile-claim-policy.sh' "${WORKFLOW}" || {
  echo "FAIL: watchdog workflow missing reconcile claim policy helper" >&2
  exit 1
}
if grep -Fq "if: \${{ steps.find.outputs.pending_count != '0' }}" "${WORKFLOW}"; then
  echo "FAIL: watchdog workflow must reconcile claim state even when pending count is zero" >&2
  exit 1
fi
grep -Fq 'dispatch_issue_numbers_json' "${WORKFLOW}" || {
  echo "FAIL: watchdog workflow missing dispatch plan output" >&2
  exit 1
}
grep -Fq 'failed_issue_numbers_json' "${WORKFLOW}" || {
  echo "FAIL: watchdog workflow missing failed dispatch tracking" >&2
  exit 1
}
grep -Fq 'gh variable set FUGUE_RECONCILE_CLAIM_STATE' "${WORKFLOW}" || {
  echo "FAIL: watchdog workflow missing reconcile claim state persistence" >&2
  exit 1
}

echo "PASS [watchdog-reconcile-workflow]"
