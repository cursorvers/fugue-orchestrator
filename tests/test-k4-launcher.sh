#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/launchers/k4"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
mkdir -p \
  "${HOME}/bin" \
  "${TMP_DIR}/root/.git" \
  "${TMP_DIR}/root/.codex/prompts" \
  "${TMP_DIR}/root/scripts/lib" \
  "${TMP_DIR}/root/scripts/local" \
  "${TMP_DIR}/log"
touch \
  "${TMP_DIR}/root/.codex/prompts/kernel.md" \
  "${TMP_DIR}/root/scripts/lib/kernel-bootstrap-receipt.sh"

cat > "${HOME}/bin/kernel-root" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${TMP_DIR}/root"
EOF
chmod +x "${HOME}/bin/kernel-root"

cat > "${TMP_DIR}/root/scripts/local/kernel-entrypoint.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${K4_TEST_LOG}"
EOF
chmod +x "${TMP_DIR}/root/scripts/local/kernel-entrypoint.sh"

export K4_TEST_LOG="${TMP_DIR}/log/k4.log"
bash "${SCRIPT}" interactive focus-text
grep -Fq 'interactive focus-text' "${K4_TEST_LOG}"

rm -f "${TMP_DIR}/root/scripts/local/kernel-entrypoint.sh"
set +e
out="$(bash "${SCRIPT}" 2>&1)"
rc=$?
set -e
[[ "${rc}" -ne 0 ]]
grep -Fq 'kernel 4-pane entrypoint not found' <<<"${out}"

echo "k4 launcher check passed"
