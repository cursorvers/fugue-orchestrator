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

echo "=== Results: 4/4 passed, 0 failed ==="
