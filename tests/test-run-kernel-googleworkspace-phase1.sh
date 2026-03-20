#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/scripts/local/run-kernel-googleworkspace-phase1.sh"

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

test_prepare_mode_outputs_command() {
  local out_file="${tmp_dir}/phase1.txt"
  (
    cd "${SCRIPT_DIR}"
    bash "${SCRIPT}" --prepare --out-dir "${tmp_dir}/out" > "${out_file}"
  )

  grep -q '^mode=prepare$' "${out_file}" &&
    grep -Fq 'WORKSPACE_ACTIONS=meeting-prep\,standup-report' "${out_file}" &&
    grep -q 'googleworkspace-preflight-enrich.sh' "${out_file}" &&
    grep -q '^report=' "${out_file}"
}

echo "=== run-kernel-googleworkspace-phase1.sh unit tests ==="
echo ""

assert_ok "prepare-mode-outputs-command" test_prepare_mode_outputs_command

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
