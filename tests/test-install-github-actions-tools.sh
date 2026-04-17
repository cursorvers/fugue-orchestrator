#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/install-github-actions-tools.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"

out="$(PATH="${TMP_DIR}/bin:/usr/bin:/bin" bash "${SCRIPT}" --check)"
grep -Fq 'actionlint: missing' <<<"${out}"

cat >"${TMP_DIR}/bin/actionlint" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-version" ]]; then
  echo "1.7.7"
else
  exit 0
fi
EOF
chmod +x "${TMP_DIR}/bin/actionlint"
out="$(PATH="${TMP_DIR}/bin:/usr/bin:/bin" bash "${SCRIPT}" --check)"
grep -Fq 'actionlint: ok (1.7.7)' <<<"${out}"

rm -f "${TMP_DIR}/bin/actionlint"
cat >"${TMP_DIR}/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf 'brew %s\n' "$*"
EOF
chmod +x "${TMP_DIR}/bin/brew"
out="$(PATH="${TMP_DIR}/bin:/usr/bin:/bin" bash "${SCRIPT}" --dry-run)"
grep -Fq 'install actionlint via Homebrew' <<<"${out}"
grep -Fq 'DRY-RUN: brew install actionlint' <<<"${out}"

rm -f "${TMP_DIR}/bin/brew"
cat >"${TMP_DIR}/bin/go" <<'EOF'
#!/usr/bin/env bash
printf 'go %s\n' "$*"
EOF
chmod +x "${TMP_DIR}/bin/go"
out="$(PATH="${TMP_DIR}/bin:/usr/bin:/bin" ACTIONLINT_GO_PACKAGE="example.com/actionlint@v1" bash "${SCRIPT}" --dry-run)"
grep -Fq 'install actionlint via go install example.com/actionlint@v1' <<<"${out}"
grep -Fq 'DRY-RUN: go install example.com/actionlint@v1' <<<"${out}"

echo "install github actions tools check passed"
