#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-exec.sh"
STATUS_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-optional-lane-budget.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"
cat >"${TMP_DIR}/bin/gemini" <<'EOF'
#!/usr/bin/env bash
echo "gemini-ok $*"
EOF
cat >"${TMP_DIR}/bin/cursor" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "agent" ]]; then
  shift
fi
echo "cursor-ok $*"
EOF
cat >"${TMP_DIR}/bin/copilot" <<'EOF'
#!/usr/bin/env bash
echo "copilot-ok $*"
EOF
chmod +x "${TMP_DIR}/bin/gemini" "${TMP_DIR}/bin/cursor" "${TMP_DIR}/bin/copilot"

export PATH="${TMP_DIR}/bin:${PATH}"
export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/ledger.json"
export KERNEL_RUN_ID="exec-test"
export KERNEL_GEMINI_DAILY_SOFT_CAP=3
export KERNEL_GEMINI_PER_RUN_SOFT_CAP=2
export KERNEL_CURSOR_MONTHLY_SOFT_CAP=3
export KERNEL_CURSOR_PER_RUN_SOFT_CAP=2
export KERNEL_COPILOT_MONTHLY_SOFT_CAP=3
export KERNEL_COPILOT_PER_RUN_SOFT_CAP=1
export KERNEL_COPILOT_AUTOPILOT_ALLOWED=false
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_CURSOR_READY=false

out="$(bash "${SCRIPT}" gemini-cli -p hello)"
grep -Fq 'gemini-ok -p hello' <<<"${out}"

out="$(bash "${SCRIPT}" cursor-cli --print hello)"
grep -Fq 'cursor-ok --print hello' <<<"${out}"

out="$(bash "${STATUS_SCRIPT}" status)"
grep -Fq 'gemini-cli: day 1/3, run 1/2' <<<"${out}"
grep -Fq 'cursor-cli: month 1/3, run 1/2' <<<"${out}"
grep -Fq 'run id: exec-test' <<<"${out}"

ledger_out="$(bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" status)"
grep -Fq 'gemini-cli: success 1, failure 0' <<<"${ledger_out}"
grep -Fq 'cursor-cli: success 1, failure 0' <<<"${ledger_out}"

out="$(bash "${SCRIPT}" auto -p auto-choice)"
grep -Fq 'copilot-ok -p auto-choice' <<<"${out}"

out="$(bash "${SCRIPT}" copilot-cli autopilot 2>&1 || true)"
grep -Fq 'copilot-cli autopilot/agent mode is disabled' <<<"${out}"

echo "kernel optional lane exec check passed"
