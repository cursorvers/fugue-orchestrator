#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_RUNNER="${ROOT_DIR}/scripts/local/run-local-orchestration.sh"
LINKED_RUNNER="${ROOT_DIR}/scripts/local/run-linked-systems.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/parallel-floor.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

passed=0
failed=0

assert_rejects() {
  local name="$1"
  shift
  local stderr_file="${TMP_DIR}/${name}.stderr"
  if "$@" >"${TMP_DIR}/${name}.stdout" 2>"${stderr_file}"; then
    echo "FAIL [${name}]: command unexpectedly succeeded"
    failed=$((failed + 1))
    return
  fi
  if ! grep -Fq 'integer >= 2' "${stderr_file}"; then
    echo "FAIL [${name}]: expected integer >= 2 policy rejection"
    cat "${stderr_file}"
    failed=$((failed + 1))
    return
  fi
  echo "PASS [${name}]"
  passed=$((passed + 1))
}

echo "=== parallel-floor-policy.sh unit tests ==="
echo ""

assert_rejects "run-local-max-parallel-floor" \
  bash "${LOCAL_RUNNER}" \
  --issue 1 \
  --force-manual-context \
  --issue-title "Test" \
  --issue-body "Body" \
  --max-parallel 1

assert_rejects "run-local-linked-max-parallel-floor" \
  bash "${LOCAL_RUNNER}" \
  --issue 1 \
  --force-manual-context \
  --issue-title "Test" \
  --issue-body "Body" \
  --linked-max-parallel 1

assert_rejects "run-linked-max-parallel-floor" \
  bash "${LINKED_RUNNER}" \
  --issue 1 \
  --max-parallel 1

echo ""
echo "=== Results: ${passed}/3 passed, ${failed} failed ==="

if (( failed > 0 )); then
  exit 1
fi
