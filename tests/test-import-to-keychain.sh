#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/sops/import-to-keychain.sh"
TMP_DIR="$(mktemp -d)"
CURRENT_USER="$(whoami)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/age"
printf 'AGE-SECRET-KEY-TEST\n' > "${TMP_DIR}/age/keys.txt"
ENV_FILE="${TMP_DIR}/fugue-secrets.enc"
printf 'OPENAI_API_KEY=test-openai\n' > "${ENV_FILE}"

cat >"${TMP_DIR}/bin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "decrypt" ]]; then
  echo "unexpected sops mode: ${1:-}" >&2
  exit 1
fi
last_arg=""
for arg in "$@"; do
  last_arg="$arg"
done
cat "${last_arg}"
EOF
chmod +x "${TMP_DIR}/bin/sops"

cat >"${TMP_DIR}/bin/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MOCK_SECURITY_FAIL:-0}" == "1" ]]; then
  exit 9
fi
printf '%s\n' "$*" >> "${MOCK_SECURITY_LOG}"
exit 0
EOF
chmod +x "${TMP_DIR}/bin/security"

export PATH="${TMP_DIR}/bin:${PATH}"
export SOPS_AGE_KEY_FILE="${TMP_DIR}/age/keys.txt"
export MOCK_SECURITY_LOG="${TMP_DIR}/security.log"
FAIL_OUT="${TMP_DIR}/fail.out"
FAIL_ERR="${TMP_DIR}/fail.err"

out="$(bash "${SCRIPT}" "${ENV_FILE}")"
grep -Fq 'imported: OPENAI_API_KEY -> openai-api-key' <<<"${out}"
grep -Fq -- '-a openai-api-key -s fugue-secrets -w test-openai -U' "${MOCK_SECURITY_LOG}"

printf 'FUGUE_QUEUE_API_KEY=queue\nSUPABASE_ACCESS_TOKEN=supabase\nX_API_KEY=xkey\n' > "${ENV_FILE}"
>"${MOCK_SECURITY_LOG}"
out="$(bash "${SCRIPT}" "${ENV_FILE}")"
grep -Fq 'imported: FUGUE_QUEUE_API_KEY (service: FUGUE_QUEUE_API_KEY)' <<<"${out}"
grep -Fq 'imported: SUPABASE_ACCESS_TOKEN (service: Supabase CLI)' <<<"${out}"
grep -Fq 'imported: X_API_KEY (service: x-auto)' <<<"${out}"
grep -Fq -- "-a ${CURRENT_USER} -s FUGUE_QUEUE_API_KEY -w queue -U" "${MOCK_SECURITY_LOG}"
grep -Fq -- '-a supabase -s Supabase CLI -w go-keyring-base64:c3VwYWJhc2U= -U' "${MOCK_SECURITY_LOG}"
grep -Fq -- '-a X_API_KEY -s x-auto -w xkey -U' "${MOCK_SECURITY_LOG}"

printf 'ESTAT_APP_ID=1234567890123456789012345678901234567890\n' > "${ENV_FILE}"
>"${MOCK_SECURITY_LOG}"
out="$(bash "${SCRIPT}" "${ENV_FILE}")"
grep -Fq 'imported: ESTAT_APP_ID -> estat-app-id (alias)' <<<"${out}"
grep -Fq -- '-a estat-app-id -s fugue-secrets -w 1234567890123456789012345678901234567890 -U' "${MOCK_SECURITY_LOG}"

printf 'OPENAI_API_KEY=test-openai\n' > "${ENV_FILE}"
>"${MOCK_SECURITY_LOG}"
export MOCK_SECURITY_FAIL=1
if bash "${SCRIPT}" "${ENV_FILE}" >"${FAIL_OUT}" 2>"${FAIL_ERR}"; then
  echo "import-to-keychain unexpectedly succeeded" >&2
  exit 1
fi
if grep -Fq 'imported:' "${FAIL_OUT}"; then
  echo "failure path reported imported output" >&2
  exit 1
fi
grep -Fq 'ERROR: failed to import OPENAI_API_KEY (canonical)' "${FAIL_ERR}"

echo "import to keychain check passed"
