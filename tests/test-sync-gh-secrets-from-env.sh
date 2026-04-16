#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/sync-gh-secrets-from-env.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"
cat >"${TMP_DIR}/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  exit 0
fi
exit 0
EOF
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
  fugue-secrets:zai-api-key) printf 'kc-zai' ;;
  fugue-secrets:estat-app-id) printf 'kc-estat' ;;
  fugue-secrets:target-repo-pat) printf 'kc-target-repo-pat' ;;
  fugue-secrets:fugue-ops-pat) printf 'kc-fugue-ops-pat' ;;
  *) exit 44 ;;
esac
EOF
chmod +x "${TMP_DIR}/bin/gh" "${TMP_DIR}/bin/security"

export PATH="${TMP_DIR}/bin:${PATH}"
unset OPENAI_API_KEY ZAI_API_KEY TARGET_REPO_PAT FUGUE_OPS_PAT ANTHROPIC_API_KEY GEMINI_API_KEY XAI_API_KEY ESTAT_API_ID || true

out="$(bash "${SCRIPT}" --dry-run)"
grep -Fq 'DRY-RUN: set org secret OPENAI_API_KEY from OPENAI_API_KEY' <<<"${out}"
grep -Fq 'DRY-RUN: set org secret ZAI_API_KEY from ZAI_API_KEY' <<<"${out}"
grep -Fq 'DRY-RUN: set org secret ESTAT_API_ID from ESTAT_API_ID' <<<"${out}"
grep -Fq 'DRY-RUN: set repo secret TARGET_REPO_PAT from TARGET_REPO_PAT' <<<"${out}"
grep -Fq 'DRY-RUN: set org secret FUGUE_OPS_PAT from FUGUE_OPS_PAT' <<<"${out}"

echo "sync gh secrets from env check passed"
