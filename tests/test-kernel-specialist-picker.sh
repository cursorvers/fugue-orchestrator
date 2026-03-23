#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-specialist-picker.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"
export PATH="${FAKE_BIN}:$PATH"
export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/ledger.json"
export KERNEL_RUN_ID="pick-test"
export KERNEL_STATE_ROOT="${TMP_DIR}/state"
export KERNEL_PROVIDER_READY_TIMEOUT_SEC=1

cat >"${FAKE_BIN}/gemini" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${FAKE_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "${FAKE_BIN}/gemini" "${FAKE_BIN}/gh"

CURSOR_STATUS_COUNT="${TMP_DIR}/cursor-status-count"
cat >"${FAKE_BIN}/cursor" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "agent" && "\${2:-}" == "status" ]]; then
  count=0
  if [[ -f "${CURSOR_STATUS_COUNT}" ]]; then
    count="\$(cat "${CURSOR_STATUS_COUNT}")"
  fi
  count=\$((count + 1))
  printf '%s\n' "\${count}" >"${CURSOR_STATUS_COUNT}"
  echo "Error: Your macOS login keychain is locked."
  exit 1
fi
exit 0
EOF
chmod +x "${FAKE_BIN}/cursor"

export KERNEL_CURSOR_READY=false

cat >"${KERNEL_OPTIONAL_LANE_LEDGER_FILE}" <<'EOF'
{
  "version": 1,
  "events": [
    {"provider":"gemini-cli","units":19,"day":"2026-03-20","run_id":"pick-test"},
    {"provider":"gemini-cli","units":180,"day":"2026-03-20","run_id":"other"},
    {"provider":"copilot-cli","units":1,"month":"2026-03","run_id":"other"}
  ]
}
EOF

out="$(bash "${SCRIPT}" pick)"
[[ "${out}" == "copilot-cli" ]]

status="$(bash "${SCRIPT}" status)"
grep -Fq $'gemini-cli\tready\t' <<<"${status}"
grep -Fq $'cursor-cli\tnot-ready' <<<"${status}"
grep -Fq $'copilot-cli\tready\t' <<<"${status}"

# Keychain locked without SSH → not-ready
unset KERNEL_CURSOR_READY
unset SSH_CONNECTION 2>/dev/null || true
unset SSH_TTY 2>/dev/null || true
unset KERNEL_CURSOR_KEYCHAIN_LOCKED_OK 2>/dev/null || true
out="$(bash "${SCRIPT}" ready cursor-cli 2>&1 || true)"
grep -Fq 'not-ready' <<<"${out}"
out="$(bash "${SCRIPT}" ready cursor-cli 2>&1 || true)"
grep -Fq 'not-ready' <<<"${out}"
[[ "$(cat "${CURSOR_STATUS_COUNT}")" == "1" ]]

# Explicit override is required for keychain-locked cursor readiness
rm -f "${CURSOR_STATUS_COUNT}"
rm -rf "${TMP_DIR}/state/auth-evidence"
export SSH_CONNECTION="127.0.0.1 12345 127.0.0.1 22"
out="$(bash "${SCRIPT}" ready cursor-cli 2>&1 || true)"
grep -Fq 'not-ready' <<<"${out}"
export KERNEL_CURSOR_KEYCHAIN_LOCKED_OK=true
out="$(bash "${SCRIPT}" ready cursor-cli 2>&1)"
grep -Fq 'ready' <<<"${out}"
unset SSH_CONNECTION
unset KERNEL_CURSOR_KEYCHAIN_LOCKED_OK

echo "kernel specialist picker check passed"
