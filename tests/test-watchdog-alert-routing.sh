#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-watchdog.yml"

echo "=== watchdog alert routing policy test ==="
echo ""

BLOCKED_DISCORD_WEBHOOKS=(
  "DISCORD_WEBHOOK_URL"
  "DISCORD_ADMIN_WEBHOOK_URL"
  "DISCORD_MANUS_WEBHOOK_URL"
  "DISCORD_MAINT_WEBHOOK_URL"
)

if grep -Fq 'LINE_WEBHOOK_URL:' "${WORKFLOW}"; then
  echo "FAIL: fugue-watchdog must not wire LINE_WEBHOOK_URL for system alerts" >&2
  exit 1
fi

if grep -Fq 'DISCORD_NOTIFY_WEBHOOK_URL:' "${WORKFLOW}"; then
  echo "FAIL: fugue-watchdog must not wire DISCORD_NOTIFY_WEBHOOK_URL for system alerts" >&2
  exit 1
fi

for blocked_webhook in "${BLOCKED_DISCORD_WEBHOOKS[@]}"; do
  if grep -Fq "${blocked_webhook}" "${WORKFLOW}"; then
    echo "FAIL: fugue-watchdog must not reference ${blocked_webhook} in system alert paths" >&2
    exit 1
  fi
done

if grep -Fq 'LINE_CHANNEL_ACCESS_TOKEN:' "${WORKFLOW}"; then
  echo "FAIL: fugue-watchdog must not wire LINE_CHANNEL_ACCESS_TOKEN for system alerts" >&2
  exit 1
fi

if grep -Fq 'scripts/local/integrations/line-notify.sh --mode execute' "${WORKFLOW}"; then
  echo "FAIL: fugue-watchdog must not invoke line-notify execute for system alerts" >&2
  exit 1
fi

if grep -Fq 'LINE_SENT:' "${WORKFLOW}"; then
  echo "FAIL: fugue-watchdog must not rely on LINE delivery state for system alert persistence" >&2
  exit 1
fi

if grep -Fq 'watchdog-alert-delivery-policy.sh' "${WORKFLOW}"; then
  echo "FAIL: fugue-watchdog persist path must be Discord-only and not call mixed delivery policy" >&2
  exit 1
fi

grep -Fq 'status=disabled-by-policy' "${WORKFLOW}" || {
  echo "FAIL: fugue-watchdog must record LINE status as disabled-by-policy" >&2
  exit 1
}

grep -Fq 'LINE delivery is prohibited for fugue-watchdog system alerts' "${WORKFLOW}" || {
  echo "FAIL: fugue-watchdog must emit a policy notice for blocked LINE delivery" >&2
  exit 1
}

grep -Fq 'DISCORD_SYSTEM_WEBHOOK:' "${WORKFLOW}" || {
  echo "FAIL: fugue-watchdog must wire DISCORD_SYSTEM_WEBHOOK for system alerts" >&2
  exit 1
}

grep -Fq 'delivery=missing-system-webhook' "${WORKFLOW}" || {
  echo "FAIL: fugue-watchdog must fail closed on missing DISCORD_SYSTEM_WEBHOOK" >&2
  exit 1
}

grep -Fq 'Discord system webhook did not confirm delivery' "${WORKFLOW}" || {
  echo "FAIL: fugue-watchdog must fail closed when Discord delivery is not confirmed" >&2
  exit 1
}

grep -Fq 'watchdog_alert_next_state_b64=' "${WORKFLOW}" || {
  echo "FAIL: fugue-watchdog should pass persisted alert state through base64 GITHUB_OUTPUT" >&2
  exit 1
}

grep -Fq 'base64 -d | jq -c' "${WORKFLOW}" || {
  echo "FAIL: fugue-watchdog should decode and validate persisted alert state before gh variable set" >&2
  exit 1
}

if grep -Fq 'watchdog_alert_next_state_json=' "${WORKFLOW}"; then
  echo "FAIL: fugue-watchdog must not write raw JSON state directly to GITHUB_OUTPUT" >&2
  exit 1
fi

echo "PASS [watchdog-alert-routing]"
