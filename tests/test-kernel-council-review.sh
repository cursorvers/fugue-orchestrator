#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/harness/run-kernel-council-review.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

pass() {
  echo "PASS [$1]"
  passed=$((passed + 1))
}

fail() {
  echo "FAIL [$1]" >&2
  failed=$((failed + 1))
}

make_stubs() {
  local dir="$1"
  mkdir -p "${dir}"

  cat > "${dir}/build-agent-matrix.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat <<'JSON'
{"matrix":{"include":[
  {"name":"codex-main-orchestrator","provider":"codex","model":"gpt-5.4","api_url":"","agent_role":"main-orchestrator","agent_directive":"main"},
  {"name":"claude-opus-assist","provider":"claude","model":"claude-opus-4-6","api_url":"","agent_role":"orchestration-assistant","agent_directive":"assist"},
  {"name":"glm-general-reviewer","provider":"glm","model":"glm-5","api_url":"","agent_role":"general-reviewer","agent_directive":"review"}
]}}
JSON
EOF
  chmod +x "${dir}/build-agent-matrix.sh"

  cat > "${dir}/build-agent-matrix-recovery.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${COUNCIL_RECOVERY_ATTEMPTED:-false}" != "true" ]]; then
  echo "matrix unavailable before recovery" >&2
  exit 19
fi
cat <<'JSON'
{"matrix":{"include":[
  {"name":"codex-main-orchestrator","provider":"codex","model":"gpt-5.4","api_url":"","agent_role":"main-orchestrator","agent_directive":"main"},
  {"name":"claude-opus-assist","provider":"claude","model":"claude-opus-4-6","api_url":"","agent_role":"orchestration-assistant","agent_directive":"assist"},
  {"name":"glm-general-reviewer","provider":"glm","model":"glm-5","api_url":"","agent_role":"general-reviewer","agent_directive":"review"}
]}}
JSON
EOF
  chmod +x "${dir}/build-agent-matrix-recovery.sh"

  cat > "${dir}/subscription-agent-runner.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -n \
  --arg name "${AGENT_NAME}" \
  --arg provider "${PROVIDER}" \
  --arg model "${MODEL}" \
  --arg agent_role "${AGENT_ROLE}" \
  '{
    name:$name,
    provider:$provider,
    model:$model,
    api_url:"",
    agent_role:$agent_role,
    http_code:"200",
    skipped:false,
    risk:"LOW",
    approve:true,
    findings:["ok"],
    recommendation:"ok",
    rationale:"ok",
    execution_engine:"kernel-council"
  }' > "agent-${AGENT_NAME}.json"
EOF
  chmod +x "${dir}/subscription-agent-runner.sh"

  cat > "${dir}/aggregate-pass.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat > "${GITHUB_OUTPUT}" <<'OUT'
weighted_vote_passed=true
ok_to_execute=true
OUT
cat > integration-vars.sh <<'OUT'
baseline_trio_gate='pass'
baseline_trio_reason='codex+claude+glm-ok'
required_claude_assist_gate='not-required'
required_claude_assist_reason='direct-policy-disabled'
OUT
EOF
  chmod +x "${dir}/aggregate-pass.sh"

  cat > "${dir}/aggregate-fail.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat > "${GITHUB_OUTPUT}" <<'OUT'
weighted_vote_passed=false
ok_to_execute=false
OUT
cat > integration-vars.sh <<'OUT'
baseline_trio_gate='fail'
baseline_trio_reason='missing-glm'
required_claude_assist_gate='not-required'
required_claude_assist_reason='direct-policy-disabled'
OUT
EOF
  chmod +x "${dir}/aggregate-fail.sh"

  cat > "${dir}/aggregate-crash.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "boom" >&2
exit 23
EOF
  chmod +x "${dir}/aggregate-crash.sh"

  cat > "${dir}/aggregate-recovery.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${COUNCIL_RECOVERY_ATTEMPTED:-false}" == "true" ]]; then
  cat > "${GITHUB_OUTPUT}" <<'OUT'
weighted_vote_passed=true
ok_to_execute=true
OUT
  cat > integration-vars.sh <<'OUT'
baseline_trio_gate='recovery-pass'
baseline_trio_reason='missing-glm;fallback-quorum=copilot,gemini'
required_claude_assist_gate='not-required'
required_claude_assist_reason='direct-policy-disabled'
OUT
else
  cat > "${GITHUB_OUTPUT}" <<'OUT'
weighted_vote_passed=false
ok_to_execute=false
OUT
  cat > integration-vars.sh <<'OUT'
baseline_trio_gate='fail'
baseline_trio_reason='missing-glm'
required_claude_assist_gate='not-required'
required_claude_assist_reason='direct-policy-disabled'
OUT
fi
EOF
  chmod +x "${dir}/aggregate-recovery.sh"

  cat > "${dir}/aggregate-vote-reject.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${COUNCIL_RECOVERY_ATTEMPTED:-false}" == "true" ]]; then
  cat > "${GITHUB_OUTPUT}" <<'OUT'
