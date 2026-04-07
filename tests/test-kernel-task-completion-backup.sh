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
import json
import os
import sys

if __name__ == "__main__":
    log_path = os.environ.get("BACKUP_CLI_LOG")
    if log_path:
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write(" ".join(sys.argv[1:]) + "\n")
    if len(sys.argv) > 1 and sys.argv[1] == "backup-record":
        args = sys.argv[2:]
        values = {}
        i = 0
        while i < len(args):
            if args[i].startswith("--") and i + 1 < len(args):
                values[args[i][2:]] = args[i + 1]
                i += 2
            else:
                i += 1
        state_root = os.environ.get("STATE_ROOT", "")
        if state_root:
            os.makedirs(state_root, exist_ok=True)
            journal_path = os.path.join(state_root, "task-completion-journal.jsonl")
            payload = {
                "session_id": values.get("session-id", ""),
                "source": values.get("source", ""),
                "summary_text": values.get("summary", ""),
                "title": values.get("title", ""),
                "completed_at": values.get("completed-at", "2026-04-07T00:00:00Z"),
            }
            with open(journal_path, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(payload, ensure_ascii=True) + "\n")
    raise SystemExit(0)
EOF

STATE_ROOT="${TMP_DIR}/state"
LOG_DIR="${TMP_DIR}/logs"
PLIST_PATH="${TMP_DIR}/com.cursorvers.kernel-task-completion-backup.plist"
BACKUP_CLI_LOG="${TMP_DIR}/backup-cli.log"
FIXED_COMPLETED_AT="2026-04-07T08:10:00Z"

TOOLS_ROOT="${TOOLS_ROOT}" \
STATE_ROOT="${STATE_ROOT}" \
BACKUP_CLI_LOG="${BACKUP_CLI_LOG}" \
bash "${RUNNER}" \
  --assistant claude \
  --source fugue-run-complete \
  --session-id test-session \
  --summary "Kernel backup smoke" \
  --cwd "${ROOT_DIR}" \
  --title "Smoke" \
  --completed-at "${FIXED_COMPLETED_AT}" \
  --no-gha \
  --dry-run \
  >/dev/null \
  2>/dev/null

grep -Fq -- 'backup-record --assistant claude --source fugue-run-complete' "${BACKUP_CLI_LOG}" || {
  echo "runner should forward assistant/source overrides to backup-record" >&2
  exit 1
}

before_lines="$(wc -l < "${BACKUP_CLI_LOG}" | tr -d ' ')"
TOOLS_ROOT="${TOOLS_ROOT}" \
STATE_ROOT="${STATE_ROOT}" \
BACKUP_CLI_LOG="${BACKUP_CLI_LOG}" \
bash "${RUNNER}" \
  --assistant claude \
  --source fugue-run-complete \
  --session-id test-session \
  --summary "Kernel backup smoke" \
  --cwd "${ROOT_DIR}" \
  --title "Smoke" \
  --completed-at "${FIXED_COMPLETED_AT}" \
  --no-gha \
  --dry-run \
  >/dev/null \
  2>/dev/null
after_lines="$(wc -l < "${BACKUP_CLI_LOG}" | tr -d ' ')"
[[ "${before_lines}" == "${after_lines}" ]] || {
  echo "runner should dedupe duplicate terminal explicit records before invoking backup-record" >&2
  exit 1
}

TOOLS_ROOT="${TOOLS_ROOT}" \
STATE_ROOT="${STATE_ROOT}" \
BACKUP_CLI_LOG="${BACKUP_CLI_LOG}" \
bash "${RUNNER}" \
  --assistant claude \
  --source kernel-run-complete \
  --session-id test-session-bound \
  --summary "Kernel backup bound" \
  --cwd "${ROOT_DIR}" \
  --title "Bound" \
  --project-os-ticket-id proj-123 \
  --acceptance "Ship backup integration" \
  --authority-scope kernel_execution_only \
  --no-gha \
  --dry-run \
  >/dev/null \
  2>/dev/null

grep -Fq -- '--project-os-ticket-id proj-123 --acceptance Ship backup integration --authority-scope kernel_execution_only' "${BACKUP_CLI_LOG}" || {
  echo "runner should forward Project OS fields to backup-record" >&2
  exit 1
}

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
