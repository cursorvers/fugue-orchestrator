#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT_DIR}/scripts/local/create-kernel-googleworkspace-issues.sh"

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

test_dry_run_lists_five_issues() {
  local out_file="${tmp_dir}/dryrun.txt"
  (
    cd "${SCRIPT_DIR}"
    bash "${SCRIPT}" --dry-run > "${out_file}"
  )

  [[ "$(grep -c '^ISSUE ' "${out_file}")" == "5" ]] &&
    grep -q 'title: task: revalidate kernel google workspace readonly evidence lane' "${out_file}" &&
    grep -q 'title: task: triage kernel google workspace extension lanes tasks pubsub slides' "${out_file}" &&
    grep -q 'orchestrator:codex' "${out_file}" &&
    grep -q 'orchestrator-assist:claude' "${out_file}"
}

test_dry_run_respects_assist_override() {
  local out_file="${tmp_dir}/assist.txt"
  (
    cd "${SCRIPT_DIR}"
    bash "${SCRIPT}" --dry-run --assist none > "${out_file}"
  )

  grep -q 'orchestrator-assist:none' "${out_file}"
}

echo "=== create-kernel-googleworkspace-issues.sh unit tests ==="
echo ""

assert_ok "dry-run-lists-five-issues" test_dry_run_lists_five_issues
assert_ok "dry-run-respects-assist-override" test_dry_run_respects_assist_override

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
