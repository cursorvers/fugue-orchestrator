#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/config/integrations/mcp-adapters.json"
POLICY="${ROOT_DIR}/scripts/lib/mcp-adapter-policy.sh"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

pass() {
  echo "[PASS] $*"
}

command -v jq >/dev/null 2>&1 || fail "missing command: jq"
[[ -f "${MANIFEST}" ]] || fail "manifest not found: ${MANIFEST}"
[[ -x "${POLICY}" ]] || fail "policy script not executable: ${POLICY}"

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

jq -e '.adapters | type == "array" and length >= 2' "${MANIFEST}" >/dev/null || fail "manifest must contain adapter array with entries"
pass "adapter count valid"

dups="$(jq -r '.adapters | group_by(.id)[] | select(length > 1) | .[0].id' "${MANIFEST}")"
[[ -z "${dups}" ]] || fail "duplicate adapter IDs: ${dups}"
pass "adapter IDs unique"

invalid="$(jq -r '
  .adapters[]
  | select(
      (.access_mode | IN("rest-bridge","kernel-adapter","skill-cli","claude-session") | not)
      or (.runtime_availability | IN("hybrid","adapter-backed","cli-backed","session-only") | not)
      or (.control_plane | IN("kernel","claude") | not)
      or (.kernel_compatible | type != "boolean")
      or (.fallback_route | IN("none","manual","claude-session") | not)
    )
  | .id
' "${MANIFEST}")"
[[ -z "${invalid}" ]] || fail "invalid MCP adapter enum values: ${invalid}"
pass "adapter enums valid"

while IFS= read -r row; do
  id="$(echo "${row}" | jq -r '.id')"
  path_value="$(echo "${row}" | jq -r '.path')"
  if [[ "${path_value}" == /* ]]; then
    resolved_path="${path_value}"
  else
    resolved_path="${ROOT_DIR}/${path_value}"
  fi
  [[ -e "${resolved_path}" ]] || fail "adapter=${id} path missing: ${path_value}"
done < <(jq -c '.adapters[]' "${MANIFEST}")
pass "adapter paths exist"

supabase_route="$("${POLICY}" --adapter supabase-rest-mcp --execution-engine subscription --session-provider none --format json)"
[[ "$(echo "${supabase_route}" | jq -r '.route')" == "rest-bridge" ]] || fail "supabase-rest-mcp should resolve to rest-bridge"
[[ "$(echo "${supabase_route}" | jq -r '.available')" == "true" ]] || fail "supabase-rest-mcp should be available"
pass "rest bridge route valid"

pencil_route="$(KERNEL_PENCIL_WRAPPER="${fake_pencil}" "${POLICY}" --adapter pencil-session-mcp --execution-engine subscription --session-provider none --format json)"
[[ "$(echo "${pencil_route}" | jq -r '.route')" == "kernel-adapter" ]] || fail "pencil-session-mcp should resolve to kernel-adapter"
[[ "$(echo "${pencil_route}" | jq -r '.available')" == "true" ]] || fail "pencil-session-mcp should be available via kernel adapter"
pass "pencil kernel adapter opens without claude session"

excalidraw_route="$(KERNEL_EXCALIDRAW_HEALTHCHECK_SCRIPT="${fake_excalidraw_dir}/healthcheck.cjs" "${POLICY}" --adapter excalidraw-session-mcp --execution-engine local --session-provider none --format json)"
[[ "$(echo "${excalidraw_route}" | jq -r '.route')" == "kernel-adapter" ]] || fail "excalidraw-session-mcp should resolve to kernel-adapter"
[[ "$(echo "${excalidraw_route}" | jq -r '.available')" == "true" ]] || fail "excalidraw-session-mcp should be available via kernel adapter"
pass "excalidraw kernel adapter opens without claude session"

slack_route="$(env -u SLACK_WEBHOOK_URL -u SLACK_BOT_TOKEN KERNEL_SLACK_SKILL_ENABLED=false "${POLICY}" --adapter slack-session-mcp --execution-engine local --session-provider claude --format json)"
[[ "$(echo "${slack_route}" | jq -r '.route')" == "claude-session" ]] || fail "slack-session-mcp should fall back to claude-session when session is active"
[[ "$(echo "${slack_route}" | jq -r '.available')" == "true" ]] || fail "slack-session-mcp should be available with Claude session"
pass "slack session fallback preserved"

slack_skill_route="$(SLACK_WEBHOOK_URL="https://hooks.slack.test/services/demo" "${POLICY}" --adapter slack-session-mcp --execution-engine local --session-provider none --format json)"
[[ "$(echo "${slack_skill_route}" | jq -r '.route')" == "skill-cli" ]] || fail "slack-session-mcp should resolve to skill-cli when webhook is present"
[[ "$(echo "${slack_skill_route}" | jq -r '.available')" == "true" ]] || fail "slack-session-mcp skill-cli route should be available when webhook is present"
pass "slack skill-cli route works"

vercel_route="$(VERCEL_TOKEN="demo-token" "${POLICY}" --adapter vercel-session-mcp --execution-engine local --session-provider none --format json)"
[[ "$(echo "${vercel_route}" | jq -r '.route')" == "skill-cli" ]] || fail "vercel-session-mcp should resolve to skill-cli when token is present"
[[ "$(echo "${vercel_route}" | jq -r '.available')" == "true" ]] || fail "vercel-session-mcp skill-cli route should be available when token is present"
pass "vercel skill-cli route works"

echo "mcp adapter contract check passed"
