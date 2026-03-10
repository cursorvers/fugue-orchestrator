#!/usr/bin/env bash
set -euo pipefail

# test-execution-profile-policy.sh — Unit test for execution profile policy.
#
# Tests subscription/harness/api engine resolution, continuity fallback,
# hold-path assist demotion, capability guard, and strict mode handling.
#
# Usage: bash tests/test-execution-profile-policy.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="${SCRIPT_DIR}/scripts/lib/execution-profile-policy.sh"

passed=0
failed=0
total=0

assert_profile() {
  local test_name="$1"
  shift
  local expected_profile="$1" expected_runner="$2" expected_assist="$3"
  shift 3

  total=$((total + 1))
  local output
  output="$("${POLICY}" "$@" --format env)" || {
    echo "FAIL [${test_name}]: script exited with error"
    failed=$((failed + 1))
    return
  }

  eval "${output}"

  local errors=""
  if [[ "${execution_profile}" != "${expected_profile}" ]]; then
    errors+=" profile=${execution_profile}(expected ${expected_profile})"
  fi
  if [[ "${run_agents_runner}" != "${expected_runner}" ]]; then
    errors+=" runner=${run_agents_runner}(expected ${expected_runner})"
  fi
  if [[ "${assist_provider_effective}" != "${expected_assist}" ]]; then
    errors+=" assist=${assist_provider_effective}(expected ${expected_assist})"
  fi

  if [[ -n "${errors}" ]]; then
    echo "FAIL [${test_name}]:${errors}"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  fi
}

assert_field() {
  local test_name="$1"
  local field_name="$2"
  local expected_value="$3"
  shift 3

  total=$((total + 1))
  local output
  output="$("${POLICY}" "$@" --format env)" || {
    echo "FAIL [${test_name}]: script exited with error"
    failed=$((failed + 1))
    return
  }

  eval "${output}"
  local actual="${!field_name}"

  if [[ "${actual}" != "${expected_value}" ]]; then
    echo "FAIL [${test_name}]: ${field_name}=${actual}(expected ${expected_value})"
    failed=$((failed + 1))
  else
    echo "PASS [${test_name}]"
    passed=$((passed + 1))
  fi
}

echo "=== execution-profile-policy.sh unit tests ==="
echo ""

# --- Group 1: Subscription online ---
assert_profile "sub-online" \
  "subscription-strict" "self-hosted" "claude" \
  --requested-engine subscription --self-hosted-online true --assist-provider claude

assert_field "sub-online-engine" "effective_engine" "subscription" \
  --requested-engine subscription --self-hosted-online true

assert_field "sub-online-continuity" "continuity_active" "false" \
  --requested-engine subscription --self-hosted-online true

assert_field "sub-online-strict-main" "strict_main_effective" "true" \
  --requested-engine subscription --self-hosted-online true --strict-main-requested true

# --- Group 2: Subscription offline + continuity ---
assert_profile "sub-offline-continuity" \
  "api-continuity" "ubuntu-latest" "claude" \
  --requested-engine subscription --self-hosted-online false --assist-provider claude --claude-state ok

assert_field "sub-offline-continuity-active" "continuity_active" "true" \
  --requested-engine subscription --self-hosted-online false --subscription-offline-policy continuity

assert_field "sub-offline-continuity-strict-off" "strict_main_effective" "false" \
  --requested-engine subscription --self-hosted-online false --strict-main-requested true

# --- Group 3: Subscription offline + continuity + claude degraded → assist demotion ---
assert_profile "sub-offline-continuity-degraded" \
  "api-continuity" "ubuntu-latest" "codex" \
  --requested-engine subscription --self-hosted-online false --assist-provider claude --claude-state degraded --emergency-assist-policy codex

assert_field "sub-offline-continuity-degraded-reason" "assist_adjustment_reason" "subscription-fallback-assist-claude->codex" \
  --requested-engine subscription --self-hosted-online false --assist-provider claude --claude-state degraded --emergency-assist-policy codex

assert_profile "sub-offline-continuity-degraded-none" \
  "api-continuity" "ubuntu-latest" "none" \
  --requested-engine subscription --self-hosted-online false --assist-provider claude --claude-state degraded --emergency-assist-policy none

