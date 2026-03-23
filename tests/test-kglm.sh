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

mkdir -p "${TMP_DIR}/api-bin"
CALL_COUNT_FILE="${TMP_DIR}/api-call-count"
cat >"${TMP_DIR}/api-bin/curl" <<'EOF'
#!/usr/bin/env bash
out_file=""
payload=""
while (($#)); do
  case "${1}" in
    -o)
      out_file="${2}"
      shift 2
      ;;
    -d)
      payload="${2}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
count=0
if [[ -n "${CALL_COUNT_FILE:-}" && -f "${CALL_COUNT_FILE}" ]]; then
  count="$(cat "${CALL_COUNT_FILE}")"
fi
count=$((count + 1))
if [[ -n "${CALL_COUNT_FILE:-}" ]]; then
  printf '%s\n' "${count}" >"${CALL_COUNT_FILE}"
fi
if [[ "${payload}" == *'"model":"glm-5.0"'* ]]; then
  printf '%s\n' '{"error":{"code":"1211","message":"Unknown Model, please check the model code."}}' >"${out_file}"
else
  printf '%s\n' '{"choices":[{"message":{"content":"glm-api-ready"}}]}' >"${out_file}"
fi
printf '200'
EOF
chmod +x "${TMP_DIR}/api-bin/curl"

export PATH="${TMP_DIR}/api-bin:/opt/homebrew/bin:/usr/bin:/bin"
export ZAI_API_KEY="test-zai"
export CALL_COUNT_FILE
out="$(/Users/masayuki_otawara/bin/kglm -p "Respond READY and nothing else.")"
grep -Fq 'glm-api-ready' <<<"${out}"
[[ "$(cat "${CALL_COUNT_FILE}")" == "2" ]]
state="$(bash "${ROOT_DIR}/scripts/lib/kernel-glm-run-state.sh" status)"
grep -Fq 'recovered: true' <<<"${state}"
ledger="$(bash "${ROOT_DIR}/scripts/lib/kernel-runtime-ledger.sh" status)"
grep -Fq 'glm: success 2, failure 1' <<<"${ledger}"

echo "kernel glm wrapper check passed"
