#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/launchers/kernel"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/.codex/prompts" "${HOME}/bin"
KERNEL_LAUNCHER_BIN="${HOME}/bin/kernel"

cp "${SCRIPT}" "${KERNEL_LAUNCHER_BIN}"
chmod +x "${KERNEL_LAUNCHER_BIN}"

cat > "${HOME}/bin/orchestrator-entrypoint-hint" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${HOME}/bin/orchestrator-entrypoint-hint"

cat > "${HOME}/.codex/prompts/kernel.md" <<'EOF'
---
description: test kernel prompt
---
Start Kernel launcher test.
$ARGUMENTS
EOF

cat > "${HOME}/bin/codex-prompt-launch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
prompt_name="${1:-}"
shift || true
prompt_path="${HOME}/.codex/prompts/${prompt_name}.md"
if [[ ! -f "${prompt_path}" ]]; then
  echo "codex prompt '${prompt_name}' not found in the current repo or ~/.codex/prompts" >&2
  exit 1
fi
cat "${prompt_path}"
if [[ $# -gt 0 ]]; then
  printf '\n%s\n' "$*"
fi
EOF
chmod +x "${HOME}/bin/codex-prompt-launch"

cat > "${HOME}/bin/codex-kernel-guard" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "guard should not be called in this test" >&2
exit 99
EOF
chmod +x "${HOME}/bin/codex-kernel-guard"

cat > "${HOME}/bin/kernel-root" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${HOME}/bin/kernel-root"

out="$(cd "${TMP_DIR}" && CODEX_BIN=/bin/echo CODEX_KERNEL_REQUIRE_GUARD=0 CODEX_KERNEL_USE_GUARD_LAUNCH=0 CODEX_KERNEL_PROVIDER_CHECK=0 "${KERNEL_LAUNCHER_BIN}" focus-text)"
grep -Fq 'Start Kernel launcher test.' <<<"${out}"
grep -Fq 'focus-text' <<<"${out}"
if grep -Fq '[orchestrator]' <<<"${out}"; then
  echo "kernel should stay quiet by default" >&2
  exit 1
fi

rm -f "${HOME}/.codex/prompts/kernel.md"
set +e
out="$(cd "${TMP_DIR}" && CODEX_BIN=/bin/echo CODEX_KERNEL_REQUIRE_GUARD=0 CODEX_KERNEL_USE_GUARD_LAUNCH=0 CODEX_KERNEL_PROVIDER_CHECK=0 "${KERNEL_LAUNCHER_BIN}" 2>&1)"
rc=$?
set -e
[[ "${rc}" -ne 0 ]]
grep -Fq "codex prompt 'kernel' not found" <<<"${out}"

echo "kernel launcher check passed"
