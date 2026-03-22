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
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="gpt-5.3-codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
export KERNEL_BOOTSTRAP_PROVIDERS_CSV="codex,glm,gemini-cli"
export ORCH_DRY_RUN=1
export KERNEL_THREE_VOICE_REQUIRED=true
export KERNEL_LOCAL_THREE_VOICE_REQUIRED=true

cat >"${TMP_DIR}/completion-bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'bootstrapped\n' >> "${KERNEL_COMPLETION_AGENT_MARKER}"
EOF
chmod +x "${TMP_DIR}/completion-bootstrap.sh"
export KERNEL_COMPLETION_AGENT_BOOTSTRAP_SCRIPT="${TMP_DIR}/completion-bootstrap.sh"
export KERNEL_COMPLETION_AGENT_MARKER="${TMP_DIR}/completion-bootstrap.log"

export KERNEL_RUN_ID="matrix-normal"
export ZAI_API_KEY="glm-present"
out="$(ORCH_DRY_RUN=0 "${GUARD}" launch smoke 2>&1)"
grep -Fq 'codex-stub -C ' <<<"${out}"
[[ ! -f "${KERNEL_COMPLETION_AGENT_MARKER}" ]]
receipt_path="$(KERNEL_RUN_ID=matrix-normal bash "${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh" path)"
test -f "${receipt_path}"
jq -e '
  .run_id == "matrix-normal" and
  .lane_count >= 6 and
  .has_codex == true and
  .has_glm == true and
  .specialist_count >= 1 and
  .manifest_lane_count >= 6 and
  .has_agent_labels == true and
  .has_subagent_labels == true
' "${receipt_path}" >/dev/null

unset ZAI_API_KEY GLM_API_KEY
export KERNEL_RUN_ID="matrix-invalid"
out="$("${GUARD}" launch smoke 2>&1 || true)"
grep -Fq "glm-credentials-missing" <<<"${out}"
receipt_path="$(KERNEL_RUN_ID=matrix-invalid bash "${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh" path)"
[[ ! -f "${receipt_path}" ]]

cat >"${TMP_DIR}/bin/bash" <<EOF
#!/bin/sh
if [ "\${1:-}" = "${ROOT_DIR}/tests/test-codex-kernel-prompt.sh" ]; then
  exit 1
fi
exec /bin/bash "\$@"
EOF
chmod +x "${TMP_DIR}/bin/bash"
export KERNEL_RUN_ID="matrix-static-fail"
export ZAI_API_KEY="glm-present"
set +e
out="$("${GUARD}" launch smoke 2>&1)"
rc=$?
set -e
[[ "${rc}" -ne 0 ]]
receipt_path="$(KERNEL_RUN_ID=matrix-static-fail bash "${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh" path)"
[[ ! -f "${receipt_path}" ]]
rm -f "${TMP_DIR}/bin/bash"

export KERNEL_RUN_ID="matrix-degraded"
"${GUARD}" glm-fail first >/dev/null
"${GUARD}" glm-fail second >/dev/null
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="gpt-5.3-codex,gemini-cli,cursor-cli"
export KERNEL_BOOTSTRAP_PROVIDERS_CSV="codex,gemini-cli,cursor-cli"
out="$("${GUARD}" launch smoke 2>&1)"
grep -Fq "${CODEX_BIN}" <<<"${out}"

rm -f "${TMP_DIR}/bin/cursor"
export KERNEL_RUN_ID="matrix-degraded-invalid"
"${GUARD}" glm-reset fresh >/dev/null
"${GUARD}" glm-fail first >/dev/null
"${GUARD}" glm-fail second >/dev/null
out="$("${GUARD}" launch smoke 2>&1 || true)"
grep -Fq "specialists-insufficient-for-degraded:1<2" <<<"${out}"
receipt_path="$(KERNEL_RUN_ID=matrix-degraded-invalid bash "${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh" path)"
[[ ! -f "${receipt_path}" ]]

export KERNEL_RUN_ID="matrix-manifest-autoseed"
export ZAI_API_KEY="glm-present"
unset KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT KERNEL_BOOTSTRAP_AGENT_LABELS KERNEL_BOOTSTRAP_SUBAGENT_LABELS KERNEL_BOOTSTRAP_PROVIDERS_CSV
out="$("${GUARD}" launch smoke 2>&1)"
grep -Fq "${CODEX_BIN}" <<<"${out}"
receipt_path="$(KERNEL_RUN_ID=matrix-manifest-autoseed bash "${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh" path)"
test -f "${receipt_path}"
jq -e '
  .run_id == "matrix-manifest-autoseed" and
  .lane_count == 6 and
  .manifest_lane_count == 6 and
  .has_agent_labels == true and
  .has_subagent_labels == true and
  .has_codex == true and
  .has_glm == true and
  .specialist_count >= 1 and
  .active_model_count >= 3
' "${receipt_path}" >/dev/null

export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="gpt-5.3-codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
export KERNEL_BOOTSTRAP_PROVIDERS_CSV="codex,glm,gemini-cli"

mkdir -p "${TMP_DIR}/deny-receipts"
chmod 0500 "${TMP_DIR}/deny-receipts"
export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/deny-receipts"
export KERNEL_RUN_ID="matrix-receipt-perm-denied"
export ZAI_API_KEY="glm-present"
set +e
out="$("${GUARD}" launch smoke 2>&1)"
rc=$?
set -e
[[ "${rc}" -ne 0 ]]
grep -Eiq 'bootstrap receipt|Operation not permitted|Permission denied' <<<"${out}"

echo "codex kernel guard matrix check passed"
