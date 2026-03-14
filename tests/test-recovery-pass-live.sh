#!/usr/bin/env bash
set -euo pipefail

# Live verification: recovery-first behavior via shadow-continuity-policy.sh
# Tests that recovery-pass is correctly computed when a baseline provider is missing
# but fallback providers fill the quorum.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/lib/shadow-continuity-policy.sh"

failures=0
pass_count=0

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    echo "[PASS] ${label}" >&2
    pass_count=$((pass_count + 1))
  else
    echo "[FAIL] ${label}: expected '${expected}', got '${actual}'" >&2
    failures=$((failures + 1))
  fi
}

# --- Scenario 1: All trio present → pass ---
scenario1_file="$(mktemp)"
cat > "${scenario1_file}" <<'JSON'
[
  {"name":"codex-main","provider":"codex","http_code":"cli:0","skipped":false},
  {"name":"claude-opus","provider":"claude","http_code":"200","skipped":false},
  {"name":"glm-reviewer","provider":"glm","http_code":"200","skipped":false}
]
JSON

fugue_calculate_baseline_trio_policy "${scenario1_file}" "true"
assert_eq "${FUGUE_BASELINE_TRIO_GATE}" "pass" "S1: full trio → pass"
assert_eq "${FUGUE_BASELINE_TRIO_REASON}" "codex+claude+glm-ok" "S1: reason is codex+claude+glm-ok"
assert_eq "${FUGUE_BASELINE_HIGH_RISK_BUMP}" "false" "S1: no high-risk bump"
rm -f "${scenario1_file}"

# --- Scenario 2: GLM missing, copilot+gemini fallback → recovery-pass ---
scenario2_file="$(mktemp)"
cat > "${scenario2_file}" <<'JSON'
[
  {"name":"codex-main","provider":"codex","http_code":"cli:0","skipped":false},
  {"name":"claude-opus","provider":"claude","http_code":"200","skipped":false},
  {"name":"glm-reviewer","provider":"glm","http_code":"500","skipped":false},
  {"name":"copilot-fallback","provider":"copilot","http_code":"200","skipped":false,"fallback_used":true,"fallback_provider":"copilot-cli","missing_lane":"glm"},
  {"name":"gemini-fallback","provider":"gemini","http_code":"200","skipped":false}
]
JSON

fugue_calculate_baseline_trio_policy "${scenario2_file}" "true"
assert_eq "${FUGUE_BASELINE_TRIO_GATE}" "recovery-pass" "S2: GLM missing + copilot+gemini fallback → recovery-pass"
assert_eq "${FUGUE_BASELINE_HIGH_RISK_BUMP}" "false" "S2: no high-risk bump on recovery-pass"
assert_eq "${FUGUE_BASELINE_FORCE_WEIGHTED_VOTE_FALSE}" "false" "S2: weighted vote not forced false on recovery-pass"
rm -f "${scenario2_file}"

# --- Scenario 3: Claude missing, copilot+gemini fallback → recovery-pass ---
scenario3_file="$(mktemp)"
cat > "${scenario3_file}" <<'JSON'
[
  {"name":"codex-main","provider":"codex","http_code":"cli:0","skipped":false},
  {"name":"claude-opus","provider":"claude","http_code":"429","skipped":false},
  {"name":"glm-reviewer","provider":"glm","http_code":"200","skipped":false},
  {"name":"copilot-fallback","provider":"copilot","http_code":"200","skipped":false,"fallback_used":true,"fallback_provider":"copilot-cli","missing_lane":"claude"},
  {"name":"gemini-specialist","provider":"gemini","http_code":"200","skipped":false}
]
JSON

fugue_calculate_baseline_trio_policy "${scenario3_file}" "true"
assert_eq "${FUGUE_BASELINE_TRIO_GATE}" "recovery-pass" "S3: Claude missing + copilot+gemini → recovery-pass"
rm -f "${scenario3_file}"

# --- Scenario 4: GLM missing, only 1 non-codex family → fail ---
scenario4_file="$(mktemp)"
cat > "${scenario4_file}" <<'JSON'
[
  {"name":"codex-main","provider":"codex","http_code":"cli:0","skipped":false},
  {"name":"claude-opus","provider":"claude","http_code":"200","skipped":false},
  {"name":"glm-reviewer","provider":"glm","http_code":"500","skipped":false}
]
JSON

fugue_calculate_baseline_trio_policy "${scenario4_file}" "true"
assert_eq "${FUGUE_BASELINE_TRIO_GATE}" "fail" "S4: GLM missing + only claude (1 non-codex) → fail"
assert_eq "${FUGUE_BASELINE_HIGH_RISK_BUMP}" "true" "S4: high-risk bump on fail"
assert_eq "${FUGUE_BASELINE_FORCE_WEIGHTED_VOTE_FALSE}" "true" "S4: weighted vote forced false on fail"
rm -f "${scenario4_file}"

# --- Scenario 5: Codex missing → fail (no recovery possible) ---
scenario5_file="$(mktemp)"
cat > "${scenario5_file}" <<'JSON'
[
  {"name":"codex-main","provider":"codex","http_code":"500","skipped":false},
  {"name":"claude-opus","provider":"claude","http_code":"200","skipped":false},
  {"name":"glm-reviewer","provider":"glm","http_code":"200","skipped":false},
  {"name":"copilot-fallback","provider":"copilot","http_code":"200","skipped":false}
]
JSON

fugue_calculate_baseline_trio_policy "${scenario5_file}" "true"
assert_eq "${FUGUE_BASELINE_TRIO_GATE}" "fail" "S5: Codex missing → fail (codex is non-negotiable)"
rm -f "${scenario5_file}"

