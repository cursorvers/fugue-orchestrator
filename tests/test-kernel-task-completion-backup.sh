#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT_DIR}/scripts/local/run-kernel-task-completion-backup.sh"
BOOTSTRAP="${ROOT_DIR}/scripts/local/bootstrap-kernel-task-completion-backup-agent.sh"
WORKFLOW_FILE="${ROOT_DIR}/.github/workflows/kernel-task-completion-backup.yml"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

TOOLS_ROOT="${TMP_DIR}/codex-kernel-guard"
mkdir -p "${TOOLS_ROOT}/src/codex_kernel_guard"
cat > "${TOOLS_ROOT}/src/codex_kernel_guard/__init__.py" <<'EOF'
EOF
cat > "${TOOLS_ROOT}/src/codex_kernel_guard/cli.py" <<'EOF'
from __future__ import annotations
if __name__ == "__main__":
    raise SystemExit(0)
EOF

STATE_ROOT="${TMP_DIR}/state"
LOG_DIR="${TMP_DIR}/logs"
PLIST_PATH="${TMP_DIR}/com.cursorvers.kernel-task-completion-backup.plist"

TOOLS_ROOT="${TOOLS_ROOT}" \
STATE_ROOT="${STATE_ROOT}" \
bash "${RUNNER}" \
  --assistant claude \
  --source claude-stop-hook \
  --session-id test-session \
  --summary "Kernel backup smoke" \
  --cwd "${ROOT_DIR}" \
  --title "Smoke" \
  --no-gha \
  --dry-run \
  >/dev/null \
  2>/dev/null

TOOLS_ROOT="${TOOLS_ROOT}" \
STATE_ROOT="${STATE_ROOT}" \
LOG_DIR="${LOG_DIR}" \
bash "${BOOTSTRAP}" --plist "${PLIST_PATH}" --runner "${RUNNER}" --dry-run > "${TMP_DIR}/bootstrap.out"

grep -q "com.cursorvers.kernel-task-completion-backup" "${TMP_DIR}/bootstrap.out" || {
  echo "bootstrap dry-run did not emit agent label" >&2
  exit 1
}

grep -q "repository_dispatch:" "${WORKFLOW_FILE}" || {
  echo "workflow must accept repository_dispatch" >&2
  exit 1
}

grep -q "contents: write" "${WORKFLOW_FILE}" || {
  echo "workflow must request contents write for durable mirror branch" >&2
  exit 1
}

grep -q "github.event.client_payload.payload_b64" "${WORKFLOW_FILE}" || {
  echo "workflow must support repository_dispatch payload lookup" >&2
  exit 1
}

grep -q "steps.decode.outputs.safe_record_id" "${WORKFLOW_FILE}" || {
  echo "workflow must use sanitized record id outputs downstream" >&2
  exit 1
}

grep -q "kernel-task-completion-backups" "${WORKFLOW_FILE}" || {
  echo "workflow must persist a durable mirror branch" >&2
  exit 1
}

grep -q "backups/task-completion-receipts" "${WORKFLOW_FILE}" || {
  echo "workflow must persist receipt files for provenance verification" >&2
  exit 1
}

echo "PASS [kernel-task-completion-backup]"
