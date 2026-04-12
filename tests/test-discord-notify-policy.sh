#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/integrations/discord-notify.sh"

echo "=== discord-notify policy tests ==="
echo ""

run_expect_status() {
  local test_name="$1"
  local expected_status="$2"
  shift 2

  local run_dir
  run_dir="$(mktemp -d)"
  env "$@" "${SCRIPT}" --mode smoke --run-dir "${run_dir}" >/tmp/"${test_name}".out 2>/tmp/"${test_name}".err

  local actual_status
  actual_status="$(awk -F= '$1=="status"{print $2}' "${run_dir}/discord-notify.meta" | tail -n1)"
  if [[ "${actual_status}" != "${expected_status}" ]]; then
    echo "FAIL [${test_name}]: status=${actual_status} (expected ${expected_status})"
    rm -rf "${run_dir}"
    return 1
  fi

  echo "PASS [${test_name}]"
  rm -rf "${run_dir}"
}

run_expect_status \
  "system-webhook-blocked-by-default" \
  "skipped-missing-config" \
  DISCORD_SYSTEM_WEBHOOK="https://example.com/system"

run_expect_status \
  "system-webhook-allowed-by-opt-in" \
  "ok" \
  DISCORD_NOTIFY_ALLOW_SYSTEM_WEBHOOK="true" \
  DISCORD_SYSTEM_WEBHOOK="https://example.com/system"

run_expect_status \
  "generic-webhook-still-works" \
  "ok" \
  DISCORD_WEBHOOK_URL="https://example.com/generic"

echo ""
echo "PASS [discord-notify-policy]"
