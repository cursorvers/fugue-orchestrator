#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/config/integrations/local-systems.json"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

pass() {
  echo "[PASS] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

require_cmd jq
[[ -f "${MANIFEST}" ]] || fail "manifest not found: ${MANIFEST}"

if ! jq -e '.systems | type == "array"' "${MANIFEST}" >/dev/null; then
  fail "manifest .systems must be an array"
fi

systems_count="$(jq '.systems | length' "${MANIFEST}")"
if (( systems_count < 1 )); then
  fail "manifest has no systems"
fi
pass "systems count: ${systems_count}"

dups="$(jq -r '.systems | group_by(.id)[] | select(length > 1) | .[0].id' "${MANIFEST}")"
if [[ -n "${dups}" ]]; then
  fail "duplicate system IDs: ${dups}"
fi
pass "system IDs are unique"

invalid_ids="$(jq -r '.systems[] | .id // "" | select(test("^[a-z0-9][a-z0-9-]*$") | not)' "${MANIFEST}")"
if [[ -n "${invalid_ids}" ]]; then
  fail "invalid system IDs (must be kebab-case): ${invalid_ids}"
fi
pass "system IDs format valid"

while IFS= read -r row; do
  id="$(echo "${row}" | jq -r '.id')"
  adapter_rel="$(echo "${row}" | jq -r '.adapter')"
  enabled="$(echo "${row}" | jq -r '.enabled')"
  adapter_abs="${ROOT_DIR}/${adapter_rel}"

  [[ -n "${id}" ]] || fail "empty id entry in manifest"
  [[ -n "${adapter_rel}" && "${adapter_rel}" != "null" ]] || fail "system=${id} missing adapter path"
  [[ "${enabled}" == "true" || "${enabled}" == "false" ]] || fail "system=${id} enabled must be boolean"

  if [[ "${enabled}" == "true" ]]; then
    [[ -f "${adapter_abs}" ]] || fail "system=${id} adapter missing: ${adapter_rel}"
    [[ -x "${adapter_abs}" ]] || fail "system=${id} adapter not executable: ${adapter_rel}"
    if ! bash -n "${adapter_abs}"; then
      fail "system=${id} adapter bash syntax invalid: ${adapter_rel}"
    fi
  fi
done < <(jq -c '.systems[]' "${MANIFEST}")

pass "enabled adapters exist, are executable, and pass bash -n"
echo "linked systems integrity check passed"

