#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/harness/notebooklm-preflight-enrich.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fake_adapter="${tmp_dir}/notebooklm-cli-adapter.sh"
cat > "${fake_adapter}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

action=""
run_dir=""
source_manifest=""
resolve_only="false"

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --action)
      action="${2:-}"
      shift 2
      ;;
    --run-dir)
      run_dir="${2:-}"
      shift 2
      ;;
    --source-manifest)
      source_manifest="${2:-}"
      shift 2
      ;;
    --resolve-only)
      resolve_only="true"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ "${action}" == "smoke" ]]; then
  echo "notebooklm-cli adapter ready"
  exit 0
fi

mkdir -p "${run_dir}/notebooklm"
if [[ -n "${FAKE_NOTEBOOKLM_ADAPTER_LOG:-}" ]]; then
  printf 'action=%s resolve_only=%s source_manifest=%s\n' "${action}" "${resolve_only}" "${source_manifest}" >> "${FAKE_NOTEBOOKLM_ADAPTER_LOG}"
fi

printf '%s\n' "notebook create Demo --json" > "${run_dir}/notebooklm/${action}.commands.txt"
printf '%s\n' "source add NOTEBOOK_ID --file ${source_manifest} --wait --json" >> "${run_dir}/notebooklm/${action}.commands.txt"

if [[ "${resolve_only}" == "true" ]]; then
  printf '%s' '{"status":"resolved","message":"resolved commands"}' > "${run_dir}/notebooklm/${action}-meta.json"
  cat "${run_dir}/notebooklm/${action}.commands.txt"
  exit 0
fi

artifact_id="art_visual"
artifact_type="mind_map"
if [[ "${action}" == "slide-prep" ]]; then
  artifact_id="art_slide"
  artifact_type="slide_deck"
fi
printf '%s' "{\"status\":\"ok\",\"message\":\"artifact created\"}" > "${run_dir}/notebooklm/${action}-meta.json"
printf '%s' "{\"schema_version\":\"1.0.0\",\"action_intent\":\"${action}\",\"notebook_id\":\"nb_demo\",\"artifact_id\":\"${artifact_id}\",\"artifact_type\":\"${artifact_type}\",\"raw_output_path\":\"${run_dir}/notebooklm/${action}.json\",\"is_truncated\":false,\"sensitivity\":\"internal\",\"ttl_expires_at\":\"2026-03-14T00:00:00Z\"}" > "${run_dir}/notebooklm/receipt.json"
cat "${run_dir}/notebooklm/receipt.json"
EOF
chmod +x "${fake_adapter}"

fake_bin_dir="${tmp_dir}/bin"
mkdir -p "${fake_bin_dir}"
fake_nlm="${fake_bin_dir}/nlm"
cat > "${fake_nlm}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo "nlm help"
  exit 0
fi
exit 0
EOF
chmod +x "${fake_nlm}"

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

test_skips_without_notebooklm_action() {
  local work_dir="${tmp_dir}/skip"
  local output_file="${work_dir}/github-output.txt"
  mkdir -p "${work_dir}"

  env \
    ISSUE_NUMBER="601" \
    ISSUE_TITLE="skip" \
    ISSUE_BODY="normal issue" \
    CONTENT_HINT_APPLIED="true" \
    CONTENT_ACTION_HINT="slide-deck" \
    CONTENT_SKILL_HINT="slide" \
    CONTENT_REASON="generic-slide" \
    OUT_DIR="${work_dir}" \
    RUN_DIR="${work_dir}/run" \
    REPORT_PATH="${work_dir}/report.md" \
    GITHUB_OUTPUT="${output_file}" \
    ADAPTER="${fake_adapter}" \
    bash "${SCRIPT}" >/dev/null

  grep -q '^notebooklm_preflight_status=skipped$' "${output_file}" &&
    grep -q 'No NotebookLM content action was suggested\.' "${work_dir}/report.md"
}

