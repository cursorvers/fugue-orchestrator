#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-run-state.json"
export KERNEL_RUN_ID="kernel-test"
export KERNEL_OPTIONAL_LANE_RUN_ID="optional-ignored"
export KERNEL_GLM_RUN_ID="glm-ignored"
export KERNEL_GLM_FAILURE_THRESHOLD=2

out="$(bash "${SCRIPT}" status)"
grep -Fq 'run id: kernel-test' <<<"${out}"
grep -Fq 'mode: healthy' <<<"${out}"
grep -Fq 'failures: 0' <<<"${out}"

out="$(bash "${SCRIPT}" fail first-fail)"
grep -Fq 'mode: healthy' <<<"${out}"
grep -Fq 'failures: 1' <<<"${out}"

out="$(bash "${SCRIPT}" fail second-fail)"
grep -Fq 'mode: degraded-allowed' <<<"${out}"
grep -Fq 'failures: 2' <<<"${out}"

out="$(bash "${SCRIPT}" recover restored)"
grep -Fq 'mode: degraded-allowed' <<<"${out}"
grep -Fq 'recovered: true' <<<"${out}"

out="$(bash "${SCRIPT}" reset new-run)"
grep -Fq 'mode: healthy' <<<"${out}"
grep -Fq 'failures: 0' <<<"${out}"

echo "kernel glm run state check passed"
