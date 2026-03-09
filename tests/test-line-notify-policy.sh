#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/integrations/line-notify.sh"

echo "=== line-notify policy tests ==="
echo ""

run_expect_fail() {
  local test_name="$1"
  local expected_status="$2"
  shift 2

  local run_dir
  run_dir="$(mktemp -d)"
  if env "$@" "${SCRIPT}" --mode execute --run-dir "${run_dir}" >/tmp/"${test_name}".out 2>/tmp/"${test_name}".err; then
    echo "FAIL [${test_name}]: expected failure"
    rm -rf "${run_dir}"
    return 1
  fi

  local actual_status
  actual_status="$(awk -F= '$1=="status"{print $2}' "${run_dir}/line-notify.meta" | tail -n1)"
  if [[ "${actual_status}" != "${expected_status}" ]]; then
    echo "FAIL [${test_name}]: status=${actual_status} (expected ${expected_status})"
    rm -rf "${run_dir}"
    return 1
  fi

  echo "PASS [${test_name}]"
  rm -rf "${run_dir}"
}

run_expect_ok() {
  local test_name="$1"
  shift

  local run_dir
  run_dir="$(mktemp -d)"
  env "$@" "${SCRIPT}" --mode smoke --run-dir "${run_dir}" >/tmp/"${test_name}".out 2>/tmp/"${test_name}".err

  local actual_status
  actual_status="$(awk -F= '$1=="status"{print $2}' "${run_dir}/line-notify.meta" | tail -n1)"
  if [[ "${actual_status}" != "ok" ]]; then
    echo "FAIL [${test_name}]: status=${actual_status} (expected ok)"
    rm -rf "${run_dir}"
    return 1
  fi

  echo "PASS [${test_name}]"
  rm -rf "${run_dir}"
}

run_expect_fail \
  "missing-purpose-blocked" \
  "error-missing-purpose" \
  LINE_WEBHOOK_URL="https://example.com/outbound"

run_expect_fail \
  "system-log-purpose-blocked" \
  "error-prohibited-purpose" \
  LINE_NOTIFY_PURPOSE="system-log" \
  LINE_WEBHOOK_URL="https://example.com/outbound"

run_expect_ok \
  "user-facing-purpose-allowed-in-smoke" \
  LINE_NOTIFY_PURPOSE="user-facing" \
  LINE_WEBHOOK_URL="https://example.com/outbound"

echo ""
echo "PASS [line-notify-policy]"