test_resolves_contract_only_when_runtime_disabled() {
  local work_dir="${tmp_dir}/resolve"
  local output_file="${work_dir}/github-output.txt"
  local adapter_log="${work_dir}/adapter.log"
  mkdir -p "${work_dir}"
  printf '# research\n' > "${work_dir}/research.md"
  printf '# plan\n' > "${work_dir}/plan.md"

  env \
    ISSUE_NUMBER="602" \
    ISSUE_TITLE="NotebookLM visual" \
    ISSUE_BODY="調査結果を図式化したい" \
    CONTENT_HINT_APPLIED="true" \
    CONTENT_ACTION_HINT="notebooklm-visual-brief" \
    CONTENT_SKILL_HINT="notebooklm-visual-brief" \
    CONTENT_REASON="notebooklm-visual-request" \
    OUT_DIR="${work_dir}" \
    RUN_DIR="${work_dir}/run" \
    REPORT_PATH="${work_dir}/report.md" \
    GITHUB_OUTPUT="${output_file}" \
    RESEARCH_REPORT_PATH="${work_dir}/research.md" \
    PLAN_REPORT_PATH="${work_dir}/plan.md" \
    ADAPTER="${fake_adapter}" \
    FAKE_NOTEBOOKLM_ADAPTER_LOG="${adapter_log}" \
    bash "${SCRIPT}" >/dev/null

  grep -q '^notebooklm_preflight_status=planned$' "${output_file}" &&
    grep -q 'NotebookLM commands resolved without live execution\.' "${work_dir}/report.md" &&
    grep -q 'action=visual-brief resolve_only=true' "${adapter_log}" &&
    jq -e '.sources | length == 3' "${work_dir}/run/source-manifest.json" >/dev/null
}

test_executes_when_runtime_available() {
  local work_dir="${tmp_dir}/exec"
  local output_file="${work_dir}/github-output.txt"
  local adapter_log="${work_dir}/adapter.log"
  mkdir -p "${work_dir}"
  printf '# critic\n' > "${work_dir}/critic.md"

  env \
    PATH="${fake_bin_dir}:${PATH}" \
    ISSUE_NUMBER="603" \
    ISSUE_TITLE="NotebookLM slide prep" \
    ISSUE_BODY="営業向けスライド下書きを作る" \
    CONTENT_HINT_APPLIED="true" \
    CONTENT_ACTION_HINT="notebooklm-slide-prep" \
    CONTENT_SKILL_HINT="notebooklm-slide-prep" \
    CONTENT_REASON="notebooklm-slide-prep-request" \
    OUT_DIR="${work_dir}" \
    RUN_DIR="${work_dir}/run" \
    REPORT_PATH="${work_dir}/report.md" \
    GITHUB_OUTPUT="${output_file}" \
    CRITIC_REPORT_PATH="${work_dir}/critic.md" \
    ADAPTER="${fake_adapter}" \
    FAKE_NOTEBOOKLM_ADAPTER_LOG="${adapter_log}" \
    NOTEBOOKLM_RUNTIME_ENABLED="true" \
    NOTEBOOKLM_HUMAN_APPROVED="true" \
    NLM_BIN="${fake_nlm}" \
    bash "${SCRIPT}" >/dev/null

  grep -q '^notebooklm_preflight_status=verified$' "${output_file}" &&
    grep -q 'artifact_type=slide_deck, artifact_id=art_slide, notebook_id=nb_demo' "${work_dir}/report.md" &&
    grep -q 'action=slide-prep resolve_only=false' "${adapter_log}" &&
    jq -e '.artifact_type == "slide_deck"' "${work_dir}/run/notebooklm/receipt.json" >/dev/null
}

test_blocks_when_runtime_required_but_unavailable() {
  local work_dir="${tmp_dir}/blocked"
  local output_file="${work_dir}/github-output.txt"
  mkdir -p "${work_dir}"

  if env \
    ISSUE_NUMBER="604" \
    ISSUE_TITLE="NotebookLM blocked" \
    ISSUE_BODY="runtime 必須" \
    CONTENT_HINT_APPLIED="true" \
    CONTENT_ACTION_HINT="notebooklm-visual-brief" \
    CONTENT_SKILL_HINT="notebooklm-visual-brief" \
    CONTENT_REASON="notebooklm-visual-request" \
    OUT_DIR="${work_dir}" \
    RUN_DIR="${work_dir}/run" \
    REPORT_PATH="${work_dir}/report.md" \
    GITHUB_OUTPUT="${output_file}" \
    ADAPTER="${fake_adapter}" \
    NOTEBOOKLM_RUNTIME_ENABLED="false" \
    NOTEBOOKLM_REQUIRE_RUNTIME_AUTH="true" \
    bash "${SCRIPT}" >/dev/null 2>&1; then
    return 1
  fi

  grep -q '^notebooklm_preflight_status=blocked$' "${output_file}" &&
    grep -q 'NotebookLM runtime execution is required but unavailable\.' "${work_dir}/report.md"
}

echo "=== notebooklm-preflight-enrich.sh unit tests ==="
echo ""

assert_ok "skips-without-notebooklm-action" test_skips_without_notebooklm_action
assert_ok "resolves-contract-only-when-runtime-disabled" test_resolves_contract_only_when_runtime_disabled
assert_ok "executes-when-runtime-available" test_executes_when_runtime_available
assert_ok "blocks-when-runtime-required-but-unavailable" test_blocks_when_runtime_required_but_unavailable

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
