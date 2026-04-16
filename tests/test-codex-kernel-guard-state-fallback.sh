#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="${KERNEL_GUARD_BIN:-${ROOT_DIR}/scripts/codex-kernel-guard.sh}"
TMP_DIR="$(mktemp -d)"
trap 'chmod 0700 "${HOME}" 2>/dev/null || true; rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"

cat >"${TMP_DIR}/bin/codex" <<'EOF'
#!/usr/bin/env bash
echo "codex-stub $*"
EOF

cat >"${TMP_DIR}/bin/gemini" <<'EOF'
#!/usr/bin/env bash
echo "gemini-stub $*"
EOF

chmod +x "${TMP_DIR}/bin/codex" "${TMP_DIR}/bin/gemini"

export HOME="${TMP_DIR}/locked-home"
mkdir -p "${HOME}"
chmod 0500 "${HOME}"

export PATH="${TMP_DIR}/bin:${PATH}"
export KERNEL_ROOT="${TMP_DIR}/not-a-kernel-root"
export CODEX_BIN="${TMP_DIR}/bin/codex"
export GEMINI_BIN="${TMP_DIR}/bin/gemini"
export CURSOR_BIN="${TMP_DIR}/bin/cursor-missing"
export COPILOT_BIN="${TMP_DIR}/bin/copilot-missing"
export KERNEL_FALLBACK_STATE_ROOT="${TMP_DIR}/kernel-state"
export KERNEL_BOOTSTRAP_PROVIDERS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
export KERNEL_RUN_ID="guard-state-fallback"
export ZAI_API_KEY="glm-present"
export ORCH_DRY_RUN=1
unset KERNEL_STATE_ROOT
unset KERNEL_BOOTSTRAP_RECEIPT_DIR
unset KERNEL_RUNTIME_LEDGER_FILE
unset KERNEL_GLM_RUN_STATE_FILE
unset KERNEL_OPTIONAL_LANE_LEDGER_FILE
unset KERNEL_COMPACT_DIR

out="$("${GUARD}" launch smoke 2>&1)"
grep -Fq "${CODEX_BIN}" <<<"${out}"

receipt_path="${KERNEL_FALLBACK_STATE_ROOT}/bootstrap-receipts/guard-state-fallback.json"
ledger_path="${KERNEL_FALLBACK_STATE_ROOT}/runtime-ledger.json"
[[ -f "${receipt_path}" ]]
[[ -f "${ledger_path}" ]]

echo "codex kernel guard state fallback check passed"