# --- Scenario 6: policy disabled → not-required ---
scenario6_file="$(mktemp)"
cat > "${scenario6_file}" <<'JSON'
[
  {"name":"codex-main","provider":"codex","http_code":"cli:0","skipped":false}
]
JSON

fugue_calculate_baseline_trio_policy "${scenario6_file}" "false"
assert_eq "${FUGUE_BASELINE_TRIO_GATE}" "not-required" "S6: policy disabled → not-required"
assert_eq "${FUGUE_BASELINE_TRIO_REASON}" "policy-disabled" "S6: reason is policy-disabled"
rm -f "${scenario6_file}"

# --- Scenario 7: GLM subagent excluded from baseline count ---
scenario7_file="$(mktemp)"
cat > "${scenario7_file}" <<'JSON'
[
  {"name":"codex-main","provider":"codex","http_code":"cli:0","skipped":false},
  {"name":"claude-opus","provider":"claude","http_code":"200","skipped":false},
  {"name":"glm-reliability-subagent","provider":"glm","http_code":"200","skipped":false},
  {"name":"copilot-helper","provider":"copilot","http_code":"200","skipped":false},
  {"name":"gemini-ui","provider":"gemini","http_code":"200","skipped":false}
]
JSON

fugue_calculate_baseline_trio_policy "${scenario7_file}" "true"
assert_eq "${FUGUE_BASELINE_TRIO_GATE}" "recovery-pass" "S7: GLM subagent excluded → GLM missing → recovery-pass via copilot+gemini"
rm -f "${scenario7_file}"

# --- Scenario 8: shadow continuity family detection ---
scenario8_file="$(mktemp)"
cat > "${scenario8_file}" <<'JSON'
[
  {"name":"codex-main","provider":"codex","http_code":"cli:0","skipped":false},
  {"name":"claude-opus","provider":"claude","http_code":"200","skipped":false},
  {"name":"glm-reviewer","provider":"glm","http_code":"500","skipped":false},
  {"name":"copilot-fallback","provider":"copilot","http_code":"200","skipped":false,"fallback_used":true,"fallback_provider":"copilot-cli","missing_lane":"glm"},
  {"name":"gemini-specialist","provider":"gemini","http_code":"200","skipped":false}
]
JSON

shadow_families="$(fugue_shadow_continuity_families "${scenario8_file}")"
shadow_count="$(fugue_shadow_continuity_success_count "${scenario8_file}")"
missing_glm_shadows="$(fugue_missing_lane_shadow_families "${scenario8_file}" "glm")"
missing_glm_count="$(fugue_missing_lane_shadow_success_count "${scenario8_file}" "glm")"

assert_eq "${shadow_count}" "2" "S8: shadow continuity detects 2 unique families (copilot+gemini, copilot-cli normalized)"
[[ "${shadow_families}" == *"copilot"* ]] && assert_eq "contains-copilot" "contains-copilot" "S8: shadow families include copilot" || { echo "[FAIL] S8: shadow families missing copilot: ${shadow_families}" >&2; failures=$((failures + 1)); }
[[ "${shadow_families}" == *"gemini"* ]] && assert_eq "contains-gemini" "contains-gemini" "S8: shadow families include gemini" || { echo "[FAIL] S8: shadow families missing gemini: ${shadow_families}" >&2; failures=$((failures + 1)); }
assert_eq "${missing_glm_count}" "1" "S8: GLM-specific shadow has 1 fallback"
[[ "${missing_glm_shadows}" == *"copilot"* ]] && assert_eq "glm-shadow-copilot" "glm-shadow-copilot" "S8: GLM shadow fallback is copilot" || { echo "[FAIL] S8: GLM shadow missing copilot: ${missing_glm_shadows}" >&2; failures=$((failures + 1)); }
rm -f "${scenario8_file}"

# --- Scenario 9: All three baselines missing → fail at policy level ---
# The recovery-pass for this case is handled at the council level
# (run-kernel-council-review.sh force-missing-provider override),
# not the policy function level. This test documents the policy behavior.
scenario9_file="$(mktemp)"
cat > "${scenario9_file}" <<'JSON'
[
  {"name":"codex-main","provider":"codex","http_code":"500","skipped":false},
  {"name":"claude-opus","provider":"claude","http_code":"500","skipped":false},
  {"name":"glm-reviewer","provider":"glm","http_code":"500","skipped":false},
  {"name":"copilot-fallback","provider":"copilot","http_code":"200","skipped":false,"fallback_used":true,"fallback_provider":"copilot-cli","missing_lane":"claude"},
  {"name":"gemini-specialist","provider":"gemini","http_code":"200","skipped":false},
  {"name":"xai-helper","provider":"xai","http_code":"200","skipped":false}
]
JSON

fugue_calculate_baseline_trio_policy "${scenario9_file}" "true"
assert_eq "${FUGUE_BASELINE_TRIO_GATE}" "fail" "S9: All three baselines missing → fail at policy level"
assert_eq "${FUGUE_BASELINE_HIGH_RISK_BUMP}" "true" "S9: high-risk bump on total baseline failure"
assert_eq "${FUGUE_SHADOW_CONTINUITY_SUCCESS_COUNT}" "3" "S9: shadow continuity detects 3 families"
rm -f "${scenario9_file}"

# --- Summary ---
echo "" >&2
echo "recovery-pass live verification: ${pass_count} passed, ${failures} failed" >&2

if (( failures > 0 )); then
  exit 1
fi
echo "recovery-pass live verification: ALL PASS"
