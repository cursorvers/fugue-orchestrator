#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_SRC="${ROOT_DIR}/scripts/sops/fugue-secret-add.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

REPO_DIR="${TMP_DIR}/repo"
mkdir -p "${REPO_DIR}/scripts/sops" "${REPO_DIR}/secrets" "${TMP_DIR}/bin" "${TMP_DIR}/age"
cp "${SCRIPT_SRC}" "${REPO_DIR}/scripts/sops/fugue-secret-add.sh"
chmod +x "${REPO_DIR}/scripts/sops/fugue-secret-add.sh"
printf 'AGE-SECRET-KEY-TEST\n' > "${TMP_DIR}/age/keys.txt"
cat >"${TMP_DIR}/zshenv" <<'EOF'
_FUGUE_SECRET_KEYS=(
  EXISTING_KEY TEST_KEY MANUS_MCP_API_KEY
)

_fugue_sops_key() {
  case "$1" in
    MANUS_MCP_API_KEY) printf 'MANUS_API' ;;
    HOSTINGER_API_TOKEN) printf 'HOSTINGER_API' ;;
    XAI_API_KEY) printf 'XAI_API' ;;
    *) printf '%s' "$1" ;;
  esac
}
EOF

cat >"${TMP_DIR}/bin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mode="${1:-}"
shift || true
last_arg=""
while [[ $# -gt 0 ]]; do
  last_arg="$1"
  shift
done

case "${mode}" in
  decrypt|encrypt)
    cat "${last_arg}"
    ;;
  *)
    echo "unexpected sops mode: ${mode}" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/sops"

cat >"${REPO_DIR}/secrets/fugue-secrets.enc" <<'EOF'
EXISTING_KEY=old
EXISTING_KEY_EXTRA=keep
EOF

SCRIPT="${REPO_DIR}/scripts/sops/fugue-secret-add.sh"
export SOPS_BIN="${TMP_DIR}/bin/sops"
export SOPS_AGE_KEY_FILE="${TMP_DIR}/age/keys.txt"
export ZSHENV_FILE="${TMP_DIR}/zshenv"
ARGV_OUT="${TMP_DIR}/argv.out"
ARGV_ERR="${TMP_DIR}/argv.err"
STDIN_OUT="${TMP_DIR}/stdin.out"
MAPPED_OUT="${TMP_DIR}/mapped.out"
INVALID_OUT="${TMP_DIR}/invalid.out"
INVALID_ERR="${TMP_DIR}/invalid.err"
MULTI_OUT="${TMP_DIR}/multi.out"
MULTI_ERR="${TMP_DIR}/multi.err"
UPDATE_OUT="${TMP_DIR}/update.out"
GATE_OUT="${TMP_DIR}/gate.out"
GATE_ERR="${TMP_DIR}/gate.err"
REVERSE_OUT="${TMP_DIR}/reverse.out"

if bash "${SCRIPT}" TEST_KEY secret >"${ARGV_OUT}" 2>"${ARGV_ERR}"; then
  echo "argv secret unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'Usage:' "${ARGV_ERR}"

printf 'new-secret' | bash "${SCRIPT}" TEST_KEY >"${STDIN_OUT}"
grep -Fq 'ADDED: TEST_KEY' "${STDIN_OUT}"
grep -Fq 'TEST_KEY=new-secret' "${REPO_DIR}/secrets/fugue-secrets.enc"

printf 'mapped-secret' | bash "${SCRIPT}" MANUS_MCP_API_KEY >"${MAPPED_OUT}"
grep -Fq 'ADDED: MANUS_MCP_API_KEY' "${MAPPED_OUT}"
grep -Fq 'MANUS_API=mapped-secret' "${REPO_DIR}/secrets/fugue-secrets.enc"
if grep -Fq 'MANUS_MCP_API_KEY=' "${REPO_DIR}/secrets/fugue-secrets.enc"; then
  echo "env key was written instead of mapped sops key" >&2
  exit 1
fi

printf 'remapped' | bash "${SCRIPT}" MANUS_API >"${REVERSE_OUT}"
grep -Fq 'UPDATED: MANUS_MCP_API_KEY' "${REVERSE_OUT}"
grep -Fq 'MANUS_API=remapped' "${REPO_DIR}/secrets/fugue-secrets.enc"

if printf 'value' | bash "${SCRIPT}" invalid_key >"${INVALID_OUT}" 2>"${INVALID_ERR}"; then
  echo "invalid key unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'KEY_NAME must match' "${INVALID_ERR}"

if printf 'line1\nline2\n' | bash "${SCRIPT}" MULTILINE_KEY >"${MULTI_OUT}" 2>"${MULTI_ERR}"; then
  echo "multiline secret unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'single-line' "${MULTI_ERR}"

printf 'fresh' | bash "${SCRIPT}" EXISTING_KEY >"${UPDATE_OUT}"
grep -Fq 'UPDATED: EXISTING_KEY' "${UPDATE_OUT}"
[[ "$(grep -c '^EXISTING_KEY=' "${REPO_DIR}/secrets/fugue-secrets.enc")" -eq 1 ]]
grep -Fq 'EXISTING_KEY=fresh' "${REPO_DIR}/secrets/fugue-secrets.enc"
grep -Fq 'EXISTING_KEY_EXTRA=keep' "${REPO_DIR}/secrets/fugue-secrets.enc"

if printf 'missing' | bash "${SCRIPT}" MISSING_KEY >"${GATE_OUT}" 2>"${GATE_ERR}"; then
  echo "unregistered key unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'is not registered in _FUGUE_SECRET_KEYS' "${GATE_ERR}"

echo "fugue secret add check passed"
