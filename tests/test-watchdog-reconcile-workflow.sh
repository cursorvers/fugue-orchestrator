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
grep -Fq 'gh variable get FUGUE_RECONCILE_CLAIM_STATE' "${WORKFLOW}" || {
  echo "FAIL: watchdog workflow should read reconcile claim state without concatenating gh api 404 JSON" >&2
  exit 1
}
grep -Fq 'next_state_b64=' "${WORKFLOW}" || {
  echo "FAIL: watchdog workflow should pass reconcile claim state through base64 GITHUB_OUTPUT" >&2
  exit 1
}
grep -Fq 'fromjson? // {}' "${WORKFLOW}" || {
  echo "FAIL: watchdog workflow should parse persisted reconcile state defensively" >&2
  exit 1
}
grep -Fq 'fromjson? // []' "${WORKFLOW}" || {
  echo "FAIL: watchdog workflow should parse failed dispatch list defensively" >&2
  exit 1
}

next_state_json='{"claims":{"681":{"issue_number":681,"claimed_at":1776317846,"expires_at":1776319646,"source":"watchdog-reconcile","status":"claimed"},"682":{"issue_number":682,"claimed_at":1776317846,"expires_at":1776319646,"source":"watchdog-reconcile","status":"claimed"}}}'
NEXT_STATE_B64="$(printf '%s' "${next_state_json}" | base64 | tr -d '\n')"
FAILED_ISSUE_NUMBERS_JSON='[682]'
decoded_next_state="$(printf '%s' "${NEXT_STATE_B64:-}" | base64 -d 2>/dev/null || printf '%s' "${NEXT_STATE_B64:-}" | base64 -D 2>/dev/null || printf '{}')"
state_raw="${decoded_next_state:-}"
if [[ -z "${state_raw}" ]]; then
  state_raw='{}'
fi
failed_raw="${FAILED_ISSUE_NUMBERS_JSON:-}"
if [[ -z "${failed_raw}" ]]; then
  failed_raw='[]'
fi
persist_json="$(jq -cn \
  --arg state_raw "${state_raw}" \
  --arg failed_raw "${failed_raw}" '
    ($state_raw | fromjson? // {}) as $state_raw_json
    | ($failed_raw | fromjson? // []) as $failed_raw_json
    | ($state_raw_json | if type == "object" then . else {} end
        | .claims = ((.claims // {}) | if type == "object" then . else {} end)) as $state
    | ($failed_raw_json | if type == "array" then . else [] end) as $failed
    |
    reduce $failed[] as $issue ($state; .claims |= (del(.[($issue|tostring)])))
  ')"
[[ "$(printf '%s' "${persist_json}" | jq -r '.claims["681"].status')" == "claimed" ]] || {
  echo "FAIL: watchdog workflow persist simulation should retain successful claims" >&2
  exit 1
}
[[ "$(printf '%s' "${persist_json}" | jq -r '.claims["682"] // empty')" == "" ]] || {
  echo "FAIL: watchdog workflow persist simulation should drop failed claims" >&2
  exit 1
}

echo "PASS [watchdog-reconcile-workflow]"
