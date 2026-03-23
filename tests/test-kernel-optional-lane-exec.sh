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
if [[ "${1:-}" == "--fail" ]]; then
  echo "gemini-fail" >&2
  exit 7
fi
echo "gemini-ok $*"
EOF
cat >"${TMP_DIR}/bin/cursor" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "agent" && "${2:-}" == "status" ]]; then
  if [[ "${CURSOR_STATUS_MODE:-ready}" == "locked" ]]; then
    echo "Error: Your macOS login keychain is locked." >&2
    exit 1
  fi
  echo "Logged in as exec-test@example.com"
  exit 0
fi
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
export KERNEL_COPILOT_PER_RUN_SOFT_CAP=3
export KERNEL_COPILOT_AUTOPILOT_ALLOWED=false
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_CURSOR_READY=true

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

# Default is blocked — verify autopilot is denied when not explicitly enabled
unset KERNEL_COPILOT_AUTOPILOT_ALLOWED
out="$(bash "${SCRIPT}" copilot-cli autopilot 2>&1 || true)"
grep -Fq 'copilot-cli autopilot/agent mode is disabled' <<<"${out}"

# Explicit enable allows autopilot
export KERNEL_COPILOT_AUTOPILOT_ALLOWED=true
out="$(bash "${SCRIPT}" copilot-cli autopilot)"
grep -Fq 'copilot-ok autopilot' <<<"${out}"

out="$(bash "${SCRIPT}" gemini-cli --fail 2>&1 || true)"
grep -Fq 'gemini-fail' <<<"${out}"
out="$(bash "${STATUS_SCRIPT}" status)"
grep -Fq 'gemini-cli: day 1/3, run 1/2' <<<"${out}"

unset KERNEL_CURSOR_READY
unset SSH_CONNECTION 2>/dev/null || true
unset SSH_TTY 2>/dev/null || true
unset KERNEL_CURSOR_KEYCHAIN_LOCKED_OK 2>/dev/null || true
export CURSOR_STATUS_MODE=locked
out="$(bash "${SCRIPT}" cursor-cli --print hello 2>&1 || true)"
grep -Fq 'optional lane provider not ready: cursor-cli' <<<"${out}"

out="$(bash "${STATUS_SCRIPT}" status)"
grep -Fq 'cursor-cli: month 1/3, run 1/2' <<<"${out}"

echo "kernel optional lane exec check passed"