assert_profile "sub-offline-continuity-exhausted" \
  "api-continuity" "ubuntu-latest" "none" \
  --requested-engine subscription --self-hosted-online false --assist-provider claude --claude-state exhausted --emergency-assist-policy none

# --- Group 4: Subscription offline + hold ---
assert_profile "sub-offline-hold" \
  "subscription-paused" "self-hosted" "claude" \
  --requested-engine subscription --self-hosted-online false --subscription-offline-policy hold --assist-provider claude --claude-state ok

assert_field "sub-offline-hold-engine" "effective_engine" "subscription" \
  --requested-engine subscription --self-hosted-online false --subscription-offline-policy hold

# --- Group 5: Hold + claude degraded → assist demotion (E2 fix) ---
assert_profile "hold-degraded-demote" \
  "subscription-paused" "self-hosted" "codex" \
  --requested-engine subscription --self-hosted-online false --subscription-offline-policy hold --assist-provider claude --claude-state degraded --emergency-assist-policy codex

assert_field "hold-degraded-reason" "assist_adjustment_reason" "hold-assist-claude-unavailable->codex" \
  --requested-engine subscription --self-hosted-online false --subscription-offline-policy hold --assist-provider claude --claude-state degraded --emergency-assist-policy codex

assert_profile "hold-exhausted-demote" \
  "subscription-paused" "self-hosted" "none" \
  --requested-engine subscription --self-hosted-online false --subscription-offline-policy hold --assist-provider claude --claude-state exhausted --emergency-assist-policy none

# --- Group 6: Hold + force-claude → no demotion ---
assert_profile "hold-degraded-force" \
  "subscription-paused" "self-hosted" "claude" \
  --requested-engine subscription --self-hosted-online false --subscription-offline-policy hold --assist-provider claude --claude-state degraded --force-claude true

# --- Group 7: API/harness engine ---
assert_profile "api-standard" \
  "api-standard" "ubuntu-latest" "claude" \
  --requested-engine api --assist-provider claude --claude-state ok

assert_profile "harness-standard" \
  "api-standard" "ubuntu-latest" "claude" \
  --requested-engine harness --assist-provider claude --claude-state ok

# --- Group 8: Emergency continuity mode ---
assert_profile "emergency-continuity" \
  "api-continuity" "ubuntu-latest" "codex" \
  --requested-engine api --emergency-continuity-mode true --assist-provider claude --claude-state degraded --emergency-assist-policy codex

assert_field "emergency-reason" "assist_adjustment_reason" "emergency-mode-assist-claude->codex" \
  --requested-engine api --emergency-continuity-mode true --assist-provider claude --claude-state degraded --emergency-assist-policy codex

# --- Group 9: Capability guard (claude direct unavailable) ---
assert_profile "api-claude-unavailable" \
  "api-standard" "ubuntu-latest" "codex" \
  --requested-engine api --assist-provider claude --claude-state ok --claude-direct-available false --emergency-assist-policy codex

assert_field "api-claude-unavail-reason" "assist_adjustment_reason" "api-capability-assist-claude-unavailable->codex" \
  --requested-engine api --assist-provider claude --claude-state ok --claude-direct-available false --emergency-assist-policy codex

# --- Group 10: Codex assist bypasses demotion ---
assert_profile "sub-offline-codex-assist" \
  "api-continuity" "ubuntu-latest" "codex" \
  --requested-engine subscription --self-hosted-online false --assist-provider codex --claude-state degraded

assert_field "sub-offline-codex-no-adjust" "assist_adjusted_by_profile" "false" \
  --requested-engine subscription --self-hosted-online false --assist-provider codex --claude-state degraded

# --- Group 11: JSON format ---
assert_field "json-profile" "execution_profile" "subscription-strict" \
  --requested-engine subscription --self-hosted-online true

# --- Group 12: Defaults ---
assert_profile "defaults" \
  "api-continuity" "ubuntu-latest" "claude" \
  # no args: requested_engine=subscription, self_hosted_online=false (continuity default)

echo ""
echo "=== Results: ${passed}/${total} passed, ${failed} failed ==="

if [[ "${failed}" -gt 0 ]]; then
  exit 1
fi
exit 0
