#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/kernel-completion-agent.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

BOOTSTRAP_SCRIPT="${TMP_DIR}/bootstrap.sh"
MARKER_FILE="${TMP_DIR}/marker.txt"

cat > "${BOOTSTRAP_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'bootstrapped\n' >> "${KERNEL_COMPLETION_AGENT_MARKER}"
if [[ "${KERNEL_COMPLETION_AGENT_FAIL:-false}" == "true" ]]; then
  exit 42
fi
EOF
chmod +x "${BOOTSTRAP_SCRIPT}"

KERNEL_AUTO_COMPLETION_AGENT=true \
KERNEL_COMPLETION_AGENT_MARKER="${MARKER_FILE}" \
KERNEL_COMPLETION_AGENT_BOOTSTRAP_SCRIPT="${BOOTSTRAP_SCRIPT}" \
bash "${SCRIPT}" ensure

grep -Fq 'bootstrapped' "${MARKER_FILE}" || {
  echo "ensure should bootstrap completion agent when explicitly enabled" >&2
  exit 1
}

: > "${MARKER_FILE}"
KERNEL_COMPLETION_AGENT_MARKER="${MARKER_FILE}" \
KERNEL_COMPLETION_AGENT_BOOTSTRAP_SCRIPT="${BOOTSTRAP_SCRIPT}" \
bash "${SCRIPT}" ensure

if [[ -s "${MARKER_FILE}" ]]; then
  echo "ensure should skip bootstrap by default" >&2
  exit 1
fi

: > "${MARKER_FILE}"
KERNEL_AUTO_COMPLETION_AGENT=false \
KERNEL_COMPLETION_AGENT_MARKER="${MARKER_FILE}" \
KERNEL_COMPLETION_AGENT_BOOTSTRAP_SCRIPT="${BOOTSTRAP_SCRIPT}" \
bash "${SCRIPT}" ensure

if [[ -s "${MARKER_FILE}" ]]; then
  echo "ensure should skip bootstrap when auto completion agent is disabled" >&2
  exit 1
fi

: > "${MARKER_FILE}"
KERNEL_AUTO_COMPLETION_AGENT=true \
ORCH_DRY_RUN=1 \
KERNEL_COMPLETION_AGENT_MARKER="${MARKER_FILE}" \
KERNEL_COMPLETION_AGENT_BOOTSTRAP_SCRIPT="${BOOTSTRAP_SCRIPT}" \
bash "${SCRIPT}" ensure

if [[ -s "${MARKER_FILE}" ]]; then
  echo "ensure should skip bootstrap during dry-run" >&2
  exit 1
fi

: > "${MARKER_FILE}"
KERNEL_AUTO_COMPLETION_AGENT=true \
KERNEL_COMPLETION_AGENT_MARKER="${MARKER_FILE}" \
KERNEL_COMPLETION_AGENT_BOOTSTRAP_SCRIPT="${BOOTSTRAP_SCRIPT}" \
KERNEL_COMPLETION_AGENT_FAIL=true \
bash "${SCRIPT}" ensure

grep -Fq 'bootstrapped' "${MARKER_FILE}" || {
  echo "ensure should attempt bootstrap even when failures are swallowed" >&2
  exit 1
}

KERNEL_AUTO_COMPLETION_AGENT=true \
KERNEL_COMPLETION_AGENT_BOOTSTRAP_SCRIPT="${TMP_DIR}/missing.sh" \
bash "${SCRIPT}" ensure

echo "kernel completion agent check passed"
