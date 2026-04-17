#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/load-shared-secrets.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"

cat >"${TMP_DIR}/bin/security" <<'EOF'
#!/usr/bin/env bash
echo "security: SecKeychainSearchCopyNext: User interaction is not allowed." >&2
exit 36
EOF
chmod +x "${TMP_DIR}/bin/security"

cat >"${TMP_DIR}/bin/sops" <<'EOF'
#!/usr/bin/env bash
printf 'OPENAI_API_KEY=sops-openai\nFUGUE_OPS_PAT=sops-fugue-ops\n'
EOF
chmod +x "${TMP_DIR}/bin/sops"

touch "${TMP_DIR}/bundle.enc" "${TMP_DIR}/keys.txt"

run_loader_clean() {
  env -i \
    HOME="${TMP_DIR}/home" \
    PATH="${TMP_DIR}/bin:/usr/bin:/bin" \
    SHARED_SECRETS_SOPS_FILE="${SHARED_SECRETS_SOPS_FILE:-}" \
    SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-}" \
    SHARED_SECRETS_ENV_FILE="${SHARED_SECRETS_ENV_FILE:-}" \
    bash "${SCRIPT}" "$@"
}

mkdir -p "${TMP_DIR}/home"

out="$(
  SHARED_SECRETS_SOPS_FILE="${TMP_DIR}/bundle.enc" \
    SOPS_AGE_KEY_FILE="${TMP_DIR}/keys.txt" \
    run_loader_clean source-of OPENAI_API_KEY
)"
[[ "${out}" == "sops-bundle" ]]

rm -f "${TMP_DIR}/bin/sops"
cat >"${TMP_DIR}/external.env" <<'EOF'
OPENAI_API_KEY=external-openai
EOF
out="$(
  SHARED_SECRETS_SOPS_FILE="${TMP_DIR}/missing.enc" \
    SOPS_AGE_KEY_FILE="${TMP_DIR}/missing-keys.txt" \
    SHARED_SECRETS_ENV_FILE="${TMP_DIR}/external.env" \
    run_loader_clean source-of OPENAI_API_KEY
)"
[[ "${out}" == "external-env" ]]

set +e
missing_out="$(
  SHARED_SECRETS_SOPS_FILE="${TMP_DIR}/missing.enc" \
    SOPS_AGE_KEY_FILE="${TMP_DIR}/missing-keys.txt" \
    SHARED_SECRETS_ENV_FILE="" \
    run_loader_clean get ZAI_API_KEY 2>&1
)"
missing_rc=$?
set -e
[[ "${missing_rc}" != "0" ]]
[[ -z "${missing_out}" ]]

doctor="$(
  SHARED_SECRETS_SOPS_FILE="${TMP_DIR}/missing.enc" \
    SOPS_AGE_KEY_FILE="${TMP_DIR}/missing-keys.txt" \
    SHARED_SECRETS_ENV_FILE="" \
    run_loader_clean doctor ZAI_API_KEY
)"
grep -Fq 'ZAI_API_KEY: missing' <<<"${doctor}"
if grep -Fq 'external-openai' <<<"${doctor}"; then
  echo "doctor must not print secret values" >&2
  exit 1
fi

echo "shared secrets failure smoke passed"
