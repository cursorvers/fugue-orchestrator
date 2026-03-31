#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/launchers/kernel"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/log"

cat > "${TMP_DIR}/bin/orchestrator-entrypoint-hint" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${TMP_DIR}/bin/kernel-root" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "${TMP_DIR}/bin/k" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'k %s\n' "$*" >> "${KERNEL_TEST_LOG}"
if [[ "${1:-}" == "latest" ]]; then
  if [[ "${KERNEL_TEST_LATEST_MODE:-present}" == "missing" ]]; then
    exit 1
  fi
  printf '%s\n' "${KERNEL_TEST_LATEST_RUN_ID:-run-primary}"
  exit 0
fi
if [[ "${1:-}" == "open" && "${KERNEL_TEST_OPEN_FAIL:-false}" == "true" ]]; then
  exit 1
fi
printf 'attach %s\n' "${*: -1}"
EOF

cat > "${TMP_DIR}/bin/codex-kernel-guard" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'guard %s\n' "$*" >> "${KERNEL_TEST_LOG}"
EOF

cat > "${TMP_DIR}/bin/codex-prompt-launch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'prompt %s\n' "$*" >> "${KERNEL_TEST_LOG}"
EOF

chmod +x "${TMP_DIR}/bin/"*
cp "${SCRIPT}" "${TMP_DIR}/bin/kernel"
chmod +x "${TMP_DIR}/bin/kernel"

export KERNEL_TEST_LOG="${TMP_DIR}/log/kernel.log"

KERNEL_AUTO_OPEN_LATEST=true \
KERNEL_NODE_ROLE=primary \
KERNEL_TEST_LATEST_MODE=present \
KERNEL_TEST_OPEN_FAIL=false \
TERM=xterm-256color \
"${TMP_DIR}/bin/kernel" >/dev/null
grep -Fq 'k latest' "${KERNEL_TEST_LOG}"
grep -Fq 'k open run-primary' "${KERNEL_TEST_LOG}"

: > "${KERNEL_TEST_LOG}"
KERNEL_AUTO_OPEN_LATEST=true \
KERNEL_NODE_ROLE=primary \
KERNEL_TEST_LATEST_MODE=present \
KERNEL_TEST_OPEN_FAIL=true \
TERM=xterm-256color \
"${TMP_DIR}/bin/kernel" smoke >/dev/null
grep -Fq 'k open run-primary' "${KERNEL_TEST_LOG}"
grep -Fq 'k new smoke' "${KERNEL_TEST_LOG}"
if grep -Fq 'guard launch smoke' "${KERNEL_TEST_LOG}"; then
  echo "non-interactive stale latest fallback should prefer k new before guard launch" >&2
  exit 1
fi

: > "${KERNEL_TEST_LOG}"
TERM=dumb \
KERNEL_AUTO_OPEN_LATEST=false \
KERNEL_NODE_ROLE=operator \
"${TMP_DIR}/bin/kernel" smoke >/dev/null
grep -Fq 'k new smoke' "${KERNEL_TEST_LOG}"
if grep -Fq 'guard launch smoke' "${KERNEL_TEST_LOG}"; then
  echo "non-interactive launcher should prefer k new before guard launch" >&2
  exit 1
fi

: > "${KERNEL_TEST_LOG}"
TERM=dumb \
KERNEL_AUTO_OPEN_LATEST=true \
KERNEL_NODE_ROLE=primary \
KERNEL_TEST_LATEST_MODE=present \
"${TMP_DIR}/bin/kernel" >/dev/null
grep -Fq 'k open run-primary' "${KERNEL_TEST_LOG}"
if grep -Fq 'k new' "${KERNEL_TEST_LOG}"; then
  echo "non-interactive latest open should win before spawning a new session" >&2
  exit 1
fi

echo "kernel launcher template check passed"
