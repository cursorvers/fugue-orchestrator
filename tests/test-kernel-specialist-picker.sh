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

cat >"${FAKE_BIN}/gemini" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"${FAKE_BIN}/copilot" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${FAKE_BIN}/gemini" "${FAKE_BIN}/copilot"

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

echo "kernel specialist picker check passed"
