#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="${SCRIPT_DIR}/scripts/lib/mcp-adapter-policy.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fake_pencil="${tmp_dir}/pencil-wrapper.sh"
cat > "${fake_pencil}" <<'EOF'
#!/usr/bin/env bash
echo "fake pencil wrapper"
EOF
chmod +x "${fake_pencil}"

fake_excalidraw_dir="${tmp_dir}/excalidraw"
mkdir -p "${fake_excalidraw_dir}"
cat > "${fake_excalidraw_dir}/healthcheck.cjs" <<'EOF'
#!/usr/bin/env node
console.log('{"status":"ok"}');
EOF
chmod +x "${fake_excalidraw_dir}/healthcheck.cjs"

assert_field() {
  local test_name="$1"
  local field_name="$2"
  local expected_value="$3"
  shift 3

  total=$((total + 1))
  local output
  output="$("$@")" || {
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
  "${POLICY}" --adapter supabase-rest-mcp --execution-engine subscription --session-provider none
assert_field "rest-bridge-available" "available" "true" \
  "${POLICY}" --adapter stripe-rest-mcp --execution-engine api --session-provider none
assert_field "pencil-kernel-route" "route" "kernel-adapter" \
  env KERNEL_PENCIL_WRAPPER="${fake_pencil}" "${POLICY}" \
  --adapter pencil-session-mcp --execution-engine subscription --session-provider none
assert_field "vercel-kernel-disabled" "route" "unavailable" \
  "${POLICY}" --adapter vercel-session-mcp --execution-engine local --session-provider none
assert_field "slack-session-fallback" "route" "claude-session" \
  "${POLICY}" --adapter slack-session-mcp --execution-engine local --session-provider claude
assert_field "session-only-available-flag" "available" "true" \
  env KERNEL_EXCALIDRAW_HEALTHCHECK_SCRIPT="${fake_excalidraw_dir}/healthcheck.cjs" "${POLICY}" \
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
