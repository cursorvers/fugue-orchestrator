#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DRIVER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-run-driver.sh"
CLAIM_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-claim.sh"
LEDGER_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_SUBSTRATE_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/state/runtime-ledger.json"
export FUGUE_APPROVED_WORKSPACE_ROOTS="${ROOT_DIR}/.fugue:${TMP_DIR}"
export KERNEL_RUNTIME_WORKSPACE_ROOT="${TMP_DIR}/workspaces"
export KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR="${TMP_DIR}/runtime-receipts"

topology_file="${TMP_DIR}/topology.json"
cat >"${topology_file}" <<'EOF'
{
  "approved": true,
  "launch": {
    "provider": "codex",
    "command_string": "printf test-run-driver"
  }
}
EOF

out="$(KERNEL_RUN_ID=test-run bash "${RUN_DRIVER_SCRIPT}" run --project demo --issue-number 1 --topology-file "${topology_file}")"
envelope_path="$(jq -r '.envelope_path' <<<"${out}")"
log_path="$(jq -r '.log_path' <<<"${out}")"

[[ -f "${envelope_path}" ]]
[[ -f "${log_path}" ]]
grep -Fq 'test-run-driver' "${log_path}"
[[ "$(jq -r '.envelope.scheduler_state' <<<"${out}")" == "terminal" ]]
[[ "$(jq -r '.envelope.status' <<<"${out}")" == "completed" ]]

claim_json="$(bash "${CLAIM_SCRIPT}" status --identity 'demo#1')"
[[ "$(jq -r '.claim.status' <<<"${claim_json}")" == "terminal" ]]

ledger_out="$(KERNEL_RUN_ID=test-run bash "${LEDGER_SCRIPT}" status)"
grep -Fq 'scheduler state: terminal' <<<"${ledger_out}"
grep -Fq 'successful providers: codex' <<<"${ledger_out}"

if KERNEL_RUN_ID=reject-run bash "${RUN_DRIVER_SCRIPT}" run --project demo --issue-number 2 --topology-file "${topology_file}" --command-string "printf other" >/dev/null 2>&1; then
  echo "expected run driver to reject command-string mismatch" >&2
  exit 1
fi

echo "kernel runtime run driver check passed"
