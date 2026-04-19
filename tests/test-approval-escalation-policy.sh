#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_ROUTER="${ROOT_DIR}/.github/workflows/fugue-task-router.yml"
TUTTI_CALLER="${ROOT_DIR}/.github/workflows/fugue-tutti-caller.yml"
CODEX_IMPLEMENT="${ROOT_DIR}/.github/workflows/fugue-codex-implement.yml"

failed=0

assert_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq -- "${needle}" "${file}"; then
    echo "PASS [${label}]"
  else
    echo "FAIL [${label}]" >&2
    failed=$((failed + 1))
  fi
}

assert_not_contains() {
  local content="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq -- "${needle}" <<<"${content}"; then
    echo "FAIL [${label}]" >&2
    failed=$((failed + 1))
  else
    echo "PASS [${label}]"
  fi
}

task_backup_block="$(sed -n '/name: Backup-safe hold notice/,/name: Add processing label/p' "${TASK_ROUTER}")"
tutti_backup_block="$(sed -n '/backup-safe-hold:/,/  # Review mode:/p' "${TUTTI_CALLER}")"
provider_failure_block="$(sed -n '/if \[\[ -z "${RESP}" \]\]/,/elif \[\[ "${RESP_PROVIDER}"/p' "${TASK_ROUTER}")"
tier3_block="$(sed -n '/name: Tier 3 fallback/,/name: Remove processing label/p' "${TASK_ROUTER}")"
credential_guard_block="$(sed -n '/name: Guard required secrets/,/name: Install Codex CLI/p' "${CODEX_IMPLEMENT}")"

assert_contains "${TASK_ROUTER}" "--add-label \"needs-review\"" "task-router has needs-review fallback"
assert_not_contains "${task_backup_block}" "--add-label \"needs-human\"" "task-router backup-safe avoids needs-human"
assert_not_contains "${tutti_backup_block}" "--add-label \"needs-human\"" "tutti-caller backup-safe avoids needs-human"
assert_not_contains "${provider_failure_block}" "--add-label \"needs-human\"" "provider failure avoids needs-human"
assert_not_contains "${tier3_block}" "--add-label \"needs-human\"" "tier3 fallback avoids needs-human"
assert_contains "${CODEX_IMPLEMENT}" 'if [[ "${skip_reason}" == "missing-target-repo-pat" ]]; then' "missing PAT remains human boundary"
assert_contains "${CODEX_IMPLEMENT}" '--add-label "needs-review" --remove-label "needs-human"' "missing OpenAI key is ops review"
assert_not_contains "${credential_guard_block}" 'missing secret `OPENAI_API_KEY`. Escalating to humans.' "missing OpenAI key not human escalation"

if (( failed > 0 )); then
  echo "=== Results: failed ${failed} ===" >&2
  exit 1
fi

echo "=== Results: all passed ==="
