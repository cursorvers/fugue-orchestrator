#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/scripts/local/simulate-kernel-googleworkspace-phase2-mailbox.sh"

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

test_simulation_generates_report() {
  local repo_dir="${tmp_dir}/repo"
  mkdir -p "${repo_dir}/scripts/local" "${repo_dir}/scripts/harness"
  cp "${SCRIPT}" "${repo_dir}/scripts/local/"
  cp "${SCRIPT_DIR}/scripts/harness/googleworkspace-preflight-enrich.sh" "${repo_dir}/scripts/harness/"

  (
    cd "${repo_dir}"
    bash scripts/local/simulate-kernel-googleworkspace-phase2-mailbox.sh \
      --out-dir .fugue/sim >/dev/null
  )

  grep -q 'weekly-digest' "${repo_dir}/.fugue/sim/phase2-mailbox-simulated-report.md" &&
    grep -q 'gmail-triage' "${repo_dir}/.fugue/sim/phase2-mailbox-simulated-report.md" &&
    grep -q '^workspace_preflight_status=ok$' "${repo_dir}/.fugue/sim/phase2-mailbox-simulated-output.txt"
}

echo "=== simulate-kernel-googleworkspace-phase2-mailbox.sh unit tests ==="
echo ""

assert_ok "simulation-generates-report" test_simulation_generates_report

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
