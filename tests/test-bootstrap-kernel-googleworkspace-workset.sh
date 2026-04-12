#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSET_SCRIPT="${SCRIPT_DIR}/scripts/local/bootstrap-kernel-googleworkspace-workset.sh"
BOOTSTRAP_SCRIPT="${SCRIPT_DIR}/scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

assert_ok() {
  local name="$1"
  shift
  total=$((total + 1))
  if "$@"; then
    echo "ok - ${name}"
    passed=$((passed + 1))
  else
    echo "not ok - ${name}"
    failed=$((failed + 1))
  fi
}

copy_ready_docs() {
  local repo_dir="$1"
  mkdir -p "${repo_dir}/docs"
  cp "${SCRIPT_DIR}/docs/kernel-googleworkspace-goal-2026-03-20.md" "${repo_dir}/docs/"
  cp "${SCRIPT_DIR}/docs/kernel-googleworkspace-issue-1-ready.md" "${repo_dir}/docs/"
  cp "${SCRIPT_DIR}/docs/kernel-googleworkspace-issue-2-ready.md" "${repo_dir}/docs/"
  cp "${SCRIPT_DIR}/docs/kernel-googleworkspace-issue-3-ready.md" "${repo_dir}/docs/"
  cp "${SCRIPT_DIR}/docs/kernel-googleworkspace-issue-4-ready.md" "${repo_dir}/docs/"
  cp "${SCRIPT_DIR}/docs/kernel-googleworkspace-issue-5-ready.md" "${repo_dir}/docs/"
}

test_builds_local_workset() {
  local repo_dir="${tmp_dir}/repo"
  mkdir -p "${repo_dir}/scripts/local"
  copy_ready_docs "${repo_dir}"
  cp "${BOOTSTRAP_SCRIPT}" "${repo_dir}/scripts/local/"
  cp "${WORKSET_SCRIPT}" "${repo_dir}/scripts/local/"

  (
    cd "${repo_dir}"
    bash scripts/local/bootstrap-kernel-googleworkspace-workset.sh \
      --out-dir .fugue/test-workset \
      --start-issue-number 9301 >/dev/null
  )

  head -n 1 "${repo_dir}/.fugue/test-workset/manifest.tsv" | grep -q '^local_issue_number' &&
    [[ "$(wc -l < "${repo_dir}/.fugue/test-workset/manifest.tsv" | tr -d '[:space:]')" == "6" ]] &&
    grep -q 'readonly-evidence' "${repo_dir}/.fugue/test-workset/manifest.tsv" &&
    grep -q 'mailbox-readonly' "${repo_dir}/.fugue/test-workset/manifest.tsv" &&
    grep -q 'meeting-prep' "${repo_dir}/.fugue/pre-implement/issue-9301-todo.md" &&
    grep -q 'weekly-digest' "${repo_dir}/.fugue/pre-implement/issue-9302-todo.md" &&
    grep -q 'Kernel Google Workspace Workset' "${repo_dir}/.fugue/test-workset/README.md"
}

echo "=== bootstrap-kernel-googleworkspace-workset.sh unit tests ==="
echo ""

assert_ok "builds-local-workset" test_builds_local_workset

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
