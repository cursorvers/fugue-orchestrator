#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export HOME="${TMP_DIR}/home"
mkdir -p "${HOME}/bin" "${TMP_DIR}/log"

cat > "${HOME}/bin/orchestrator-entrypoint-hint" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${HOME}/bin/orchestrator-entrypoint-hint"

cat > "${HOME}/bin/codex-prompt-launch" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${VOTE_TEST_LOG}"
EOF
chmod +x "${HOME}/bin/codex-prompt-launch"

cp "${ROOT_DIR}/scripts/local/launchers/vote" "${HOME}/bin/vote"
cp "${ROOT_DIR}/scripts/local/launchers/v" "${HOME}/bin/v"
chmod +x "${HOME}/bin/vote" "${HOME}/bin/v"

export VOTE_TEST_LOG="${TMP_DIR}/log/vote.log"

"${HOME}/bin/vote" focus-one
"${HOME}/bin/v" focus-two

grep -Fqx 'vote focus-one' "${VOTE_TEST_LOG}"
grep -Fqx 'v focus-two' "${VOTE_TEST_LOG}"

echo "vote launchers check passed"
