#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-budget.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/ledger.json"
export KERNEL_OPTIONAL_LANE_LOCK_DIR="${TMP_DIR}/ledger.lock"
export KERNEL_RUN_ID="race-test"
export KERNEL_GEMINI_DAILY_SOFT_CAP=2
export KERNEL_GEMINI_PER_RUN_SOFT_CAP=1

run_consume() {
  bash "${SCRIPT}" consume gemini 1 race >/tmp/kernel-race-"$1".log 2>&1
}

run_consume 1 &
pid1=$!
run_consume 2 &
pid2=$!

rc1=0
rc2=0
wait "${pid1}" || rc1=$?
wait "${pid2}" || rc2=$?

if ! { [[ "${rc1}" -eq 0 && "${rc2}" -ne 0 ]] || [[ "${rc2}" -eq 0 && "${rc1}" -ne 0 ]]; }; then
  echo "expected exactly one consume to fail under run cap; rc1=${rc1} rc2=${rc2}" >&2
  exit 1
fi

out="$(bash "${SCRIPT}" status)"
grep -Fq 'gemini-cli: day 1/2, run 1/1' <<<"${out}"

echo "kernel optional lane race check passed"
