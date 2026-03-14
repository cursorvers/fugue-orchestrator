#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/shadow-continuity-policy.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

fixture="${tmp_dir}/results.json"
cat > "${fixture}" <<'EOF'
[
  {"name":"codex-main-orchestrator","provider":"codex","http_code":"cli:0","skipped":false,"fallback_used":false},
  {"name":"claude-opus-assist","provider":"claude","http_code":"200","skipped":false,"fallback_used":false},
  {"name":"glm-general-reviewer","provider":"glm","http_code":"200","skipped":false,"fallback_used":false},
  {"name":"glm-risk-subagent","provider":"glm","http_code":"200","skipped":false,"fallback_used":false},
  {"name":"claude-opus-assist","provider":"copilot","http_code":"cli:0","skipped":false,"fallback_used":true,"missing_lane":"claude","fallback_provider":"copilot-cli"},
  {"name":"glm-general-reviewer","provider":"gemini","http_code":"200","skipped":false,"fallback_used":true,"missing_lane":"glm","fallback_provider":"gemini-cli"},
  {"name":"xai-general-reviewer","provider":"xai","http_code":"200","skipped":false,"fallback_used":false},
  {"name":"codex-shadow","provider":"codex","http_code":"200","skipped":false,"fallback_used":true,"fallback_provider":"codex"},
  {"name":"copilot-skipped","provider":"copilot","http_code":"200","skipped":true,"fallback_used":true,"fallback_provider":"copilot-cli"}
]
EOF

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL [${label}]: got '${actual}' expected '${expected}'"
    exit 1
  fi
  echo "PASS [${label}]"
}

echo "=== shadow-continuity policy contract tests ==="
echo ""

assert_eq "$(fugue_provider_success_count "${fixture}" "codex")" "1" "codex-success-count"
assert_eq "$(fugue_provider_success_count "${fixture}" "claude")" "1" "claude-success-count"
assert_eq "$(fugue_provider_success_count "${fixture}" "glm" "true")" "1" "glm-success-count-excludes-subagents"
assert_eq "$(fugue_shadow_continuity_families "${fixture}")" "copilot,gemini,xai" "shadow-continuity-families"
assert_eq "$(fugue_shadow_continuity_success_count "${fixture}")" "3" "shadow-continuity-success-count"
assert_eq "$(fugue_missing_lane_shadow_families "${fixture}" "claude")" "copilot" "claude-shadow-families"
assert_eq "$(fugue_missing_lane_shadow_success_count "${fixture}" "claude")" "1" "claude-shadow-success-count"
assert_eq "$(fugue_missing_lane_shadow_families "${fixture}" "glm")" "gemini" "glm-shadow-families"
assert_eq "$(fugue_missing_lane_shadow_success_count "${fixture}" "glm")" "1" "glm-shadow-success-count"

fugue_calculate_baseline_trio_policy "${fixture}" "true"
assert_eq "${FUGUE_BASELINE_TRIO_GATE}" "pass" "baseline-trio-pass"
assert_eq "${FUGUE_BASELINE_TRIO_REASON}" "codex+claude+glm-ok" "baseline-trio-pass-reason"

jq '[.[] | select((.provider // "") != "glm")]' "${fixture}" > "${tmp_dir}/missing-glm.json"
fugue_calculate_baseline_trio_policy "${tmp_dir}/missing-glm.json" "true"
assert_eq "${FUGUE_BASELINE_TRIO_GATE}" "recovery-pass" "baseline-trio-recovery-pass"
assert_eq "${FUGUE_BASELINE_TRIO_REASON}" "missing-glm;fallback-quorum=claude,copilot,gemini,xai" "baseline-trio-recovery-pass-reason"
assert_eq "${FUGUE_BASELINE_HIGH_RISK_BUMP}" "false" "baseline-no-high-risk-bump-on-recovery-pass"
assert_eq "${FUGUE_BASELINE_FORCE_WEIGHTED_VOTE_FALSE}" "false" "baseline-no-weighted-vote-force-false-on-recovery-pass"

fugue_calculate_baseline_trio_policy "${fixture}" "false"
assert_eq "${FUGUE_BASELINE_TRIO_GATE}" "not-required" "baseline-not-required"
assert_eq "${FUGUE_BASELINE_TRIO_REASON}" "policy-disabled" "baseline-not-required-reason"
