#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="${SCRIPT_DIR}/scripts/lib/mcp-adapter-policy.sh"

passed=0
failed=0
total=0

assert_field() {
  local test_name="$1"
  local field_name="$2"
  local expected_value="$3"
  shift 3

  total=$((total + 1))
  local output
  output="$("${POLICY}" "$@")" || {
    echo "FAIL [${test_name}]: script exited with error"
    failed=$((failed + 1))
    return
  }

  eval "${output}"
  local actual="${!field_name}"
  if [[ "${actual}" != "${expected_value}" ]]; then
    echo "FAIL [${test_name}]: ${field_name}=${actual}(expected ${expected_value})"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  fi
}

echo "=== mcp-adapter-policy.sh unit tests ==="
echo ""

assert_field "rest-bridge-route" "route" "rest-bridge" \
  --adapter supabase-rest-mcp --execution-engine subscription --session-provider none
assert_field "rest-bridge-available" "available" "true" \
  --adapter stripe-rest-mcp --execution-engine api --session-provider none
assert_field "pencil-kernel-route" "route" "kernel-adapter" \
  --adapter pencil-session-mcp --execution-engine subscription --session-provider none
assert_field "vercel-kernel-disabled" "route" "unavailable" \
  --adapter vercel-session-mcp --execution-engine local --session-provider none
assert_field "slack-session-fallback" "route" "claude-session" \
  --adapter slack-session-mcp --execution-engine local --session-provider claude
assert_field "session-only-available-flag" "available" "true" \
  --adapter excalidraw-session-mcp --execution-engine local --session-provider claude

total=$((total + 1))
vercel_enabled_output="$(env KERNEL_VERCEL_ADAPTER_ENABLED=true "${POLICY}" --adapter vercel-session-mcp --execution-engine local --session-provider none)" || {
  echo "FAIL [vercel-kernel-enabled]: script exited with error"
  failed=$((failed + 1))
  vercel_enabled_output=""
}
if [[ -n "${vercel_enabled_output}" ]]; then
  eval "${vercel_enabled_output}"
  if [[ "${route}" != "kernel-adapter" ]]; then
    echo "FAIL [vercel-kernel-enabled]: route=${route}(expected kernel-adapter)"
    failed=$((failed + 1))
  else
    echo "PASS [vercel-kernel-enabled]"
    passed=$((passed + 1))
  fi
fi

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
