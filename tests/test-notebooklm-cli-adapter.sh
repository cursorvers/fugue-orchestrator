#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/lib/notebooklm-cli-adapter.sh"

passed=0
failed=0
total=0

TMP_ROOT="/Users/masayuki/Dev/tmp"
mkdir -p "${TMP_ROOT}"
tmp_dir="$(mktemp -d "${TMP_ROOT%/}/notebooklm-cli-adapter.XXXXXX")"
trap 'rm -rf "${tmp_dir}"' EXIT

fake_bin_dir="${tmp_dir}/bin"
mkdir -p "${fake_bin_dir}"
fake_nlm="${fake_bin_dir}/nlm"
fake_log="${tmp_dir}/nlm-calls.log"
cat > "${fake_nlm}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FAKE_NLM_CALLS_LOG}"

if [[ "${1:-}" == "--help" ]]; then
  echo "nlm help"
  exit 0
fi

case "$*" in
  "create Demo")
    printf '✓ Created notebook: Demo\n  ID: nb_demo\n'
    ;;
  "add nb_demo https://example.com/article")
    printf '✓ Added source: Example Source (ready)\nSource ID: src_url\n'
    ;;
  add\ nb_demo\ /*)
    printf '✓ Added source: File Source (ready)\nSource ID: src_file\n'
    ;;
  "mindmap nb_demo src_url src_file")
    printf '✓ Mind map created\n  ID: art_mindmap\n  Title: Demo\n'
    ;;
  "briefing-doc nb_demo src_url src_file")
    printf '✓ Briefing doc created\n  Artifact ID: art_report\n'
    ;;
  *)
    echo "unexpected command: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${fake_nlm}"

manifest="${tmp_dir}/sources.json"
sample_file="${tmp_dir}/sample.txt"
printf 'notes' > "${sample_file}"
cat > "${manifest}" <<EOF
{
  "sources": [
    { "type": "url", "value": "https://example.com/article", "wait": true },
    { "type": "file", "value": "${sample_file}", "wait": true }
  ]
}
EOF

assert_ok() {
  local test_name="$1"
  shift
  total=$((total + 1))
  if "$@"; then
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  else
    echo "FAIL [${test_name}]"
    failed=$((failed + 1))
  fi
}

test_resolve_only_visual_brief() {
  local output
  output="$(
    FAKE_NLM_CALLS_LOG="${fake_log}" \
    NLM_BIN="${fake_nlm}" \
    bash "${SCRIPT}" \
      --action visual-brief \
      --title Demo \
      --source-manifest "${manifest}" \
      --ok-to-execute true \
      --human-approved true \
      --resolve-only
  )"

  grep -q '^nlm create Demo$' <<< "${output}" &&
    grep -q 'add NOTEBOOK_ID https://example.com/article' <<< "${output}" &&
    grep -q 'add NOTEBOOK_ID '"${sample_file}" <<< "${output}" &&
    grep -q 'mindmap NOTEBOOK_ID SOURCE_ID_1 SOURCE_ID_2' <<< "${output}" &&
    [[ ! -s "${fake_log}" ]]
}

test_blocks_without_approval() {
  local run_dir="${tmp_dir}/blocked-run"
  if FAKE_NLM_CALLS_LOG="${fake_log}" NLM_BIN="${fake_nlm}" bash "${SCRIPT}" \
      --action visual-brief \
      --title Demo \
      --source-manifest "${manifest}" \
      --run-dir "${run_dir}" >/dev/null 2>"${tmp_dir}/blocked.err"; then
    return 1
  fi

  grep -q 'approval gate' "${tmp_dir}/blocked.err" &&
    jq -e '.status == "skipped"' "${run_dir}/notebooklm/visual-brief-meta.json" >/dev/null &&
    [[ ! -f "${run_dir}/notebooklm/receipt.json" ]]
}

test_exec_visual_brief_writes_receipt() {
  local run_dir="${tmp_dir}/exec-run"
  local output
  : > "${fake_log}"
  output="$(
    FAKE_NLM_CALLS_LOG="${fake_log}" \
    NLM_BIN="${fake_nlm}" \
    bash "${SCRIPT}" \
      --action visual-brief \
      --title Demo \
      --source-manifest "${manifest}" \
      --run-dir "${run_dir}" \
      --ok-to-execute true \
      --human-approved true
  )"

  jq -e '.action_intent == "visual-brief"' <<< "${output}" >/dev/null &&
    jq -e '.notebook_id == "nb_demo"' <<< "${output}" >/dev/null &&
  jq -e '.artifact_id == "art_mindmap"' <<< "${output}" >/dev/null &&
    jq -e '.artifact_type == "mind_map"' "${run_dir}/notebooklm/receipt.json" >/dev/null &&
    jq -e '.status == "ok"' "${run_dir}/notebooklm/visual-brief-meta.json" >/dev/null &&
    grep -q '^nlm create Demo$' "${run_dir}/notebooklm/visual-brief.commands.txt" &&
    grep -q '^create Demo$' "${fake_log}" &&
    grep -q '^add nb_demo https://example.com/article$' "${fake_log}" &&
    grep -q '^add nb_demo '"${sample_file}"'$' "${fake_log}" &&
    grep -q '^mindmap nb_demo src_url src_file$' "${fake_log}"
}

test_smoke() {
  local output
  output="$(
    FAKE_NLM_CALLS_LOG="${fake_log}" \
    NLM_BIN="${fake_nlm}" \
    bash "${SCRIPT}" --action smoke
  )"
  [[ "${output}" == "notebooklm-cli adapter ready" ]]
}

echo "=== notebooklm-cli-adapter.sh unit tests ==="
echo ""

assert_ok "resolve-only-visual-brief" test_resolve_only_visual_brief
assert_ok "blocks-without-approval" test_blocks_without_approval
assert_ok "exec-visual-brief-writes-receipt" test_exec_visual_brief_writes_receipt
assert_ok "smoke" test_smoke

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
