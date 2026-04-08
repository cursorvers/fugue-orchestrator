#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEDULER_SCRIPT="${ROOT_DIR}/scripts/kernel-scheduler.sh"
CLAIM_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-claim.sh"
STATUS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-status-surface.sh"
TMP_DIR="$(mktemp -d)"
run_pids=()

cleanup() {
  local pid
  for pid in "${run_pids[@]:-}"; do
    if [[ -n "${pid:-}" && "${pid}" =~ ^[0-9]+$ ]]; then
      kill "${pid}" 2>/dev/null || true
      for _ in {1..20}; do
        if ! kill -0 "${pid}" 2>/dev/null; then
          break
        fi
        sleep 0.1
      done
    fi
  done
  rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

export KERNEL_SUBSTRATE_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/state/runtime-ledger.json"
export FUGUE_APPROVED_WORKSPACE_ROOTS="${ROOT_DIR}/.fugue:${TMP_DIR}"
export KERNEL_RUNTIME_WORKSPACE_ROOT="${TMP_DIR}/workspaces"
export KERNEL_RUNTIME_WORKSPACE_RECEIPT_DIR="${TMP_DIR}/runtime-receipts"
export KERNEL_RUNTIME_SCHEDULER_DIR="${TMP_DIR}/state/scheduler"

queue_file="${TMP_DIR}/queue.json"
cat >"${queue_file}" <<'EOF'
{
  "items": [
    {
      "project": "demo",
      "issue_number": 11,
      "authorized": true,
      "command_string": "sleep 2",
      "provider": "codex"
    },
    {
      "project": "demo",
      "issue_number": 12,
      "authorized": true,
      "command_string": "printf second",
      "provider": "codex"
    },
    {
      "project": "plain",
      "issue_number": 13,
      "command_string": "printf blocked",
      "provider": "codex"
    },
    {
      "project": "unauthorized",
      "issue_number": 15,
      "authorized": false,
      "dispatchable": true,
      "command_string": "printf should-not-run",
      "provider": "codex"
    },
    {
      "project": "alt",
      "issue_number": 14,
      "start_signal": "/vote",
      "command_string": "sleep 2",
      "provider": "codex"
    }
  ]
}
EOF

out="$(bash "${SCHEDULER_SCRIPT}" once --queue-file "${queue_file}")"
[[ "$(jq '.launched | length' <<<"${out}")" == "2" ]]
[[ "$(jq '.deferred | length' <<<"${out}")" == "1" ]]

claim_one="$(bash "${CLAIM_SCRIPT}" status --identity 'demo#11')"
claim_two="$(bash "${CLAIM_SCRIPT}" status --identity 'demo#12')"
claim_three="$(bash "${CLAIM_SCRIPT}" status --identity 'alt#14')"
claim_plain="$(bash "${CLAIM_SCRIPT}" status --identity 'plain#13' || true)"
claim_unauthorized="$(bash "${CLAIM_SCRIPT}" status --identity 'unauthorized#15' || true)"
[[ "$(jq -r '.claim.status' <<<"${claim_one}")" == "running" ]]
[[ "$(jq -r '.claim.status' <<<"${claim_two}")" == "retry_queued" ]]
[[ "$(jq -r '.claim.status' <<<"${claim_three}")" == "running" ]]
[[ "$(jq -r '.present // false' <<<"${claim_plain}")" == "false" ]]
[[ "$(jq -r '.present // false' <<<"${claim_unauthorized}")" == "false" ]]
test -f "$(jq -r '.claim.topology_path' <<<"${claim_one}")"
test -f "$(jq -r '.claim.topology_path' <<<"${claim_three}")"

run_pids+=("$(jq -r '.claim.run_driver_pid // ""' <<<"${claim_one}")")
run_pids+=("$(jq -r '.claim.run_driver_pid // ""' <<<"${claim_three}")")
for pid in "${run_pids[@]}"; do
  if [[ -n "${pid}" && "${pid}" =~ ^[0-9]+$ ]]; then
    kill "${pid}" 2>/dev/null || true
  fi
done

snapshot_path="$(bash "${STATUS_SCRIPT}" path)"
[[ -f "${snapshot_path}" ]]
grep -Fq '"retrying"' "${snapshot_path}"
[[ "$(jq -r '.summary.blocked' "${snapshot_path}")" == "2" ]]
[[ "$(jq -r '.blocked | map(.identity) | sort | join(",")' "${snapshot_path}")" == "plain#13,unauthorized#15" ]]

echo "kernel scheduler check passed"
