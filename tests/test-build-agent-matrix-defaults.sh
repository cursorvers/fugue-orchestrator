#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER="${ROOT_DIR}/scripts/lib/build-agent-matrix.sh"

if [[ ! -x "${BUILDER}" ]]; then
  echo "FAIL: missing executable builder ${BUILDER}" >&2
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

help_output="$("${BUILDER}" --help)"
if printf '%s\n' "${help_output}" | grep -Eq -- '--codex-main-model[[:space:]]+VALUE[[:space:]]+default: gpt-5-codex'; then
  echo "[PASS] help codex main default" >&2
else
  echo "[FAIL] help codex main default" >&2
  failures=$((failures + 1))
fi
if printf '%s\n' "${help_output}" | grep -Eq -- '--codex-multi-agent-model[[:space:]]+VALUE[[:space:]]+default: gpt-5-codex'; then
  echo "[PASS] help codex multi default" >&2
else
  echo "[FAIL] help codex multi default" >&2
  failures=$((failures + 1))
fi
if printf '%s\n' "${help_output}" | grep -Eq -- '--glm-model[[:space:]]+VALUE[[:space:]]+default: glm-5'; then
  echo "[PASS] help glm default" >&2
else
  echo "[FAIL] help glm default" >&2
  failures=$((failures + 1))
fi
if printf '%s\n' "${help_output}" | grep -Eq -- '--implementation-phase[[:space:]]+VALUE[[:space:]]+true\|false'; then
  echo "[PASS] help implementation phase" >&2
else
  echo "[FAIL] help implementation phase" >&2
  failures=$((failures + 1))
fi

default_payload="$("${BUILDER}" --format json)"
assert_eq "$(echo "${default_payload}" | jq -r '.matrix.include[] | select(.name == "codex-main-orchestrator") | .model' | sort -u)" \
  "gpt-5-codex" \
  "default main codex model"
assert_eq "$(echo "${default_payload}" | jq -r '.matrix.include[] | select(.provider == "codex" and .name != "codex-main-orchestrator") | .model' | sort -u)" \
  "gpt-5-codex" \
  "default non-main codex model"
assert_eq "$(echo "${default_payload}" | jq -r '.matrix.include[] | select(.provider == "glm") | .model' | sort -u)" \
  "" \
  "default subscription matrix omits glm lanes"

glm_payload="$("${BUILDER}" --engine subscription --allow-glm-in-subscription true --format json)"
assert_eq "$(echo "${glm_payload}" | jq -r '.matrix.include[] | select(.provider == "glm") | .model' | sort -u)" \
  "glm-5" \
  "glm subscription-enabled default model"
assert_eq "$(echo "${glm_payload}" | jq -r '.matrix.include[] | select(.provider == "claude") | .name' | sort -u | tr '\n' ',' | sed 's/,$//')" \
  "claude-opus-assist" \
  "glm subscription-enabled matrix keeps claude lane"

implement_payload="$("${BUILDER}" --engine subscription --allow-glm-in-subscription true --assist-provider none --implementation-phase true --format json)"
assert_eq "$(echo "${implement_payload}" | jq -r '.matrix.include[] | select(.provider == "claude") | .name' | sort -u | tr '\n' ',' | sed 's/,$//')" \
  "claude-main-orchestrator,claude-opus-assist" \
  "implementation phase raises claude diversity lanes"
assert_eq "$(echo "${implement_payload}" | jq -r '.main_signal_lanes | join(",")')" \
  "codex-main-orchestrator,claude-main-orchestrator" \
  "implementation phase enables dual main signal"

if (( failures > 0 )); then
  echo "build-agent-matrix default check failed: ${failures} failure(s)" >&2
  exit 1
fi

echo "build-agent-matrix default check passed"
