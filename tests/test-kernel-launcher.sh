#!/usr/bin/env bash
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/bin" "${TMP_DIR}/log"

cat > "${HOME}/bin/kernel-root" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${KERNEL_TEST_ROOT}"
EOF
chmod +x "${HOME}/bin/kernel-root"

cat > "${HOME}/bin/k" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'k %s\n' "$*" >> "${KERNEL_TEST_LOG}"
if [[ "${1:-}" == "latest" ]]; then
  printf 'run-primary\n'
fi
EOF
chmod +x "${HOME}/bin/k"

cat > "${HOME}/bin/codex-kernel-guard" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'guard %s\n' "$*" >> "${KERNEL_TEST_LOG}"
EOF
chmod +x "${HOME}/bin/codex-kernel-guard"

export KERNEL_TEST_ROOT="${TMP_DIR}/root"
export KERNEL_TEST_LOG="${TMP_DIR}/log/kernel.log"
mkdir -p "${KERNEL_TEST_ROOT}"

export KERNEL_AUTO_OPEN_LATEST=true
export KERNEL_NODE_ROLE=operator
/Users/masayuki_otawara/bin/kernel >/dev/null
grep -Fq 'guard launch' "${KERNEL_TEST_LOG}"
if grep -Fq 'k latest' "${KERNEL_TEST_LOG}"; then
  echo "operator host must not auto-open the latest run" >&2
  exit 1
fi

: > "${KERNEL_TEST_LOG}"
export KERNEL_NODE_ROLE=primary
/Users/masayuki_otawara/bin/kernel >/dev/null
grep -Fq 'k latest' "${KERNEL_TEST_LOG}"
grep -Fq 'k open run-primary' "${KERNEL_TEST_LOG}"

rm -f "${HOME}/bin/kernel-root"
set +e
out="$(/Users/masayuki_otawara/bin/kernel 2>&1)"
rc=$?
set -e
[[ "${rc}" -ne 0 ]]
grep -Fq 'kernel-root unavailable' <<<"${out}"

echo "kernel launcher check passed"
