#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBSCRIPTION_RUNNER="${ROOT_DIR}/scripts/harness/subscription-agent-runner.sh"
CI_RUNNER="${ROOT_DIR}/scripts/harness/ci-agent-runner.sh"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agent-runner-compat.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT
BASE_TEST_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

passed=0
failed=0
total=0

make_fake_claude() {
  cat > "${TMP_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  cat <<'HELP'
Usage: claude [options]
  --dangerously-skip-permissions
  --print
HELP
  exit 0
fi
args="$*"
if [[ "${args}" == *"--permission-mode"* ]]; then
  echo "unexpected legacy permission flag" >&2
  exit 91
fi
if [[ "${args}" != *"--dangerously-skip-permissions"* ]]; then
  echo "missing supported permission flag" >&2
  exit 92
fi
if [[ "${args}" != *"--model claude-sonnet-4-6"* ]]; then
  echo "wrong model" >&2
  exit 93
fi
printf '%s\n' '{"result":"{\"risk\":\"LOW\",\"approve\":true,\"findings\":[],\"recommendation\":\"ok\",\"rationale\":\"cli-compatible\"}","session_id":"sess-123"}'
EOF
  chmod +x "${TMP_DIR}/claude"
}

make_fake_copilot() {
  cat > "${TMP_DIR}/copilot" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' 'copilot help'
  exit 0
fi
args="$*"
if [[ "${REQUIRE_NO_ALLOW_ALL_TOOLS:-false}" == "true" && "${args}" == *"--allow-all-tools"* ]]; then
  echo "unexpected allow-all-tools" >&2
  exit 94
fi
if [[ "${REQUIRE_ALLOW_ALL_TOOLS:-false}" == "true" && "${args}" != *"--allow-all-tools"* ]]; then
  echo "missing allow-all-tools" >&2
  exit 95
fi
printf '%s\n' '{"risk":"LOW","approve":true,"findings":[],"recommendation":"ok","rationale":"copilot-compatible"}'
EOF
  chmod +x "${TMP_DIR}/copilot"
}

make_fake_curl() {
  cat > "${TMP_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output_file=""
data=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output_file="$2"
      shift 2
      ;;
    -d)
      data="$2"
      shift 2
      ;;
    http*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

model="$(printf '%s' "${data}" | jq -r '.model // empty' 2>/dev/null || true)"

if [[ "${url}" == "https://api.z.ai/api/coding/paas/v4/chat/completions" ]]; then
  if [[ "${model}" == "glm-4.7" || "${model}" == "glm-4.6" ]]; then
    printf '%s\n' '{"error":{"message":"Unknown Model"}}' > "${output_file}"
    printf '400'
    exit 0
  fi
  if [[ "${model}" == "glm-4.5" ]]; then
    printf '%s\n' '{"choices":[{"message":{"content":"{\"risk\":\"LOW\",\"approve\":true,\"findings\":[],\"recommendation\":\"ok\",\"rationale\":\"glm fallback\"}"}}]}' > "${output_file}"
    printf '200'
    exit 0
  fi
fi

if [[ "${url}" == "https://api.anthropic.com/v1/messages" ]]; then
  if [[ "${model}" == "claude-sonnet-4-0" ]]; then
    printf '%s\n' '{"content":[{"type":"text","text":"{\"risk\":\"LOW\",\"approve\":true,\"findings\":[],\"recommendation\":\"ok\",\"rationale\":\"api-compatible\"}"}]}' > "${output_file}"
    printf '200'
    exit 0
  fi
  printf '%s\n' '{"error":{"message":"invalid model"}}' > "${output_file}"
  printf '400'
  exit 0
fi

printf '%s\n' '{"error":{"message":"unexpected request"}}' > "${output_file}"
printf '500'
EOF
  chmod +x "${TMP_DIR}/curl"
}

assert_json_field() {
  local file="$1"
  local jq_filter="$2"
  local expected="$3"
  local actual
  actual="$(jq -r "${jq_filter}" "${file}")"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "expected ${jq_filter}=${expected}, got ${actual}" >&2
    return 1
  fi
}

