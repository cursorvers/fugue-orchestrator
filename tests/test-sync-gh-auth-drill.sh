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
  echo "not logged in" >&2
  exit 1
fi
exit 0
EOF
chmod +x "${TMP_DIR}/bin/gh"

export OPENAI_API_KEY="dry-run-openai"
export ZAI_API_KEY="dry-run-zai"
export ESTAT_API_ID="dry-run-estat"
export TARGET_REPO_PAT="dry-run-target"
export FUGUE_OPS_PAT="dry-run-ops"
export SHARED_SECRETS_SOPS_FILE="${TMP_DIR}/missing.enc"
export SOPS_AGE_KEY_FILE="${TMP_DIR}/missing-keys.txt"

dry_run_out="$(PATH="${TMP_DIR}/bin:/usr/bin:/bin" bash "${SCRIPT}" --dry-run)"
grep -Fq 'mode=dry-run' <<<"${dry_run_out}"
grep -Fq 'DRY-RUN: set org secret OPENAI_API_KEY from OPENAI_API_KEY' <<<"${dry_run_out}"

set +e
apply_out="$(PATH="${TMP_DIR}/bin:/usr/bin:/bin" bash "${SCRIPT}" --apply 2>&1)"
apply_rc=$?
set -e
[[ "${apply_rc}" == "1" ]]
grep -Fq 'Error: gh auth is not ready.' <<<"${apply_out}"

echo "sync gh auth drill passed"
