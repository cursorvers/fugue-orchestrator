#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNIPPET="${ROOT_DIR}/scripts/local/launchers/codex-orchestrator.zsh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/home/bin" "${TMP_DIR}/log"

cat > "${TMP_DIR}/home/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'raw-codex %s\n' "$*" >> "${KERNEL_TEST_LOG}"
EOF

cat > "${TMP_DIR}/home/bin/kernel" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'kernel %s\n' "$*" >> "${KERNEL_TEST_LOG}"
EOF

cat > "${TMP_DIR}/home/bin/kernel-root" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${KERNEL_TEST_KERNEL_ROOT:-present}" == "missing" ]]; then
  exit 1
fi
printf '%s\n' "${KERNEL_TEST_ROOT_PATH:-/tmp/fugue-orchestrator}"
EOF

chmod +x "${TMP_DIR}/home/bin/"*
export KERNEL_TEST_LOG="${TMP_DIR}/log/orchestrator.log"
TEST_SHELL="${TEST_SHELL:-$(command -v zsh || command -v bash)}"
[[ -n "${TEST_SHELL}" ]] || {
  echo "missing zsh/bash for codex orchestrator snippet test" >&2
  exit 1
}

"${TEST_SHELL}" -lc '
  export HOME="'"${TMP_DIR}/home"'"
  export PATH="${HOME}/bin:/opt/homebrew/bin:/usr/bin:/bin"
  export KERNEL_TEST_LOG="'"${TMP_DIR}/log/orchestrator.log"'"
  export KERNEL_TEST_KERNEL_ROOT=present
  source "'"${SNIPPET}"'"
  codex smoke-route
' >/dev/null
grep -Fq 'kernel smoke-route' "${KERNEL_TEST_LOG}"
if grep -Fq 'raw-codex smoke-route' "${KERNEL_TEST_LOG}"; then
  echo "repo-root codex should route to kernel" >&2
  exit 1
fi

: > "${KERNEL_TEST_LOG}"
"${TEST_SHELL}" -lc '
  export HOME="'"${TMP_DIR}/home"'"
  export PATH="${HOME}/bin:/opt/homebrew/bin:/usr/bin:/bin"
  export KERNEL_TEST_LOG="'"${TMP_DIR}/log/orchestrator.log"'"
  export KERNEL_TEST_KERNEL_ROOT=present
  source "'"${SNIPPET}"'"
  codex exec "print only"
' >/dev/null
grep -Fq 'raw-codex exec print only' "${KERNEL_TEST_LOG}"

: > "${KERNEL_TEST_LOG}"
"${TEST_SHELL}" -lc '
  export HOME="'"${TMP_DIR}/home"'"
  export PATH="/usr/bin:/bin"
  export KERNEL_TEST_LOG="'"${TMP_DIR}/log/orchestrator.log"'"
  export KERNEL_TEST_KERNEL_ROOT=missing
  source "'"${SNIPPET}"'"
  codex smoke-home-fallback
' >/dev/null
grep -Fq 'raw-codex smoke-home-fallback' "${KERNEL_TEST_LOG}"

: > "${KERNEL_TEST_LOG}"
"${TEST_SHELL}" -lc '
  export HOME="'"${TMP_DIR}/home"'"
  export PATH="/usr/bin:/bin"
  export KERNEL_TEST_LOG="'"${TMP_DIR}/log/orchestrator.log"'"
  export RAW_CODEX_BIN=/nonexistent
  source "'"${SNIPPET}"'"
  codex-raw --version
' >/dev/null
grep -Fq 'raw-codex --version' "${KERNEL_TEST_LOG}"

echo "codex orchestrator snippet check passed"
