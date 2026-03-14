#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBSCRIPTION_RUNNER="${ROOT_DIR}/scripts/harness/subscription-agent-runner.sh"
CI_RUNNER="${ROOT_DIR}/scripts/harness/ci-agent-runner.sh"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agent-runner-compat.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT
BASE_TEST_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
CLAUDE_TEST_MODEL="claude-opus-4-6"

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
if [[ "${args}" != *"--model ${EXPECTED_CLAUDE_MODEL:-claude-opus-4-6}"* ]]; then
  echo "wrong model" >&2
  exit 93
fi
printf '%s\n' '{"result":"{\"risk\":\"LOW\",\"approve\":true,\"findings\":[],\"recommendation\":\"ok\",\"rationale\":\"cli-compatible\"}","session_id":"sess-123"}'
EOF
  chmod +x "${TMP_DIR}/claude"
}

make_noisy_claude() {
  cat > "${TMP_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then
  echo "claude($$) MallocStackLogging: can't turn off malloc stack logging because it was not enabled." >&2
  cat <<'HELP'
Usage: claude [options]
  --dangerously-skip-permissions
  --print
HELP
  exit 0
fi
echo "claude($$) MallocStackLogging: can't turn off malloc stack logging because it was not enabled." >&2
printf '%s\n' '{"result":"{\"risk\":\"LOW\",\"approve\":true,\"findings\":[],\"recommendation\":\"ok\",\"rationale\":\"noise-filtered\"}","session_id":"sess-noise"}'
EOF
  chmod +x "${TMP_DIR}/claude"
}

make_failing_claude() {
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
echo "forced claude failure" >&2
exit 99
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
if [[ "${REQUIRE_GH_TOKEN:-false}" == "true" && -z "${GH_TOKEN:-}" ]]; then
  echo "missing gh token" >&2
  exit 96
fi
printf '%s\n' '{"risk":"LOW","approve":true,"findings":[],"recommendation":"ok","rationale":"copilot-compatible"}'
EOF
  chmod +x "${TMP_DIR}/copilot"
}

make_fake_npx() {
  cat > "${TMP_DIR}/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
if [[ "${args}" != *"@github/copilot"* ]]; then
  echo "missing copilot package" >&2
  exit 97
fi
if [[ "${REQUIRE_GH_TOKEN:-false}" == "true" && -z "${GH_TOKEN:-}" ]]; then
  echo "missing gh token" >&2
  exit 98
fi
if [[ "${REQUIRE_ALLOW_ALL_TOOLS:-false}" == "true" && "${args}" != *"--allow-all-tools"* ]]; then
  echo "missing allow-all-tools" >&2
  exit 99
fi
printf '%s\n' '{"risk":"LOW","approve":true,"findings":[],"recommendation":"ok","rationale":"copilot-via-npx"}'
EOF
  chmod +x "${TMP_DIR}/npx"
}

make_fake_gh() {
  cat > "${TMP_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "auth" && "${2:-}" == "token" ]]; then
  printf '%s\n' "${FAKE_GH_TOKEN:-gho_fake_from_gh}"
  exit 0
fi
echo "unexpected gh invocation" >&2
exit 101
EOF
  chmod +x "${TMP_DIR}/gh"
}

