#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="${ROOT_DIR}/scripts/lib/build-agent-matrix.sh"

if [[ ! -x "${BUILDER}" ]]; then
  echo "matrix builder is missing or not executable: ${BUILDER}" >&2
  exit 1
fi

failures=0

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "[FAIL] ${label}: expected=${expected} actual=${actual}" >&2
    failures=$((failures + 1))
  else
    echo "[PASS] ${label}: ${actual}" >&2
  fi
}

assert_lane() {
  local payload="$1"
  local lane="$2"
  local label="$3"
  if echo "${payload}" | jq -e --arg lane "${lane}" '.matrix.include | any(.name == $lane)' >/dev/null; then
    echo "[PASS] ${label}: lane=${lane}" >&2
  else
    echo "[FAIL] ${label}: missing lane=${lane}" >&2
    failures=$((failures + 1))
  fi
}

assert_no_lane() {
  local payload="$1"
  local lane="$2"
  local label="$3"
  if echo "${payload}" | jq -e --arg lane "${lane}" '.matrix.include | any(.name == $lane) | not' >/dev/null; then
    echo "[PASS] ${label}: lane absent=${lane}" >&2
  else
    echo "[FAIL] ${label}: lane unexpectedly present=${lane}" >&2
    failures=$((failures + 1))
  fi
}

# T1: GHA subscription strict (default enhanced) -> 12 lanes, no GLM baseline.
t1="$("${BUILDER}" \
  --engine subscription \
  --main-provider codex \
  --assist-provider claude \
  --multi-agent-mode enhanced \
  --glm-subagent-mode paired \
  --allow-glm-in-subscription false \
  --format json)"
assert_eq "$(echo "${t1}" | jq -r '.lanes')" "12" "T1 lanes"
assert_eq "$(echo "${t1}" | jq -r '.use_glm_baseline')" "false" "T1 glm baseline"
assert_lane "${t1}" "codex-main-orchestrator" "T1 main lane"
assert_lane "${t1}" "claude-opus-assist" "T1 assist lane"
assert_no_lane "${t1}" "glm-orchestration-subagent" "T1 no glm subagent on strict subscription"

# T2: GHA harness enhanced paired -> 17 lanes.
t2="$("${BUILDER}" \
  --engine harness \
  --main-provider codex \
  --assist-provider claude \
  --multi-agent-mode enhanced \
  --glm-subagent-mode paired \
  --allow-glm-in-subscription false \
  --format json)"
assert_eq "$(echo "${t2}" | jq -r '.lanes')" "17" "T2 lanes"
assert_eq "$(echo "${t2}" | jq -r '.use_glm_baseline')" "true" "T2 glm baseline"
assert_lane "${t2}" "glm-orchestration-subagent" "T2 glm orchestration subagent"
assert_lane "${t2}" "claude-sonnet4-assist" "T2 claude sonnet4 assist"

# T3: GHA harness max symphony (claude main + codex assist) -> 18 lanes.
t3="$("${BUILDER}" \
  --engine harness \
  --main-provider claude \
  --assist-provider codex \
  --multi-agent-mode max \
  --glm-subagent-mode symphony \
  --allow-glm-in-subscription false \
  --format json)"
assert_eq "$(echo "${t3}" | jq -r '.lanes')" "18" "T3 lanes"
assert_eq "$(echo "${t3}" | jq -r '.main_signal_lane')" "claude-main-orchestrator" "T3 main signal lane"
assert_lane "${t3}" "codex-orchestration-assist" "T3 codex assist lane"
assert_lane "${t3}" "glm-reliability-subagent" "T3 glm reliability subagent"

# T4: Local hybrid subscription + allow GLM -> 15 lanes.
t4="$("${BUILDER}" \
  --engine subscription \
  --main-provider codex \
  --assist-provider claude \
  --multi-agent-mode enhanced \
  --glm-subagent-mode paired \
  --allow-glm-in-subscription true \
  --format json)"
assert_eq "$(echo "${t4}" | jq -r '.lanes')" "15" "T4 lanes"
assert_eq "$(echo "${t4}" | jq -r '.use_glm_baseline')" "true" "T4 glm baseline"
assert_lane "${t4}" "glm-orchestration-subagent" "T4 glm orchestration subagent"
assert_lane "${t4}" "claude-opus-assist" "T4 claude opus assist"

# T5: Local hybrid standard/off -> 8 lanes.
t5="$("${BUILDER}" \
  --engine subscription \
  --main-provider codex \
  --assist-provider claude \
  --multi-agent-mode standard \
  --glm-subagent-mode off \
  --allow-glm-in-subscription true \
  --format json)"
assert_eq "$(echo "${t5}" | jq -r '.lanes')" "8" "T5 lanes"
assert_no_lane "${t5}" "glm-orchestration-subagent" "T5 no glm subagent when off"

if (( failures > 0 )); then
  echo "matrix parity check failed: ${failures} failure(s)" >&2
  exit 1
fi

echo "matrix parity check passed"
