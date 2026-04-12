#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-budget.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/ledger.json"
export KERNEL_RUN_ID="test-run"
export KERNEL_OPTIONAL_LANE_RUN_ID="test-run"
export KERNEL_GLM_RUN_ID="glm-ignored"
export KERNEL_ALLOW_NONATOMIC_BUDGET=true
export KERNEL_GEMINI_DAILY_SOFT_CAP=2
export KERNEL_GEMINI_PER_RUN_SOFT_CAP=1
export KERNEL_CURSOR_MONTHLY_SOFT_CAP=2
export KERNEL_CURSOR_PER_RUN_SOFT_CAP=1
export KERNEL_COPILOT_MONTHLY_SOFT_CAP=2
export KERNEL_COPILOT_PER_RUN_SOFT_CAP=1

out="$(bash "${SCRIPT}" status)"
grep -Fq 'run id: test-run' <<<"${out}"
grep -Fq 'gemini-cli: day 0/2, run 0/1' <<<"${out}"

out="$(bash "${SCRIPT}" can-use gemini 1)"
grep -Fq 'allow gemini-cli' <<<"${out}"

bash "${SCRIPT}" record gemini 1 smoke >/dev/null

out="$(bash "${SCRIPT}" can-use gemini 1 || true)"
grep -Fq 'deny gemini-cli: run cap exceeded' <<<"${out}"

out="$(bash "${SCRIPT}" can-use cursor 1)"
grep -Fq 'allow cursor-cli' <<<"${out}"

bash "${SCRIPT}" record cursor 1 smoke >/dev/null

out="$(bash "${SCRIPT}" can-use cursor 1 || true)"
grep -Fq 'deny cursor-cli: run cap exceeded' <<<"${out}"

export KERNEL_RUN_ID="refund-run"
bash "${SCRIPT}" consume gemini 1 smoke >/dev/null
out="$(bash "${SCRIPT}" refund gemini 1 failure)"
grep -Fq 'refunded gemini-cli' <<<"${out}"
out="$(bash "${SCRIPT}" status)"
grep -Fq 'gemini-cli: day 1/2, run 0/1' <<<"${out}"

echo "kernel optional lane budget check passed"
