#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_RUN_ID="runtime-ledger-race"

for n in 1 2 3 4 5 6 7 8; do
  bash "${SCRIPT}" transition running "race-${n}" "/tmp/race-${n}.json" >/dev/null &
done
wait

state="$(bash "${SCRIPT}" status)"
grep -Fq 'state: running' <<<"${state}"

bash "${SCRIPT}" record-event cc-pocket "k show" "doctor-run" >/dev/null
state="$(bash "${SCRIPT}" status)"
grep -Fq 'recent events: 1' <<<"${state}"

echo "kernel runtime ledger race check passed"
