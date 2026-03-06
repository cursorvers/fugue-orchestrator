#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXEC="${ROOT_DIR}/scripts/lib/mcp-adapter-exec.sh"

passed=0
failed=0
total=0

assert_json_field() {
  local test_name="$1"
  local jq_expr="$2"
  local expected="$3"
  shift 3

  total=$((total + 1))
  local output
  if ! output="$("$@")"; then
    echo "FAIL [${test_name}]: command failed"
    failed=$((failed + 1))
    return
  fi

  local actual
  actual="$(echo "${output}" | jq -r "${jq_expr}")"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL [${test_name}]: ${actual}(expected ${expected})"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  fi
}

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
cat > "${fake_excalidraw_dir}/export-elements.cjs" <<'EOF'
#!/usr/bin/env node
const fs = require("node:fs");
const out = process.argv[process.argv.indexOf("--out") + 1];
fs.writeFileSync(out, '{"elements":[]}');
console.log(`Wrote 0 elements to ${out}`);
EOF
cat > "${fake_excalidraw_dir}/import-elements.cjs" <<'EOF'
#!/usr/bin/env node
console.log("Imported 0 elements (batch)");
EOF
cat > "${fake_excalidraw_dir}/clear-canvas.cjs" <<'EOF'
#!/usr/bin/env node
console.log("Cleared canvas");
EOF
chmod +x "${fake_excalidraw_dir}"/*.cjs

echo "=== mcp-adapter-exec.sh unit tests ==="
echo ""

assert_json_field "resolve-pencil-route" ".status" "ok" \
  env KERNEL_PENCIL_WRAPPER="${fake_pencil}" \
  "${EXEC}" --adapter pencil-session-mcp --action resolve

assert_json_field "pencil-server-command" ".message" "pencil command resolved" \
  env KERNEL_PENCIL_WRAPPER="${fake_pencil}" \
  "${EXEC}" --adapter pencil-session-mcp --action server-command

assert_json_field "pencil-smoke-dry-run" ".message" "pencil dry-run" \
  env KERNEL_PENCIL_WRAPPER="${fake_pencil}" \
  "${EXEC}" --adapter pencil-session-mcp --action smoke --dry-run

export_out="${tmp_dir}/elements.json"
assert_json_field "excalidraw-export" ".message" "excalidraw export completed" \
  env KERNEL_EXCALIDRAW_HEALTHCHECK_SCRIPT="${fake_excalidraw_dir}/healthcheck.cjs" \
  EXCALIDRAW_SERVER_URL="http://example.test" \
  "${EXEC}" --adapter excalidraw-session-mcp --action export --out "${export_out}"

assert_json_field "excalidraw-import-dry-run" ".details.mode" "sync" \
  env KERNEL_EXCALIDRAW_HEALTHCHECK_SCRIPT="${fake_excalidraw_dir}/healthcheck.cjs" \
  EXCALIDRAW_SERVER_URL="http://example.test" \
  "${EXEC}" --adapter excalidraw-session-mcp --action import --in "${export_out}" --mode sync --dry-run

assert_json_field "slack-fallback" ".status" "fallback" \
  env -u SLACK_WEBHOOK_URL -u SLACK_BOT_TOKEN \
  "${EXEC}" --adapter slack-session-mcp --action notify --session-provider claude

assert_json_field "slack-dry-run" ".message" "slack notify dry-run" \
  env SLACK_WEBHOOK_URL="https://hooks.slack.test/services/demo" \
  "${EXEC}" --adapter slack-session-mcp --action notify --text "hello" --dry-run

assert_json_field "vercel-list-projects-dry-run" ".message" "vercel list-projects dry-run" \
  env KERNEL_VERCEL_ADAPTER_ENABLED=true VERCEL_TOKEN="demo-token" \
  "${EXEC}" --adapter vercel-session-mcp --action list-projects --dry-run

assert_json_field "rest-bridge-dry-run" ".message" "rest bridge dry-run" \
  "${EXEC}" --adapter supabase-rest-mcp --action smoke --dry-run

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
