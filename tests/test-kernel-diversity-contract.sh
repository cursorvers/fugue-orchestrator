#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

check_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Fq -- "${pattern}" "${file}"; then
    echo "PASS [${label}]"
  else
    echo "FAIL [${label}]: missing pattern '${pattern}' in ${file}" >&2
    exit 1
  fi
}

check_absent() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Fq -- "${pattern}" "${file}"; then
    echo "FAIL [${label}]: unexpected pattern '${pattern}' in ${file}" >&2
    exit 1
  else
    echo "PASS [${label}]"
  fi
}

check_contains "${ROOT_DIR}/scripts/harness/generate-tutti-comment.sh" "multi-agent diversity:" "integrated comment shows diversity"
check_contains "${ROOT_DIR}/scripts/local/run-local-orchestration.sh" "- multi-agent diversity:" "local summary shows diversity"
check_contains "${ROOT_DIR}/.github/workflows/fugue-tutti-caller.yml" "diversity=planned(codex+claude+glm" "caller announces planned diversity"
check_contains "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" "--implementation-phase" "router passes implementation phase into matrix builder"
check_contains "${ROOT_DIR}/.github/workflows/fugue-tutti-router.yml" "--has-implement \"\${implementation_phase}\"" "router risk policy sees implementation phase"
check_absent "${ROOT_DIR}/scripts/harness/aggregate-tutti-votes.sh" "claude-waived" "glm no longer waives claude baseline"

echo "kernel diversity contract checks passed"
