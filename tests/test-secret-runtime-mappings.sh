#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZSHENV_FILE="${ZSHENV_FILE:-$HOME/.zshenv}"
IMPORT_SCRIPT="${ROOT_DIR}/scripts/sops/import-to-keychain.sh"
LOADER_SCRIPT="${ROOT_DIR}/scripts/lib/load-shared-secrets.sh"

[[ -f "${ZSHENV_FILE}" ]] || {
  echo "missing zshenv: ${ZSHENV_FILE}" >&2
  exit 1
}

zshenv_sops_block="$(sed -n '/^_fugue_sops_key()/,/^}/p' "${ZSHENV_FILE}")"
zshenv_kc_block="$(sed -n '/^_fugue_kc_resolve()/,/^}/p' "${ZSHENV_FILE}")"

grep -Eq "MANUS_MCP_API_KEY\).*printf 'MANUS_API'" <<<"${zshenv_sops_block}"
grep -Eq "HOSTINGER_API_TOKEN\).*printf 'HOSTINGER_API'" <<<"${zshenv_sops_block}"
grep -Eq "XAI_API_KEY\).*printf 'XAI_API'" <<<"${zshenv_sops_block}"

grep -Eq "MANUS_MCP_API_KEY\).*account=manus-api" <<<"${zshenv_kc_block}"
grep -Eq "HOSTINGER_API_TOKEN\).*account=hostinger-api" <<<"${zshenv_kc_block}"
grep -Eq "XAI_API_KEY\).*account=xai-api-key" <<<"${zshenv_kc_block}"

grep -Eq "MANUS_API\).*echo \"manus-api\"" "${IMPORT_SCRIPT}"
grep -Eq "HOSTINGER_API\).*echo \"hostinger-api\"" "${IMPORT_SCRIPT}"
grep -Eq "XAI_API_KEY\).*echo \"xai-api-key\"" "${IMPORT_SCRIPT}"
grep -Eq "XAI_API\).*echo \"xai-api\"" "${IMPORT_SCRIPT}"

grep -Eq "XAI_API\).*printf 'XAI_API_KEY" "${LOADER_SCRIPT}"
grep -Eq "XAI_API_KEY\).*printf 'XAI_API" "${LOADER_SCRIPT}"
grep -Eq "XAI_API_KEY\).*printf 'xai-api-key" "${LOADER_SCRIPT}"

echo "secret runtime mapping check passed"
