#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/config/integrations/peripheral-adapters.json"
LOCAL_SYSTEMS_MANIFEST="${ROOT_DIR}/config/integrations/local-systems.json"

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
[[ -f "${LOCAL_SYSTEMS_MANIFEST}" ]] || fail "local systems manifest not found: ${LOCAL_SYSTEMS_MANIFEST}"

if ! jq -e '.adapters | type == "array"' "${MANIFEST}" >/dev/null; then
  fail "manifest .adapters must be an array"
fi

adapter_count="$(jq '.adapters | length' "${MANIFEST}")"
if (( adapter_count < 1 )); then
  fail "manifest has no adapters"
fi
pass "adapter count: ${adapter_count}"

dups="$(jq -r '.adapters | group_by(.id)[] | select(length > 1) | .[0].id' "${MANIFEST}")"
if [[ -n "${dups}" ]]; then
  fail "duplicate adapter IDs: ${dups}"
fi
pass "adapter IDs are unique"

invalid_ids="$(jq -r '.adapters[] | .id // "" | select(test("^[a-z0-9][a-z0-9-]*$") | not)' "${MANIFEST}")"
if [[ -n "${invalid_ids}" ]]; then
  fail "invalid adapter IDs (must be kebab-case): ${invalid_ids}"
fi
pass "adapter IDs format valid"

enum_failures="$(jq -r '
  .adapters[]
  | select(
      (.scope | IN("local-linked","cross-repo","skill") | not)
      or (.kind | IN("content","knowledge","notify","service","ui","artifact") | not)
      or (.adapter_class | IN("shell","worker-service","external-contract","skill") | not)
      or (.authority | IN("artifact-only","service-adapter","gateway","protected-external","ui-boundary") | not)
      or (.validation_mode | IN("smoke","budgeted","regression","contract") | not)
      or (.contract_owner | IN("kernel-local","cloudflare","cursorvers-line","vercel","external") | not)
      or (.preferred_lane | IN("codex","claude","cloudflare","external") | not)
      or (.protected_interface | type != "boolean")
    )
  | .id
' "${MANIFEST}")"
if [[ -n "${enum_failures}" ]]; then
  fail "adapter entries with invalid enum values: ${enum_failures}"
fi
pass "adapter enums valid"

ingress_failures="$(jq -r '
  def valid_ingress_surface: IN("public-web","public-webhook","private-admin-ui","service-private");
  def valid_ingress_auth: IN("webhook-signature","tailscale-auth","session-auth","service-to-service");
  .adapters[]
  | . as $a
  | (((has("ingress_surface")) or (has("ingress_auth")) or (has("accepts_signed_payload")) or (has("routing_domain")) or (has("dedupe_strategy")) or (has("fail_closed")))) as $has_ingress
  | (((.authority == "gateway") or (.authority == "ui-boundary" and .protected_interface == true))) as $ingress_required
  | select(
      (($has_ingress) and (
        ((.ingress_surface // "") == "") or
        ((.ingress_auth // "") == "") or
        ((has("accepts_signed_payload") | not)) or
        ((.routing_domain // "") == "") or
        ((.ingress_surface | valid_ingress_surface) | not) or
        ((.ingress_auth | valid_ingress_auth) | not) or
        (.accepts_signed_payload | type != "boolean") or
        (.routing_domain | type != "string") or
        ((.routing_domain | test("^[a-z0-9][a-z0-9-]*$")) | not) or
        ((has("fail_closed")) and (.fail_closed | type != "boolean")) or
        ((has("dedupe_strategy")) and (.dedupe_strategy | type != "string")) or
        (.ingress_auth == "webhook-signature" and .accepts_signed_payload != true) or
        (.ingress_auth == "tailscale-auth" and (.ingress_surface | IN("private-admin-ui","service-private") | not)) or
        ((.ingress_surface | IN("public-web","public-webhook")) and .ingress_auth == "tailscale-auth")
      ))
      or
      (($ingress_required) and (
        ((.ingress_surface // "") == "") or
        ((.ingress_auth // "") == "") or
        ((has("accepts_signed_payload") | not)) or
        ((.routing_domain // "") == "")
      ))
      or
      ((.authority == "gateway") and (
        (.fail_closed != true) or
        ((.dedupe_strategy // "") == "")
      ))
    )
  | .id
' "${MANIFEST}")"
if [[ -n "${ingress_failures}" ]]; then
  fail "adapter entries with invalid ingress contract values: ${ingress_failures}"
fi
pass "adapter ingress contracts valid"

while IFS= read -r row; do
  id="$(echo "${row}" | jq -r '.id')"
  scope="$(echo "${row}" | jq -r '.scope')"
  adapter_class="$(echo "${row}" | jq -r '.adapter_class')"
  path_value="$(echo "${row}" | jq -r '.path // empty')"
  local_system_id="$(echo "${row}" | jq -r '.local_system_id // empty')"

  [[ -n "${id}" ]] || fail "empty adapter id"
  [[ -n "${scope}" ]] || fail "adapter=${id} missing scope"
  [[ -n "${adapter_class}" ]] || fail "adapter=${id} missing adapter_class"
  [[ -n "${path_value}" ]] || fail "adapter=${id} missing path"

  if [[ "${path_value}" == /* ]]; then
    resolved_path="${path_value}"
  else
    resolved_path="${ROOT_DIR}/${path_value}"
  fi
  [[ -e "${resolved_path}" ]] || fail "adapter=${id} path missing: ${path_value}"

  if [[ "${adapter_class}" == "shell" ]]; then
    [[ -f "${resolved_path}" ]] || fail "adapter=${id} shell path is not a file: ${path_value}"
    [[ -x "${resolved_path}" ]] || fail "adapter=${id} shell adapter not executable: ${path_value}"
    bash -n "${resolved_path}" || fail "adapter=${id} shell adapter bash syntax invalid: ${path_value}"
  fi

  if [[ "${scope}" == "local-linked" ]]; then
    [[ -n "${local_system_id}" ]] || fail "adapter=${id} missing local_system_id"
    jq -e --arg id "${local_system_id}" '.systems[] | select(.id == $id)' "${LOCAL_SYSTEMS_MANIFEST}" >/dev/null \
      || fail "adapter=${id} references unknown local_system_id=${local_system_id}"
  fi
done < <(jq -c '.adapters[]' "${MANIFEST}")

pass "adapter paths and local-linked references valid"
echo "peripheral adapter contract check passed"
