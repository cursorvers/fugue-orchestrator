#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-claim.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_SUBSTRATE_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/state/runtime-ledger.json"

first="$(bash "${SCRIPT}" claim --project demo --issue-number 101 --run-id run-101 --command-string "printf ok" --refresh-token a)"
[[ "$(jq -r '.action' <<<"${first}")" == "claimed" ]]
[[ "$(jq -r '.claim.refresh_count' <<<"${first}")" == "1" ]]

second="$(bash "${SCRIPT}" claim --project demo --issue-number 101 --run-id run-101 --command-string "printf ok" --refresh-token b)"
[[ "$(jq -r '.action' <<<"${second}")" == "coalesced" ]]
[[ "$(jq -r '.claim.refresh_count' <<<"${second}")" == "2" ]]

list_json="$(bash "${SCRIPT}" list --active-only)"
[[ "$(jq 'length' <<<"${list_json}")" == "1" ]]
[[ "$(jq -r '.[0].identity' <<<"${list_json}")" == "demo#101" ]]

bash "${SCRIPT}" release --identity 'demo#101' --reason "finished" >/dev/null
status_json="$(bash "${SCRIPT}" status --identity 'demo#101')"
[[ "$(jq -r '.claim.status' <<<"${status_json}")" == "terminal" ]]
[[ "$(jq -r '.claim.claim_active' <<<"${status_json}")" == "false" ]]

echo "kernel runtime claim check passed"