run_test() {
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

test_subscription_claude_cli_flag() {
  make_fake_claude
  local work_dir="${TMP_DIR}/subscription-claude"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      PROVIDER="claude" \
      MODEL="claude-sonnet-4-6" \
      AGENT_NAME="claude-opus-assist" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-claude-opus-assist.json"
  assert_json_field "${result}" '.http_code' 'cli:0'
  assert_json_field "${result}" '.model' 'claude-sonnet-4-6'
  assert_json_field "${result}" '.skipped' 'false'
}

test_subscription_glm_fallback() {
  make_fake_curl
  local work_dir="${TMP_DIR}/subscription-glm"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      PROVIDER="glm" \
      MODEL="" \
      ZAI_API_KEY="dummy" \
      AGENT_NAME="glm-code-reviewer" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-glm-code-reviewer.json"
  assert_json_field "${result}" '.model' 'glm-4.5'
  assert_json_field "${result}" '.http_code' '200'
  assert_json_field "${result}" '.skipped' 'false'
  jq -e '.model_attempts | contains("glm:glm-4.7:exit0-http400") and contains("glm:glm-4.5:ok")' "${result}" >/dev/null
}

test_ci_claude_api_model() {
  make_fake_curl
  local work_dir="${TMP_DIR}/ci-claude"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      PROVIDER="claude" \
      MODEL="claude-sonnet-4-6" \
      API_URL="https://api.anthropic.com/v1/messages" \
      ANTHROPIC_API_KEY="dummy" \
      AGENT_NAME="claude-main-orchestrator" \
      AGENT_ROLE="orchestrator" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${CI_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-claude-main-orchestrator.json"
  assert_json_field "${result}" '.model' 'claude-sonnet-4-0'
  assert_json_field "${result}" '.http_code' '200'
  assert_json_field "${result}" '.skipped' 'false'
}

test_ci_claude_copilot_mode() {
  make_fake_copilot
  local work_dir="${TMP_DIR}/ci-copilot"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      COPILOT_CLI_BIN="${TMP_DIR}/copilot" \
      HAS_COPILOT_CLI="true" \
      REQUIRE_NO_ALLOW_ALL_TOOLS="true" \
      PROVIDER="claude" \
      MODEL="claude-sonnet-4-0" \
      API_URL="https://api.anthropic.com/v1/messages" \
      AGENT_NAME="claude-main-orchestrator" \
      AGENT_ROLE="orchestrator" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${CI_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-claude-main-orchestrator.json"
  assert_json_field "${result}" '.http_code' 'cli:0'
  assert_json_field "${result}" '.execution_route' 'claude-via-copilot-cli'
  assert_json_field "${result}" '.skipped' 'false'
}

test_ci_claude_copilot_mode_allow_tools_opt_in() {
  make_fake_copilot
  local work_dir="${TMP_DIR}/ci-copilot-allow-tools"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      COPILOT_CLI_BIN="${TMP_DIR}/copilot" \
      HAS_COPILOT_CLI="true" \
      COPILOT_ALLOW_ALL_TOOLS="true" \
      REQUIRE_ALLOW_ALL_TOOLS="true" \
      PROVIDER="claude" \
      MODEL="claude-sonnet-4-0" \
      API_URL="https://api.anthropic.com/v1/messages" \
      AGENT_NAME="claude-main-orchestrator" \
      AGENT_ROLE="orchestrator" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${CI_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-claude-main-orchestrator.json"
  assert_json_field "${result}" '.http_code' 'cli:0'
  assert_json_field "${result}" '.execution_route' 'claude-via-copilot-cli'
  assert_json_field "${result}" '.skipped' 'false'
}

test_ci_claude_opus_strict_rejects_copilot() {
  make_fake_copilot
  local work_dir="${TMP_DIR}/ci-copilot-strict"
  mkdir -p "${work_dir}"
  if (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      COPILOT_CLI_BIN="${TMP_DIR}/copilot" \
      HAS_COPILOT_CLI="true" \
      PROVIDER="claude" \
      MODEL="claude-sonnet-4-0" \
      API_URL="https://api.anthropic.com/v1/messages" \
      AGENT_NAME="claude-opus-assist" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="true" \
      bash "${CI_RUNNER}" >/dev/null
  ); then
    echo "expected strict opus guard to reject copilot route" >&2
    return 1
  fi
}

echo "=== agent runner provider compatibility tests ==="
echo ""

run_test "subscription-claude-cli-flag" test_subscription_claude_cli_flag
run_test "subscription-glm-fallback" test_subscription_glm_fallback
run_test "ci-claude-api-model" test_ci_claude_api_model
run_test "ci-claude-copilot-mode" test_ci_claude_copilot_mode
run_test "ci-claude-copilot-allow-tools-opt-in" test_ci_claude_copilot_mode_allow_tools_opt_in
run_test "ci-claude-opus-strict-rejects-copilot" test_ci_claude_opus_strict_rejects_copilot

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
