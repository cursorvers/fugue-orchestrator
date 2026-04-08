#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAIM_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-claim.sh"
STATUS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-status-surface.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_SUBSTRATE_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/state/runtime-ledger.json"

bash "${CLAIM_SCRIPT}" claim --project demo --issue-number 1 --run-id run-1 --command-string "printf one" >/dev/null
bash "${CLAIM_SCRIPT}" set-state --identity 'demo#1' --state running --reason "live" >/dev/null
bash "${CLAIM_SCRIPT}" claim --project demo --issue-number 2 --run-id run-2 --command-string "printf two" >/dev/null
bash "${CLAIM_SCRIPT}" set-state --identity 'demo#2' --state retry_queued --reason "retry later" >/dev/null
bash "${CLAIM_SCRIPT}" claim --project demo --issue-number 3 --run-id run-3 --command-string "printf three" --continuity-owner gha-continuity >/dev/null
bash "${CLAIM_SCRIPT}" set-state --identity 'demo#3' --state continuity_degraded --reason "fallback active" --continuity-owner gha-continuity >/dev/null

queue_json='{"items":[{"project":"demo","issue_number":4,"authorized":true,"eligible":false,"reason":"awaiting approval"}]}'
snapshot="$(bash "${STATUS_SCRIPT}" snapshot --queue-json "${queue_json}" --write)"

[[ "$(jq -r '.summary.running' <<<"${snapshot}")" == "1" ]]
[[ "$(jq -r '.summary.retrying' <<<"${snapshot}")" == "1" ]]
[[ "$(jq -r '.summary.degraded' <<<"${snapshot}")" == "1" ]]
[[ "$(jq -r '.summary.blocked' <<<"${snapshot}")" == "1" ]]
[[ "$(jq -r '.recovery_handoff.preferred_recovery' <<<"${snapshot}")" == "local-primary" ]]
[[ -f "$(bash "${STATUS_SCRIPT}" path)" ]]

echo "kernel runtime status surface check passed"