weighted_vote_passed=true
ok_to_execute=true
OUT
else
  cat > "${GITHUB_OUTPUT}" <<'OUT'
weighted_vote_passed=false
ok_to_execute=false
OUT
fi
cat > integration-vars.sh <<'OUT'
baseline_trio_gate='pass'
baseline_trio_reason='codex+claude+glm-ok'
required_claude_assist_gate='not-required'
required_claude_assist_reason='direct-policy-disabled'
OUT
EOF
  chmod +x "${dir}/aggregate-vote-reject.sh"
}

run_case() {
  local name="$1"
  local aggregate_script="$2"
  local expected_rc="$3"
  local expected_ok="$4"
  local expected_gate="$5"
  local expected_reason="$6"
  local expected_failure_stage="${7:-}"
  local expected_failure_reason="${8:-}"
  local build_script="${9:-build-agent-matrix.sh}"
  local case_dir="${tmp_dir}/${name}"
  local stub_dir="${case_dir}/stubs"
  local run_dir="${case_dir}/run"
  local output_file="${case_dir}/github-output.txt"

  total=$((total + 1))
  mkdir -p "${case_dir}" "${run_dir}"
  make_stubs "${stub_dir}"

  set +e
  env \
    FUGUE_BUILD_MATRIX_SCRIPT="${stub_dir}/${build_script}" \
    FUGUE_SUBSCRIPTION_RUNNER_SCRIPT="${stub_dir}/subscription-agent-runner.sh" \
    FUGUE_AGGREGATE_VOTES_SCRIPT="${stub_dir}/${aggregate_script}" \
    COUNCIL_RUN_DIR="${run_dir}" \
    GITHUB_OUTPUT="${output_file}" \
    COUNCIL_STAGE="preflight" \
    ISSUE_NUMBER="42" \
    ISSUE_TITLE="Kernel council test" \
    ISSUE_BODY="Council continuity test" \
    bash "${SCRIPT}" >/dev/null 2>"${case_dir}/stderr.log"
  rc=$?
  set -e

  if [[ "${rc}" -ne "${expected_rc}" ]]; then
    fail "${name}-exit-code"
    return
  fi

  if [[ ! -f "${run_dir}/council-status.json" ]]; then
    fail "${name}-status-file-missing"
    return
  fi

  if ! jq -e --arg expected "${expected_ok}" '.ok_to_execute == ($expected == "true")' "${run_dir}/council-status.json" >/dev/null; then
    fail "${name}-status-ok"
    return
  fi
  if ! jq -e --arg expected "${expected_gate}" '.baseline_trio_gate == $expected' "${run_dir}/council-status.json" >/dev/null; then
    fail "${name}-status-gate"
    return
  fi
  if ! jq -e --arg expected "${expected_reason}" '.baseline_trio_reason == $expected' "${run_dir}/council-status.json" >/dev/null; then
    fail "${name}-status-reason"
    return
  fi
  if ! jq -e '.execution_engine == "kernel-council"' "${run_dir}/council-status.json" >/dev/null; then
    fail "${name}-status-engine"
    return
  fi

  if ! grep -q "^council_ok=${expected_ok}$" "${output_file}"; then
    fail "${name}-output-council-ok"
    return
  fi

  if [[ -n "${expected_failure_stage}" ]]; then
    if ! jq -e --arg expected "${expected_failure_stage}" '.failure_stage == $expected' "${run_dir}/council-status.json" >/dev/null; then
      fail "${name}-status-failure-stage"
      return
    fi
    if ! jq -e --arg expected "${expected_failure_reason}" '.failure_reason == $expected' "${run_dir}/council-status.json" >/dev/null; then
      fail "${name}-status-failure-reason"
      return
    fi
  fi

  pass "${name}"
}

echo "=== run-kernel-council-review.sh unit tests ==="
echo ""

run_case "council-status-pass" "aggregate-pass.sh" 0 "true" "pass" "codex+claude+glm-ok"
run_case "council-status-recovery-pass" "aggregate-recovery.sh" 0 "true" "recovery-pass" "missing-glm;fallback-quorum=copilot,gemini"
run_case "council-status-fail-persists" "aggregate-fail.sh" 1 "false" "fail" "missing-glm"
run_case "council-status-vote-reject-no-retry" "aggregate-vote-reject.sh" 1 "false" "pass" "codex+claude+glm-ok" "council" "weighted-vote=false;baseline=pass/codex+claude+glm-ok"
run_case "council-status-build-matrix-recovery-pass" "aggregate-pass.sh" 0 "true" "pass" "codex+claude+glm-ok" "" "" "build-agent-matrix-recovery.sh"
run_case "council-status-crash-persists" "aggregate-crash.sh" 23 "false" "fail" "aggregate-not-run" "aggregate" "aggregate-script-exit-23"

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
