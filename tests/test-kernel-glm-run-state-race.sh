#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_RUN_ID="glm-race"
export KERNEL_GLM_FAILURE_THRESHOLD=99

for n in 1 2 3 4 5 6; do
  bash "${SCRIPT}" fail "race-${n}" >/dev/null &
done
wait

state="$(bash "${SCRIPT}" status)"
grep -Fq 'failures: 6' <<<"${state}"

echo "kernel glm run state race check passed"
