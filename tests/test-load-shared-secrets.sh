#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/load-shared-secrets.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"
cat >"${TMP_DIR}/bin/security" <<'EOF'
#!/usr/bin/env bash
acct=""
service=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    find-generic-password) shift ;;
    -a) acct="${2:-}"; shift 2 ;;
    -s) service="${2:-}"; shift 2 ;;
    -w) shift ;;
    *) shift ;;
  esac
done

case "${service}:${acct}" in
  fugue-secrets:openai-api-key) printf 'kc-openai' ;;
  fugue-secrets:anthropic-api-key) printf 'kc-anthropic' ;;
  fugue-secrets:xai-api-key) printf 'kc-xai' ;;
  fugue-secrets:target-repo-pat) printf 'kc-target-repo-pat' ;;
  fugue-secrets:fugue-ops-pat) printf 'kc-fugue-ops-pat' ;;
  fugue-secrets:estat-app-id) printf '1234567890123456789012345678901234567890' ;;
  *) exit 44 ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/security"

ENV_FILE="${TMP_DIR}/shared.env"
cat >"${ENV_FILE}" <<'EOF'
ZAI_API_KEY=file-zai
XAI_API=legacy-xai
ESTAT_APP_ID=file-estat-app-id
EOF

export PATH="${TMP_DIR}/bin:${PATH}"
export SHARED_SECRETS_ENV_FILE="${ENV_FILE}"

export OPENAI_API_KEY="env-openai"
out="$(bash "${SCRIPT}" get OPENAI_API_KEY)"
[[ "${out}" == "env-openai" ]]
src="$(bash "${SCRIPT}" source-of OPENAI_API_KEY)"
[[ "${src}" == "process-env" ]]
unset OPENAI_API_KEY

out="$(bash "${SCRIPT}" get OPENAI_API_KEY)"
[[ "${out}" == "kc-openai" ]]
src="$(bash "${SCRIPT}" source-of OPENAI_API_KEY)"
[[ "${src}" == "keychain" ]]

out="$(bash "${SCRIPT}" get ZAI_API_KEY)"
[[ "${out}" == "file-zai" ]]
src="$(bash "${SCRIPT}" source-of ZAI_API_KEY)"
[[ "${src}" == "external-env" ]]

out="$(bash "${SCRIPT}" get XAI_API_KEY)"
[[ "${out}" == "kc-xai" || "${out}" == "legacy-xai" ]]

out="$(bash "${SCRIPT}" get TARGET_REPO_PAT)"
[[ "${out}" == "kc-target-repo-pat" ]]
src="$(bash "${SCRIPT}" source-of TARGET_REPO_PAT)"
[[ "${src}" == "keychain" ]]

out="$(bash "${SCRIPT}" get FUGUE_OPS_PAT)"
[[ "${out}" == "kc-fugue-ops-pat" ]]
src="$(bash "${SCRIPT}" source-of FUGUE_OPS_PAT)"
[[ "${src}" == "keychain" ]]

unset SHARED_SECRETS_ENV_FILE
out="$(bash "${SCRIPT}" get ESTAT_API_ID)"
[[ "${out}" == "1234567890123456789012345678901234567890" ]]
src="$(bash "${SCRIPT}" source-of ESTAT_API_ID)"
[[ "${src}" == "keychain" ]]

export SHARED_SECRETS_ENV_FILE="${ENV_FILE}"
out="$(bash "${SCRIPT}" get ESTAT_APP_ID)"
[[ "${out}" == "1234567890123456789012345678901234567890" || "${out}" == "file-estat-app-id" ]]

echo "shared secret loader check passed"
