#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0

assert_contains_regex() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if grep -Eq "${pattern}" "${path}"; then
    echo "[PASS] ${label}" >&2
  else
    echo "[FAIL] ${label}: pattern '${pattern}' not found in ${path}" >&2
    failures=$((failures + 1))
  fi
}

assert_not_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "${needle}" "${path}"; then
    echo "[FAIL] ${label}: found '${needle}' in ${path}" >&2
    failures=$((failures + 1))
  else
    echo "[PASS] ${label}" >&2
  fi
}

assert_contains_regex "${ROOT_DIR}/scripts/local/run-local-orchestration.sh" 'CODEX_MAIN_MODEL="\$\{CODEX_MAIN_MODEL:-gpt-5-codex\}"' "local runner main default"
assert_contains_regex "${ROOT_DIR}/scripts/lib/model-policy.sh" 'DEFAULT_CODEX_MAIN="gpt-5-codex"' "model policy main default"
assert_contains_regex "${ROOT_DIR}/.github/workflows/fugue-tutti-caller.yml" "CODEX_MAIN_MODEL: \\$\\{\\{ vars\\.FUGUE_CODEX_MAIN_MODEL \\|\\| 'gpt-5-codex' \\}\\}" "tutti caller main default"
assert_contains_regex "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" "CODEX_MAIN_MODEL: \\$\\{\\{ vars\\.FUGUE_CODEX_MAIN_MODEL \\|\\| 'gpt-5-codex' \\}\\}" "tutti router main default"
assert_contains_regex "${ROOT_DIR}/.github/workflows/fugue-task-router.yml" "CODEX_MAIN_MODEL: \\$\\{\\{ vars\\.FUGUE_CODEX_MAIN_MODEL \\|\\| 'gpt-5-codex' \\}\\}" "task router main default"
assert_contains_regex "${ROOT_DIR}/.github/workflows/fugue-task-router.yml" 'CODEX_MAIN_MODEL="\$\(echo "\$\{CODEX_MAIN_MODEL:-gpt-5-codex\}"' "task router main normalization"
assert_contains_regex "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" 'CODEX_MAIN_MODEL="\$\(echo "\$\{CODEX_MAIN_MODEL:-gpt-5-codex\}"' "tutti router main normalization"
assert_not_contains "${ROOT_DIR}/.github/workflows/fugue-task-router.yml" 'CODEX_MAIN_MODEL="gpt-5.4"' "task router avoids hardcoded gpt-5.4"
assert_not_contains "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" 'CODEX_MAIN_MODEL="gpt-5.4"' "tutti router avoids hardcoded gpt-5.4"

if (( failures > 0 )); then
  echo "codex live defaults check failed: ${failures} failure(s)" >&2
  exit 1
fi

echo "codex live defaults check passed"
