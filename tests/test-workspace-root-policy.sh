#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/workspace-root-policy.sh"

passed=0
failed=0
default_roots="$(fugue_default_workspace_roots "${ROOT_DIR}")"
default_tmp_root="$(printf '%s' "${default_roots}" | cut -d: -f2)"
approved_tmp_root="${default_tmp_root}"
rejected_parent="/tmp/fugue-root-policy-rejected-$$"

if ! mkdir -p "${approved_tmp_root}" 2>/dev/null; then
  approved_tmp_root="${ROOT_DIR}/.fugue/dev-tmp-root"
  export FUGUE_APPROVED_WORKSPACE_ROOTS="${ROOT_DIR}/.fugue:${approved_tmp_root}"
  mkdir -p "${approved_tmp_root}"
fi

assert_case() {
  local name="$1"
  local target="$2"
  local expected="$3"
  local assert_no_side_effect="${4:-false}"
  local stderr_file
  stderr_file="$(mktemp "${TMPDIR:-/tmp}/workspace-root-policy.XXXXXX.stderr")"

  if result="$(fugue_resolve_workspace_dir "${ROOT_DIR}" "${target}" "test workspace" 2>"${stderr_file}")"; then
    if [[ "${expected}" != "ok" ]]; then
      echo "FAIL [${name}]: expected rejection, got ${result}"
      failed=$((failed + 1))
      rm -f "${stderr_file}"
      return
    fi
    echo "PASS [${name}]"
    passed=$((passed + 1))
    rm -f "${stderr_file}"
    return
  fi

  if [[ "${expected}" != "error" ]]; then
    echo "FAIL [${name}]: expected success"
    cat "${stderr_file}"
    failed=$((failed + 1))
    rm -f "${stderr_file}"
    return
  fi
  if ! grep -Fq 'approved workspace roots' "${stderr_file}"; then
    echo "FAIL [${name}]: expected approved-roots error"
    cat "${stderr_file}"
    failed=$((failed + 1))
    rm -f "${stderr_file}"
    return
  fi
  if [[ "${assert_no_side_effect}" == "true" && -e "$(dirname "${target}")" ]]; then
    echo "FAIL [${name}]: rejected path created parent directory"
    failed=$((failed + 1))
    rm -f "${stderr_file}"
    return
  fi
  echo "PASS [${name}]"
  passed=$((passed + 1))
  rm -f "${stderr_file}"
}

echo "=== workspace-root-policy.sh unit tests ==="
echo ""

rm -rf "${rejected_parent}"

assert_case "repo-fugue-root-allowed" "${ROOT_DIR}/.fugue/local-run/test-case" "ok"
assert_case "dev-tmp-root-allowed" "${approved_tmp_root}/fugue-root-policy/test-case" "ok"
assert_case "tmp-root-rejected" "${rejected_parent}/test-case" "error" "true"

echo ""
echo "=== Results: ${passed}/3 passed, ${failed} failed ==="

if (( failed > 0 )); then
  exit 1
fi
