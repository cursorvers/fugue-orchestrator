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
assert_eq "$(printf '%s\n' "${help_output}" | grep -F "default: gpt-5-codex" | head -n1)" \
  "  --codex-multi-agent-model VALUE   default: gpt-5-codex" \
  "help codex multi default"
assert_eq "$(printf '%s\n' "${help_output}" | grep -F "default: glm-5" | head -n1)" \
  "  --glm-model VALUE                 default: glm-5" \
  "help glm default"

default_payload="$("${BUILDER}" --format json)"
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

if (( failures > 0 )); then
  echo "build-agent-matrix default check failed: ${failures} failure(s)" >&2
  exit 1
fi

echo "build-agent-matrix default check passed"
