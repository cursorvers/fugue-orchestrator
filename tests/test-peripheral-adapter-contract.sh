#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="${ROOT_DIR}/scripts/check-peripheral-adapters.sh"
MANIFEST="${ROOT_DIR}/config/integrations/peripheral-adapters.json"

if [[ ! -x "${CHECK_SCRIPT}" ]]; then
  echo "FAIL: missing executable script ${CHECK_SCRIPT}" >&2
  exit 1
fi

bash "${CHECK_SCRIPT}" >/dev/null
echo "PASS [check-script]"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat >"${TMP_DIR}/local-systems.json" <<'JSON'
{
  "systems": [
    {
      "id": "local-dummy",
      "name": "Local Dummy",
      "path": "scripts/local/integrations/auto-video.sh"
    }
  ]
}
JSON

cat >"${TMP_DIR}/peripheral-adapters.json" <<'JSON'
{
  "adapters": [
    {
      "id": "cross-repo-missing-contract",
      "scope": "cross-repo",
      "kind": "service",
      "adapter_class": "external-contract",
      "authority": "protected-external",
      "validation_mode": "contract",
      "contract_owner": "external",
      "preferred_lane": "external",
      "protected_interface": true,
      "path": "../definitely-missing-repo/adapter.ts"
    },
    {
      "id": "missing-external-skill",
      "scope": "skill",
      "kind": "artifact",
      "adapter_class": "skill",
      "authority": "artifact-only",
      "validation_mode": "contract",
      "contract_owner": "kernel-local",
      "preferred_lane": "codex",
      "protected_interface": false,
      "path": "/Users/example/.codex/skills/missing/SKILL.md"
    }
  ]
}
JSON

PERIPHERAL_ADAPTER_MANIFEST="${TMP_DIR}/peripheral-adapters.json" \
  PERIPHERAL_LOCAL_SYSTEMS_MANIFEST="${TMP_DIR}/local-systems.json" \
  bash "${CHECK_SCRIPT}" --mode contract >/dev/null
echo "PASS [contract-mode-missing-cross-repo]"
echo "PASS [contract-mode-missing-external-skill]"

set +e
PERIPHERAL_ADAPTER_MANIFEST="${TMP_DIR}/peripheral-adapters.json" \
  PERIPHERAL_LOCAL_SYSTEMS_MANIFEST="${TMP_DIR}/local-systems.json" \
  bash "${CHECK_SCRIPT}" --mode strict >/dev/null 2>&1
strict_rc=$?
set -e
if [[ "${strict_rc}" == "0" ]]; then
  echo "FAIL: strict mode should reject missing cross-repo paths" >&2
  exit 1
fi
echo "PASS [strict-mode-missing-cross-repo]"

set +e
bash "${CHECK_SCRIPT}" --mode >/dev/null 2>&1
missing_mode_rc=$?
set -e
if [[ "${missing_mode_rc}" == "0" ]]; then
  echo "FAIL: --mode without value should fail" >&2
  exit 1
fi
echo "PASS [mode-missing-value]"

jq -e '.adapters[] | select(.id == "railway-kernel-edge-intake" and .authority == "gateway" and .ingress_auth == "webhook-signature" and .accepts_signed_payload == true and .fail_closed == true and (.dedupe_strategy | length > 0))' "${MANIFEST}" >/dev/null || {
  echo "FAIL: missing Railway edge intake ingress contract" >&2
  exit 1
}
echo "PASS [railway-edge-intake]"

jq -e '.adapters[] | select(.id == "tailscale-admin-ui" and .authority == "ui-boundary" and .ingress_auth == "tailscale-auth" and .ingress_surface == "private-admin-ui")' "${MANIFEST}" >/dev/null || {
  echo "FAIL: missing Tailscale admin UI ingress contract" >&2
  exit 1
}
echo "PASS [tailscale-admin-ui]"

jq -e '.adapters[] | select(.id == "railway-happy-web-boundary" and .authority == "ui-boundary" and .ingress_auth == "session-auth" and .routing_domain == "happy-public-web")' "${MANIFEST}" >/dev/null || {
  echo "FAIL: missing Railway Happy web boundary ingress contract" >&2
  exit 1
}
echo "PASS [railway-happy-web-boundary]"

echo "=== Results: 8/8 passed, 0 failed ==="
