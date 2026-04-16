#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/load-shared-secrets.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FIXTURE="${TMP_DIR}/shared.env"
cat >"${FIXTURE}" <<'EOF'
OPENAI_API_KEY=shared-openai
ZAI_API_KEY=shared-zai
XAI_API=shared-xai
ESTAT_APP_ID=shared-estat
FUGUE_OPS_PAT=shared-fugue-ops
EOF

make_profile() {
  local profile="$1"
  local mode="$2"
  local root="${TMP_DIR}/${profile}"
  mkdir -p "${root}/bin" "${root}/home/.config/sops/age"
  touch "${root}/bundle.enc" "${root}/home/.config/sops/age/keys.txt"

  cat >"${root}/bin/sops" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" != "decrypt" ]]; then
  echo "unexpected sops mode" >&2
  exit 2
fi
cat "${FIXTURE}"
EOF
  chmod +x "${root}/bin/sops"

  if [[ "${mode}" == "keychain" ]]; then
    cat >"${root}/bin/security" <<'EOF'
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
  fugue-secrets:openai-api-key) printf 'shared-openai' ;;
  fugue-secrets:zai-api-key) printf 'shared-zai' ;;
  fugue-secrets:xai-api-key) printf 'shared-xai' ;;
  fugue-secrets:estat-app-id) printf 'shared-estat' ;;
  fugue-secrets:fugue-ops-pat) printf 'shared-fugue-ops' ;;
  *) exit 44 ;;
esac
EOF
  else
    cat >"${root}/bin/security" <<'EOF'
#!/usr/bin/env bash
exit 44
EOF
  fi
  chmod +x "${root}/bin/security"
}

run_loader() {
  local profile="$1"
  shift
  local root="${TMP_DIR}/${profile}"
  env -i \
    HOME="${root}/home" \
    PATH="${root}/bin:/usr/bin:/bin" \
    SHARED_SECRETS_SOPS_FILE="${root}/bundle.enc" \
    bash "${SCRIPT}" "$@"
}

assert_resolves() {
  local profile="$1"
  local key="$2"
  local expected_source="$3"
  local expected_value="$4"
  local value source
  value="$(run_loader "${profile}" get "${key}")"
  source="$(run_loader "${profile}" source-of "${key}")"
  [[ "${value}" == "${expected_value}" ]]
  [[ "${source}" == "${expected_source}" ]]
}

make_profile "macmini" "sops"
make_profile "mbp" "keychain"

for profile in macmini mbp; do
  expected_source="sops-bundle"
  if [[ "${profile}" == "mbp" ]]; then
    expected_source="keychain"
  fi

  assert_resolves "${profile}" OPENAI_API_KEY "${expected_source}" shared-openai
  assert_resolves "${profile}" ZAI_API_KEY "${expected_source}" shared-zai
  assert_resolves "${profile}" XAI_API_KEY "${expected_source}" shared-xai
  assert_resolves "${profile}" ESTAT_API_ID "${expected_source}" shared-estat
  assert_resolves "${profile}" ESTAT_APP_ID "${expected_source}" shared-estat
  assert_resolves "${profile}" FUGUE_OPS_PAT "${expected_source}" shared-fugue-ops

  doctor="$(run_loader "${profile}" doctor OPENAI_API_KEY ZAI_API_KEY XAI_API_KEY ESTAT_API_ID FUGUE_OPS_PAT)"
  grep -Fq "OPENAI_API_KEY: present (${expected_source}, len=13)" <<<"${doctor}"
  grep -Fq "ESTAT_API_ID: present (${expected_source}, len=12)" <<<"${doctor}"

  if grep -Eq 'shared-(openai|zai|xai|estat|fugue-ops)' <<<"${doctor}"; then
    echo "doctor leaked a secret value for ${profile}" >&2
    exit 1
  fi

  export_out="$(run_loader "${profile}" export ESTAT_APP_ID)"
  grep -Fq 'export ESTAT_API_ID=' <<<"${export_out}"
  if grep -Fq 'ESTAT_APP_ID=' <<<"${export_out}"; then
    echo "export emitted legacy ESTAT alias for ${profile}" >&2
    exit 1
  fi
done

echo "mbp/macmini shared secrets simulation passed"
