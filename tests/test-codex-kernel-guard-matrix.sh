#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="/Users/masayuki_otawara/bin/codex-kernel-guard"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"

cat >"${TMP_DIR}/bin/codex" <<'EOF'
#!/usr/bin/env bash
echo "codex-stub $*"
EOF

cat >"${TMP_DIR}/bin/gemini" <<'EOF'
#!/usr/bin/env bash
echo "gemini-stub $*"
EOF

cat >"${TMP_DIR}/bin/cursor" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "agent" && "${2:-}" == "status" ]]; then
  echo "Logged in as kernel-test@example.com"
  exit 0
fi
echo "cursor-stub $*"
EOF

chmod +x "${TMP_DIR}/bin/codex" "${TMP_DIR}/bin/gemini" "${TMP_DIR}/bin/cursor"

export PATH="${TMP_DIR}/bin:${PATH}"
export KERNEL_ROOT="${ROOT_DIR}"
export CODEX_BIN="${TMP_DIR}/bin/codex"
export GEMINI_BIN="${TMP_DIR}/bin/gemini"
export CURSOR_BIN="${TMP_DIR}/bin/cursor"
export COPILOT_BIN="${TMP_DIR}/bin/copilot-missing"
export KERNEL_OPTIONAL_LANE_LEDGER_FILE="${TMP_DIR}/ledger.json"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm.json"
export ORCH_DRY_RUN=1
export KERNEL_THREE_VOICE_REQUIRED=true
export KERNEL_LOCAL_THREE_VOICE_REQUIRED=true

export KERNEL_RUN_ID="matrix-normal"
export ZAI_API_KEY="glm-present"
out="$("${GUARD}" launch smoke 2>&1)"
grep -Fq "${CODEX_BIN}" <<<"${out}"

unset ZAI_API_KEY
export KERNEL_RUN_ID="matrix-invalid"
out="$("${GUARD}" launch smoke 2>&1 || true)"
grep -Fq "glm-credentials-missing" <<<"${out}"

export KERNEL_RUN_ID="matrix-degraded"
"${GUARD}" glm-fail first >/dev/null
"${GUARD}" glm-fail second >/dev/null
out="$("${GUARD}" launch smoke 2>&1)"
grep -Fq "${CODEX_BIN}" <<<"${out}"

rm -f "${TMP_DIR}/bin/cursor"
export KERNEL_RUN_ID="matrix-degraded-invalid"
"${GUARD}" glm-reset fresh >/dev/null
"${GUARD}" glm-fail first >/dev/null
"${GUARD}" glm-fail second >/dev/null
out="$("${GUARD}" launch smoke 2>&1 || true)"
grep -Fq "specialists-insufficient-for-degraded:1<2" <<<"${out}"

echo "codex kernel guard matrix check passed"
