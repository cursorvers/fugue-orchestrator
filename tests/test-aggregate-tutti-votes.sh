#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/harness/aggregate-tutti-votes.sh"

passed=0
failed=0
total=0

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

write_result() {
  local path="$1"
  local name="$2"
  local provider="$3"
  local role="$4"
  local fallback_used="${5:-false}"
  local fallback_provider="${6:-}"
  cat > "${path}" <<EOF
{"name":"${name}","provider":"${provider}","model":"${provider}-model","agent_role":"${role}","http_code":"200","skipped":false,"risk":"LOW","approve":true,"findings":[],"recommendation":"ok","rationale":"ok","fallback_used":${fallback_used},"fallback_provider":"${fallback_provider}"}
EOF
}

run_case() {
  local name="$1"
  local claude_state="$2"
  local include_codex="$3"
  local include_claude="$4"
  local include_glm="$5"
  local include_copilot="$6"
  local include_gemini="$7"
  local require_baseline_trio="$8"
  local vote_command_input="$9"
  local expected_gate="${10}"
  local expected_reason="${11}"
  local case_dir="${tmp_dir}/${name}"
  local output_file="${case_dir}/github-output.txt"

  total=$((total + 1))
  mkdir -p "${case_dir}/agent-results"
  if [[ "${include_codex}" == "true" ]]; then
    write_result "${case_dir}/agent-results/codex.json" "codex-security-analyst" "codex" "security-analyst"
  fi
  if [[ "${include_claude}" == "true" ]]; then
    write_result "${case_dir}/agent-results/claude.json" "claude-opus-assist" "claude" "orchestration-assistant"
  fi
  if [[ "${include_glm}" == "true" ]]; then
    write_result "${case_dir}/agent-results/glm.json" "glm-general-reviewer" "glm" "general-reviewer"
  fi
  if [[ "${include_copilot}" == "true" ]]; then
    write_result "${case_dir}/agent-results/copilot.json" "claude-opus-assist" "copilot" "orchestration-assistant" "true" "copilot"
  fi
  if [[ "${include_gemini}" == "true" ]]; then
    write_result "${case_dir}/agent-results/gemini.json" "glm-general-reviewer" "gemini" "general-reviewer" "true" "gemini"
  fi

  if ! (
    cd "${case_dir}"
    env \
      ASSIST_PROVIDER_RESOLVED="claude" \
      CLAUDE_RATE_LIMIT_STATE="${claude_state}" \
      REQUIRE_DIRECT_CLAUDE_ASSIST="false" \
      REQUIRE_CLAUDE_SUB_ON_COMPLEX="true" \
      REQUIRE_BASELINE_TRIO="${require_baseline_trio}" \
      VOTE_COMMAND_INPUT="${vote_command_input}" \
      INPUT_RISK_TIER="low" \
      INPUT_AMBIGUITY_TRANSLATION_GATE="false" \
      INPUT_AMBIGUITY_TRANSLATION_SCORE="0" \
      INPUT_CLAUDE_SUB_TRIGGER="none" \
      GITHUB_OUTPUT="${output_file}" \
      bash "${SCRIPT}" >/dev/null 2>"${case_dir}/stderr.log"
  ); then
    echo "FAIL [${name}]: script exited with error"
    failed=$((failed + 1))
    return
  fi

  # shellcheck disable=SC1090
  source "${case_dir}/integration-vars.sh"
  if [[ "${baseline_trio_gate}" != "${expected_gate}" || "${baseline_trio_reason}" != "${expected_reason}" ]]; then
    echo "FAIL [${name}]: gate=${baseline_trio_gate}/${baseline_trio_reason} expected ${expected_gate}/${expected_reason}"
    failed=$((failed + 1))
    return
  fi

  echo "PASS [${name}]"
  passed=$((passed + 1))
}

echo "=== aggregate-tutti-votes.sh unit tests ==="
echo ""

run_case "baseline-trio-pass" "ok" "true" "true" "true" "false" "false" "true" "false" "pass" "codex+claude+glm-ok"
run_case "baseline-trio-missing-codex" "ok" "false" "true" "true" "false" "false" "true" "false" "fail" "missing-codex"
run_case "baseline-trio-no-waiver-on-degraded-claude" "degraded" "true" "false" "true" "false" "false" "true" "false" "fail" "missing-claude"
run_case "baseline-trio-missing-glm" "ok" "true" "true" "false" "false" "false" "true" "false" "fail" "missing-glm"
run_case "baseline-trio-multiple-missing" "ok" "false" "true" "false" "false" "false" "true" "false" "fail" "missing-codex,glm"
run_case "baseline-trio-shadow-continuity-recovery-pass" "ok" "true" "false" "false" "true" "true" "true" "false" "recovery-pass" "missing-claude,glm;fallback-quorum=copilot,gemini"
run_case "baseline-trio-fallback-missing-second-family" "ok" "true" "false" "false" "true" "false" "true" "false" "fail" "missing-claude,glm;shadow-continuity=copilot"
run_case "baseline-trio-not-required" "ok" "true" "false" "false" "false" "false" "false" "false" "not-required" "policy-disabled"
run_case "baseline-trio-vote-command-forces-required" "ok" "true" "false" "false" "false" "false" "false" "true" "fail" "missing-claude,glm"

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
