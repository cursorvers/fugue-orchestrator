#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT_DIR}/scripts/local/run-kernel-task-completion-backup.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

export TOOLS_ROOT="${TMP_DIR}/missing-tools"
export STATE_ROOT="${TMP_DIR}/state"
export KERNEL_COMPACT_DIR="${TMP_DIR}/compact"
mkdir -p "${STATE_ROOT}" "${KERNEL_COMPACT_DIR}"

cat >"${KERNEL_COMPACT_DIR}/record-session.json" <<'EOF'
{"run_id":"record-session","project":"fugue-orchestrator","purpose":"completion","current_phase":"verify","mode":"healthy","tmux_session":"fugue-orchestrator__completion","owner":"codex","active_models":["codex","glm","gemini-cli"],"blocking_reason":"","next_action":["record-completion"],"decisions":["d1"],"summary":["done"],"last_event":"phase_completed","updated_at":"2026-03-20T00:00:00Z"}
EOF

bash "${RUNNER}" \
  --assistant codex \
  --source kernel-run-complete \
  --session-id record-session \
  --summary "Kernel fallback backup smoke" \
  --cwd "${ROOT_DIR}" \
  --title "Fallback Smoke" \
  --no-gha \
  --dry-run

journal="${STATE_ROOT}/task-completion-journal.jsonl"
[[ -f "${journal}" ]]
grep -Fq '"record_id"' "${journal}"
grep -Fq '"assistant":"codex"' "${journal}"
grep -Fq '"summary_text":"Kernel fallback backup smoke"' "${journal}"
grep -Fq '"gha_mirror_path":"backups/task-completion/' "${journal}"
grep -Fq '"orchestration_compliance":"kernel-run-complete"' "${journal}"

bash "${RUNNER}" \
  --assistant codex \
  --source kernel-run-complete \
  --session-id record-session \
  --summary "Kernel fallback backup smoke duplicate" \
  --cwd "${ROOT_DIR}" \
  --title "Fallback Smoke Duplicate" \
  --no-gha \
  --dry-run

kernel_run_complete_count="$(grep -c '"source":"kernel-run-complete"' "${journal}")"
[[ "${kernel_run_complete_count}" == "1" ]]
if grep -Fq '"summary_text":"Kernel fallback backup smoke duplicate"' "${journal}"; then
  echo "terminal completion backup should be deduped for the same session/source window" >&2
  exit 1
fi

bash "${RUNNER}" \
  --assistant codex \
  --source kernel-progress-save \
  --session-id record-session \
  --summary "Kernel progress backup smoke" \
  --cwd "${ROOT_DIR}" \
  --title "Fallback Progress" \
  --no-gha \
  --dry-run

grep -Fq '"orchestration_compliance":"kernel-progress-save"' "${journal}"

bash "${RUNNER}" \
  --assistant codex \
  --source kernel-progress-save \
  --session-id record-session \
  --summary "Kernel progress backup smoke" \
  --cwd "${ROOT_DIR}" \
  --title "Fallback Progress" \
  --no-gha \
  --dry-run

kernel_progress_count="$(grep -c '"source":"kernel-progress-save"' "${journal}")"
[[ "${kernel_progress_count}" == "1" ]]

bash "${RUNNER}" \
  --assistant codex \
  --source kernel-progress-save \
  --session-id record-session \
  --summary "Kernel progress backup smoke v2" \
  --cwd "${ROOT_DIR}" \
  --title "Fallback Progress" \
  --no-gha \
  --dry-run

kernel_progress_count="$(grep -c '"source":"kernel-progress-save"' "${journal}")"
[[ "${kernel_progress_count}" == "2" ]]
grep -Fq '"summary_text":"Kernel progress backup smoke v2"' "${journal}"

echo "kernel task completion backup fallback check passed"
