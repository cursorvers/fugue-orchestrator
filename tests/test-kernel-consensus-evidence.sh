#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-consensus-evidence.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_RUN_ID="consensus-run"

out="$(KERNEL_TASK_SIZE_TIER=medium bash "${SCRIPT}" record approved vote "local vote passed")"
grep -Fq 'present: true' <<<"${out}"
grep -Fq 'decision: approved' <<<"${out}"
grep -Fq 'task size tier: medium' <<<"${out}"
grep -Fq 'ok to execute: true' <<<"${out}"

json_path="$(bash "${SCRIPT}" path)"
[[ -f "${json_path}" ]]

integrated_json="${TMP_DIR}/integrated.json"
jq -n '{
  weighted_vote_passed: true,
  ok_to_execute: true,
  issue_task_size_tier: "critical",
  lanes_configured: 5
}' > "${integrated_json}"

out="$(bash "${SCRIPT}" from-local-orchestration "${integrated_json}" local-vote "critical orchestration")"
grep -Fq 'task size tier: critical' <<<"${out}"
grep -Fq 'critical: true' <<<"${out}"
grep -Fq 'lanes configured: 5' <<<"${out}"

echo "kernel consensus evidence check passed"
