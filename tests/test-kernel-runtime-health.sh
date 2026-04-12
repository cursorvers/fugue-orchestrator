#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECEIPT_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-bootstrap-receipt.sh"
HEALTH_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-runtime-health.sh"
GLM_SCRIPT="${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh"
GUARD_BIN="/Users/masayuki_otawara/bin/codex-kernel-guard"
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
chmod +x "${TMP_DIR}/bin/codex" "${TMP_DIR}/bin/gemini"

export KERNEL_BOOTSTRAP_RECEIPT_DIR="${TMP_DIR}/receipts"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
export CODEX_BIN="${TMP_DIR}/bin/codex"
export GEMINI_BIN="${TMP_DIR}/bin/gemini"
export KERNEL_BOOTSTRAP_PROVIDERS_CSV="codex,glm,gemini-cli"
export ZAI_API_KEY="glm-present"
export KERNEL_RUN_ID="health-test"
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"

bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" record-provider codex success launch >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" record-provider glm success critic >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" record-provider gemini-cli success specialist >/dev/null
out="$(bash "${HEALTH_SCRIPT}" status)"
grep -Fq 'state: healthy' <<<"${out}"
grep -Fq 'lifecycle state: bootstrap-valid' <<<"${out}"
grep -Fq 'scheduler state: unknown' <<<"${out}"
grep -Fq 'mutating: true' <<<"${out}"

bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" scheduler-state running "live-running" >/dev/null
out="$(KERNEL_RUNTIME_HEALTH_MUTATE=false bash "${HEALTH_SCRIPT}" status)"
grep -Fq 'lifecycle state: live-running' <<<"${out}"
grep -Fq 'scheduler state: running' <<<"${out}"

bash "${GLM_SCRIPT}" fail one >/dev/null
bash "${GLM_SCRIPT}" fail two >/dev/null
bash "${GLM_SCRIPT}" status >/dev/null
export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,gemini-cli,cursor-cli"
bash "${RECEIPT_SCRIPT}" write 6 codex,gemini-cli,cursor-cli degraded-allowed >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" record-provider cursor-cli success specialist >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" scheduler-state continuity_degraded "live-continuity-degraded" >/dev/null
out="$(bash "${HEALTH_SCRIPT}" status)"
grep -Fq 'state: degraded-allowed' <<<"${out}"
grep -Fq 'lifecycle state: live-continuity-degraded' <<<"${out}"
grep -Fq 'mutating: true' <<<"${out}"

before="$(jq -r --arg run_id "${KERNEL_RUN_ID}" '.runs[$run_id].updated_at // ""' "${KERNEL_RUNTIME_LEDGER_FILE}")"
out="$(KERNEL_RUNTIME_HEALTH_MUTATE=false bash "${HEALTH_SCRIPT}" status)"
grep -Fq 'mutating: false' <<<"${out}"
after="$(jq -r --arg run_id "${KERNEL_RUN_ID}" '.runs[$run_id].updated_at // ""' "${KERNEL_RUNTIME_LEDGER_FILE}")"
[[ "${before}" == "${after}" ]]

rm -f "${KERNEL_BOOTSTRAP_RECEIPT_DIR}/health-test.json"
if bash "${HEALTH_SCRIPT}" status >/dev/null 2>&1; then
  echo "expected invalid health status to return non-zero" >&2
  exit 1
fi

unset KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV
unset KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT
unset KERNEL_BOOTSTRAP_AGENT_LABELS
unset KERNEL_BOOTSTRAP_SUBAGENT_LABELS
bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
if bash "${HEALTH_SCRIPT}" status >/dev/null 2>&1; then
  echo "expected missing manifest evidence to return non-zero" >&2
  exit 1
fi

export KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV="codex,glm,gemini-cli"
export KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT="6"
export KERNEL_BOOTSTRAP_AGENT_LABELS="true"
export KERNEL_BOOTSTRAP_SUBAGENT_LABELS="true"
bash "${RECEIPT_SCRIPT}" write 6 codex,glm,gemini-cli normal >/dev/null
rm -f "${KERNEL_RUNTIME_LEDGER_FILE}"
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" transition running "reset-health" >/dev/null
if KERNEL_RUNTIME_HEALTH_MUTATE=false bash "${HEALTH_SCRIPT}" status >/tmp/kernel-health-check.$$ 2>&1; then
  echo "expected provider-evidence-missing to return non-zero" >&2
  cat /tmp/kernel-health-check.$$ >&2
  rm -f /tmp/kernel-health-check.$$
  exit 1
fi
grep -Fq 'codex-provider-evidence-missing' /tmp/kernel-health-check.$$ || grep -Fq 'glm-provider-evidence-missing' /tmp/kernel-health-check.$$
rm -f /tmp/kernel-health-check.$$

export ORCH_DRY_RUN=1
export KERNEL_RUN_ID="health-guard-launch"
bash "${GLM_SCRIPT}" reset launch-ready >/dev/null
bash "${GUARD_BIN}" launch smoke >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" record-provider glm success guard-test >/dev/null
bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" record-provider gemini-cli success guard-test >/dev/null
out="$(bash "${HEALTH_SCRIPT}" status)"
grep -Fq 'state: healthy' <<<"${out}"
if grep -Fq 'bootstrap-receipt-missing' <<<"${out}"; then
  echo "guard launch should create bootstrap receipt before health check" >&2
  exit 1
fi

echo "kernel runtime health check passed"
