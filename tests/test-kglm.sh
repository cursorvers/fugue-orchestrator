#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"
cat >"${TMP_DIR}/bin/glm" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "fail" ]]; then
  exit 9
fi
echo "glm-wrapper:$*"
EOF
chmod +x "${TMP_DIR}/bin/glm"

export PATH="${TMP_DIR}/bin:${PATH}"
export KERNEL_ROOT="${ROOT_DIR}"
export KERNEL_GLM_RUN_STATE_FILE="${TMP_DIR}/glm-state.json"
export KERNEL_RUNTIME_LEDGER_FILE="${TMP_DIR}/runtime-ledger.json"
export KERNEL_RUN_ID="kglm-test"

out="$(/Users/masayuki_otawara/bin/kglm ok)"
grep -Fq 'glm-wrapper:ok' <<<"${out}"

state="$(bash "${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh" status)"
grep -Fq 'recovered: true' <<<"${state}"
ledger="$(bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" status)"
grep -Fq 'glm: success 1, failure 0' <<<"${ledger}"

/Users/masayuki_otawara/bin/kglm fail >/dev/null 2>&1 || true
state="$(bash "${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh" status)"
grep -Fq 'failures: 1' <<<"${state}"
ledger="$(bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" status)"
grep -Fq 'glm: success 1, failure 1' <<<"${ledger}"

echo "kernel glm wrapper check passed"
