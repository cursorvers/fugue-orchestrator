#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh"

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

test_bootstrap_readonly_track() {
  local repo_dir="${tmp_dir}/readonly"
  mkdir -p "${repo_dir}/scripts/local" "${repo_dir}/tests"
  cp "${SCRIPT}" "${repo_dir}/scripts/local/"

  (
    cd "${repo_dir}"
    bash scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh \
      --issue-number 77 \
      --issue-title "Readonly revalidation" \
      --track readonly-evidence \
      --cycles 3 \
      --rounds 2 \
      --lessons-required >/dev/null
  )

  grep -q '^## Plan$' "${repo_dir}/.fugue/pre-implement/issue-77-todo.md" &&
    grep -q 'meeting-prep' "${repo_dir}/.fugue/pre-implement/issue-77-todo.md" &&
    ! grep -q 'weekly-digest' "${repo_dir}/.fugue/pre-implement/issue-77-todo.md" &&
    grep -q '^## Cycle 3$' "${repo_dir}/.fugue/pre-implement/issue-77-preflight.md" &&
    grep -q '^### 3. Critical Review$' "${repo_dir}/.fugue/pre-implement/issue-77-preflight.md" &&
    grep -q '^## Round 2$' "${repo_dir}/.fugue/implement/issue-77-implementation-loop.md" &&
    grep -Eq '^##[[:space:]]+Issue[[:space:]]+#77$' "${repo_dir}/.fugue/pre-implement/lessons.md"
}

test_mailbox_track_outputs() {
  local repo_dir="${tmp_dir}/mailbox"
  mkdir -p "${repo_dir}/scripts/local"
  cp "${SCRIPT}" "${repo_dir}/scripts/local/"

  (
    cd "${repo_dir}"
    bash scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh \
      --issue-number 89 \
      --track mailbox-readonly \
      --cycles 2 \
      --rounds 1 >/dev/null
  )

  grep -q 'weekly-digest' "${repo_dir}/.fugue/pre-implement/issue-89-todo.md" &&
    grep -q 'gmail-triage' "${repo_dir}/.fugue/pre-implement/issue-89-todo.md" &&
    grep -q '^## Cycle 2$' "${repo_dir}/.fugue/pre-implement/issue-89-preflight.md" &&
    grep -q '^## Round 1$' "${repo_dir}/.fugue/implement/issue-89-implementation-loop.md"
}

test_refuses_overwrite_without_force() {
  local repo_dir="${tmp_dir}/overwrite"
  mkdir -p "${repo_dir}/scripts/local"
  cp "${SCRIPT}" "${repo_dir}/scripts/local/"

  (
    cd "${repo_dir}"
    bash scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh --issue-number 88 >/dev/null
  )

  if (
    cd "${repo_dir}" &&
      bash scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh --issue-number 88 >/dev/null 2>&1
  ); then
    return 1
  fi

  return 0
}

test_scope_min_track_outputs() {
  local repo_dir="${tmp_dir}/scope"
  mkdir -p "${repo_dir}/scripts/local"
  cp "${SCRIPT}" "${repo_dir}/scripts/local/"

  (
    cd "${repo_dir}"
    bash scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh \
      --issue-number 91 \
      --track scope-minimization \
      --cycles 4 \
      --rounds 3 >/dev/null
  )

  grep -q 'mailbox readonly operator auth profile' "${repo_dir}/.fugue/pre-implement/issue-91-todo.md" &&
    grep -q 'gws auth login --full' "${repo_dir}/.fugue/pre-implement/issue-91-todo.md" &&
    grep -q '^## Cycle 4$' "${repo_dir}/.fugue/pre-implement/issue-91-preflight.md" &&
    grep -q '^## Round 3$' "${repo_dir}/.fugue/implement/issue-91-implementation-loop.md"
}

echo "=== bootstrap-kernel-googleworkspace-artifacts.sh unit tests ==="
echo ""

assert_ok "bootstrap-readonly-track" test_bootstrap_readonly_track
assert_ok "mailbox-track-outputs" test_mailbox_track_outputs
assert_ok "refuses-overwrite-without-force" test_refuses_overwrite_without_force
assert_ok "scope-min-track-outputs" test_scope_min_track_outputs

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
