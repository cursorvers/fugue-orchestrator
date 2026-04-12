#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-budget.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/ledger.json"
export KERNEL_RUN_ID="nonatomic-test"

out="$(bash "${SCRIPT}" can-use gemini 1 2>&1 || true)"
grep -Fq 'non-atomic budget-can-use is disabled' <<<"${out}"

out="$(bash "${SCRIPT}" record gemini 1 smoke 2>&1 || true)"
grep -Fq 'non-atomic budget-record is disabled' <<<"${out}"

echo "kernel budget nonatomic disabled check passed"