make_failing_gh() {
  cat > "${TMP_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "gh auth unavailable" >&2
exit 102
EOF
  chmod +x "${TMP_DIR}/gh"
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
  if [[ "${model}" == "glm-5" ]]; then
    printf '%s\n' '{"choices":[{"message":{"content":"{\"risk\":\"LOW\",\"approve\":true,\"findings\":[],\"recommendation\":\"ok\",\"rationale\":\"glm fallback\"}"}}]}' > "${output_file}"
    printf '200'
    exit 0
  fi
fi

if [[ "${url}" == https://generativelanguage.googleapis.com/* ]]; then
  printf '%s\n' '{"candidates":[{"content":{"parts":[{"text":"{\"risk\":\"LOW\",\"approve\":true,\"findings\":[],\"recommendation\":\"ok\",\"rationale\":\"gemini metered fallback\"}"}]}}]}' > "${output_file}"
  printf '200'
  exit 0
fi

if [[ "${url}" == "https://api.x.ai/v1/chat/completions" ]]; then
  printf '%s\n' '{"choices":[{"message":{"content":"{\"risk\":\"LOW\",\"approve\":true,\"findings\":[],\"recommendation\":\"ok\",\"rationale\":\"xai metered fallback\"}"}}]}' > "${output_file}"
  printf '200'
  exit 0
fi

if [[ "${url}" == "https://api.anthropic.com/v1/messages" ]]; then
  if [[ -n "${FAKE_ANTHROPIC_HTTP:-}" ]]; then
    printf '%s\n' '{"error":{"message":"forced anthropic failure"}}' > "${output_file}"
    printf '%s' "${FAKE_ANTHROPIC_HTTP}"
    exit 0
  fi
  if [[ "${model}" == "claude-opus-4-6" ]]; then
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
      EXPECTED_CLAUDE_MODEL="${CLAUDE_TEST_MODEL}" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
      AGENT_NAME="claude-opus-assist" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-claude-opus-assist.json"
  assert_json_field "${result}" '.http_code' 'cli:0'
  assert_json_field "${result}" '.model' "${CLAUDE_TEST_MODEL}"
  assert_json_field "${result}" '.skipped' 'false'
}

test_subscription_claude_filters_malloc_noise() {
  make_noisy_claude
  local work_dir="${TMP_DIR}/subscription-claude-noise"
  local stderr_file="${TMP_DIR}/subscription-claude-noise.stderr"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
      AGENT_NAME="claude-opus-assist" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null 2>"${stderr_file}"
  )
  local result="${work_dir}/agent-claude-opus-assist.json"
  assert_json_field "${result}" '.http_code' 'cli:0'
  assert_json_field "${result}" '.skipped' 'false'
  if rg -q "MallocStackLogging" "${stderr_file}"; then
    echo "expected subscription runner stderr to filter MallocStackLogging noise" >&2
    return 1
  fi
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
  assert_json_field "${result}" '.model' 'glm-5'
  assert_json_field "${result}" '.http_code' '200'
  assert_json_field "${result}" '.skipped' 'false'
  jq -e '.model_attempts == "glm:glm-5:exit0-http200;glm:glm-5:ok" or .model_attempts == "glm:glm-5:ok"' "${result}" >/dev/null
}

test_subscription_glm_metered_gemini_fallback() {
  make_fake_curl
  local work_dir="${TMP_DIR}/subscription-glm-metered"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      PROVIDER="glm" \
      MODEL="" \
      ZAI_API_KEY="" \
      GEMINI_API_KEY="dummy" \
      METERED_PROVIDER_REASON="overflow" \
      AGENT_NAME="glm-code-reviewer" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-glm-code-reviewer.json"
  assert_json_field "${result}" '.provider' 'gemini' &&
    assert_json_field "${result}" '.execution_route' 'gemini-api' &&
    assert_json_field "${result}" '.fallback_used' 'true' &&
    assert_json_field "${result}" '.missing_lane' 'glm' &&
    assert_json_field "${result}" '.fallback_provider' 'gemini' &&
    assert_json_field "${result}" '.metered_reason' 'overflow'
}

test_subscription_claude_copilot_fallback() {
  make_failing_claude
  make_fake_copilot
  local work_dir="${TMP_DIR}/subscription-copilot"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      COPILOT_CLI_BIN="${TMP_DIR}/copilot" \
      HAS_COPILOT_CLI="true" \
      COPILOT_GITHUB_TOKEN="github_pat_example" \
      REQUIRE_GH_TOKEN="true" \
      REQUIRE_ALLOW_ALL_TOOLS="true" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
      AGENT_NAME="claude-main-orchestrator" \
      AGENT_ROLE="orchestrator" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-claude-main-orchestrator.json"
  assert_json_field "${result}" '.http_code' 'cli:0'
  assert_json_field "${result}" '.execution_route' 'claude-via-copilot-cli'
  assert_json_field "${result}" '.skipped' 'false'
  assert_json_field "${result}" '.fallback_used' 'true'
  assert_json_field "${result}" '.missing_lane' 'claude'
  assert_json_field "${result}" '.fallback_provider' 'copilot'
  jq -e --arg model "${CLAUDE_TEST_MODEL}" '.model_attempts | contains("claude:" + $model + ":exit99") and contains("copilot-cli:" + $model + ":ok")' "${result}" >/dev/null
}

test_subscription_xai_requires_metered_reason() {
  make_fake_curl
  local work_dir="${TMP_DIR}/subscription-xai-no-reason"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      PROVIDER="xai" \
      XAI_API_KEY="dummy" \
      AGENT_NAME="xai-realtime-info" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-xai-realtime-info.json"
  assert_json_field "${result}" '.skipped' 'true' &&
    assert_json_field "${result}" '.execution_route' 'xai-metered-reason-missing'
}

test_subscription_xai_metered_route() {
  make_fake_curl
  local work_dir="${TMP_DIR}/subscription-xai-metered"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      PROVIDER="xai" \
      XAI_API_KEY="dummy" \
      METERED_PROVIDER_REASON="tie-break" \
      AGENT_NAME="xai-realtime-info" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-xai-realtime-info.json"
  assert_json_field "${result}" '.provider' 'xai' &&
    assert_json_field "${result}" '.execution_route' 'xai-api' &&
    assert_json_field "${result}" '.metered_reason' 'tie-break' &&
    assert_json_field "${result}" '.skipped' 'false'
}

test_subscription_claude_opus_strict_rejects_copilot() {
  make_fake_copilot
  local work_dir="${TMP_DIR}/subscription-copilot-strict"
  mkdir -p "${work_dir}"
  if (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      COPILOT_CLI_BIN="${TMP_DIR}/copilot" \
      HAS_COPILOT_CLI="true" \
      COPILOT_GITHUB_TOKEN="github_pat_example" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
      AGENT_NAME="claude-opus-assist" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="true" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  ); then
    echo "expected strict opus guard to reject copilot route in subscription runner" >&2
    return 1
  fi
}

test_subscription_claude_copilot_gh_auth_fallback() {
  make_failing_claude
  make_fake_copilot
  make_fake_gh
  local work_dir="${TMP_DIR}/subscription-copilot-gh-auth"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      FAKE_GH_TOKEN="gho_from_gh_auth" \
      COPILOT_CLI_BIN="${TMP_DIR}/copilot" \
      HAS_COPILOT_CLI="true" \
      REQUIRE_GH_TOKEN="true" \
      REQUIRE_ALLOW_ALL_TOOLS="true" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
      AGENT_NAME="claude-main-orchestrator" \
      AGENT_ROLE="orchestrator" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-claude-main-orchestrator.json"
  assert_json_field "${result}" '.http_code' 'cli:0'
  assert_json_field "${result}" '.execution_route' 'claude-via-copilot-cli'
  assert_json_field "${result}" '.skipped' 'false'
  jq -e --arg model "${CLAUDE_TEST_MODEL}" '.model_attempts | contains("copilot-cli:" + $model + ":ok")' "${result}" >/dev/null
}

test_subscription_claude_failure_reports_missing_copilot_token() {
  make_failing_claude
  make_fake_copilot
  make_failing_gh
  local work_dir="${TMP_DIR}/subscription-claude-missing-copilot-token"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      COPILOT_CLI_BIN="${TMP_DIR}/copilot" \
      HAS_COPILOT_CLI="true" \
      REQUIRE_GH_TOKEN="true" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
      AGENT_NAME="claude-general-reviewer" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-claude-general-reviewer.json"
  assert_json_field "${result}" '.execution_route' 'claude-cli-failed'
  assert_json_field "${result}" '.skipped' 'true'
  jq -e '.rationale | contains("forced claude failure") and contains("Copilot CLI preflight failed: Copilot CLI authentication token is missing.")' "${result}" >/dev/null
}

test_subscription_local_direct_does_not_autofallback_to_copilot() {
  make_failing_claude
  make_fake_copilot
  local work_dir="${TMP_DIR}/subscription-local-direct-no-copilot"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      EXECUTION_PROFILE="local-direct" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
      AGENT_NAME="claude-general-reviewer" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-claude-general-reviewer.json"
  assert_json_field "${result}" '.execution_route' 'claude-cli-failed'
  assert_json_field "${result}" '.skipped' 'true'
  jq -e '.rationale | contains("forced claude failure") and (contains("Copilot CLI preflight failed") | not)' "${result}" >/dev/null
  jq -e --arg model "${CLAUDE_TEST_MODEL}" '.model_attempts | contains("claude:" + $model + ":exit99") and (contains("copilot-cli") | not)' "${result}" >/dev/null
}

test_subscription_claude_normalizes_stale_requested_model() {
  make_fake_claude
  local work_dir="${TMP_DIR}/subscription-claude-normalized"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      EXPECTED_CLAUDE_MODEL="${CLAUDE_TEST_MODEL}" \
      PROVIDER="claude" \
      MODEL="claude-sonnet-4-6" \
      AGENT_NAME="claude-general-reviewer" \
      AGENT_ROLE="reviewer" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${SUBSCRIPTION_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-claude-general-reviewer.json"
  assert_json_field "${result}" '.model' "${CLAUDE_TEST_MODEL}"
  jq -e --arg model "${CLAUDE_TEST_MODEL}" '.requested_model == "claude-sonnet-4-6" and .model_attempts == ("claude:" + $model + ":ok")' "${result}" >/dev/null
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
      MODEL="${CLAUDE_TEST_MODEL}" \
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
  assert_json_field "${result}" '.model' "${CLAUDE_TEST_MODEL}"
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
      COPILOT_GITHUB_TOKEN="dummy-token" \
      REQUIRE_GH_TOKEN="true" \
      REQUIRE_ALLOW_ALL_TOOLS="true" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
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
      COPILOT_GITHUB_TOKEN="dummy-token" \
      REQUIRE_GH_TOKEN="true" \
      COPILOT_ALLOW_ALL_TOOLS="true" \
      REQUIRE_ALLOW_ALL_TOOLS="true" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
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

test_ci_claude_copilot_npx_fallback() {
  make_fake_npx
  local work_dir="${TMP_DIR}/ci-copilot-npx"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      COPILOT_CLI_BIN="copilot" \
      HAS_COPILOT_CLI="true" \
      COPILOT_GITHUB_TOKEN="github_pat_example" \
      REQUIRE_GH_TOKEN="true" \
      REQUIRE_ALLOW_ALL_TOOLS="true" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
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
      COPILOT_GITHUB_TOKEN="dummy-token" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
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

test_ci_claude_copilot_unsupported_token_falls_back() {
  make_fake_copilot
  make_fake_curl
  local work_dir="${TMP_DIR}/ci-copilot-unsupported-token"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      COPILOT_CLI_BIN="${TMP_DIR}/copilot" \
      HAS_COPILOT_CLI="true" \
      COPILOT_GITHUB_TOKEN="ghp_classic_token" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
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
  assert_json_field "${result}" '.http_code' '200'
  assert_json_field "${result}" '.execution_route' 'claude-direct'
  assert_json_field "${result}" '.skipped' 'false'
  assert_json_field "${result}" '.copilot_failure' 'Copilot CLI token type is unsupported (classic_pat).'
  jq -e --arg model "${CLAUDE_TEST_MODEL}" '.model_attempts | contains("copilot-cli:" + $model + ":unsupported-token-type") and contains("claude:" + $model + ":200")' "${result}" >/dev/null
}

test_ci_claude_gemini_fallback_when_copilot_unavailable() {
  make_fake_curl
  local work_dir="${TMP_DIR}/ci-claude-gemini-fallback"
  mkdir -p "${work_dir}"
  (
    cd "${work_dir}"
    env \
      PATH="${TMP_DIR}:${BASE_TEST_PATH}" \
      HAS_COPILOT_CLI="false" \
      PROVIDER="claude" \
      MODEL="${CLAUDE_TEST_MODEL}" \
      API_URL="https://api.anthropic.com/v1/messages" \
      ANTHROPIC_API_KEY="dummy" \
      GEMINI_API_KEY="dummy" \
      GEMINI_MODEL="gemini-2.5-pro" \
      FAKE_ANTHROPIC_HTTP="400" \
      AGENT_NAME="claude-main-orchestrator" \
      AGENT_ROLE="orchestrator" \
      ISSUE_TITLE="compat" \
      ISSUE_BODY="check" \
      STRICT_OPUS_ASSIST_DIRECT="false" \
      bash "${CI_RUNNER}" >/dev/null
  )
  local result="${work_dir}/agent-claude-main-orchestrator.json"
  assert_json_field "${result}" '.provider' 'gemini'
  assert_json_field "${result}" '.http_code' '200'
  assert_json_field "${result}" '.execution_route' 'claude-via-gemini-fallback'
  assert_json_field "${result}" '.skipped' 'false'
  assert_json_field "${result}" '.fallback_used' 'true'
  assert_json_field "${result}" '.missing_lane' 'claude'
  assert_json_field "${result}" '.fallback_provider' 'gemini'
  jq -e --arg model "${CLAUDE_TEST_MODEL}" '.model_attempts | contains("claude:" + $model + ":400") and contains("gemini:gemini-2.5-pro:200")' "${result}" >/dev/null
}

echo "=== agent runner provider compatibility tests ==="
echo ""

run_test "subscription-claude-cli-flag" test_subscription_claude_cli_flag
run_test "subscription-claude-filters-malloc-noise" test_subscription_claude_filters_malloc_noise
run_test "subscription-glm-fallback" test_subscription_glm_fallback
run_test "subscription-glm-metered-gemini-fallback" test_subscription_glm_metered_gemini_fallback
run_test "subscription-claude-copilot-fallback" test_subscription_claude_copilot_fallback
run_test "subscription-xai-requires-metered-reason" test_subscription_xai_requires_metered_reason
run_test "subscription-xai-metered-route" test_subscription_xai_metered_route
run_test "subscription-claude-opus-strict-rejects-copilot" test_subscription_claude_opus_strict_rejects_copilot
run_test "subscription-claude-copilot-gh-auth-fallback" test_subscription_claude_copilot_gh_auth_fallback
run_test "subscription-claude-failure-reports-missing-copilot-token" test_subscription_claude_failure_reports_missing_copilot_token
run_test "subscription-local-direct-no-copilot-autofallback" test_subscription_local_direct_does_not_autofallback_to_copilot
run_test "ci-claude-api-model" test_ci_claude_api_model
run_test "ci-claude-copilot-mode" test_ci_claude_copilot_mode
run_test "ci-claude-copilot-allow-tools-opt-in" test_ci_claude_copilot_mode_allow_tools_opt_in
run_test "ci-claude-copilot-npx-fallback" test_ci_claude_copilot_npx_fallback
run_test "ci-claude-opus-strict-rejects-copilot" test_ci_claude_opus_strict_rejects_copilot
run_test "ci-claude-copilot-unsupported-token-falls-back" test_ci_claude_copilot_unsupported_token_falls_back
run_test "ci-claude-gemini-fallback-when-copilot-unavailable" test_ci_claude_gemini_fallback_when_copilot_unavailable

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
