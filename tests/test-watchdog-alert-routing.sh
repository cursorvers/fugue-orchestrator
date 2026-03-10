#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-watchdog.yml"

echo "=== watchdog alert routing policy test ==="
echo ""

if grep -Fq 'LINE_WEBHOOK_URL:' "${WORKFLOW}"; then
  echo "FAIL: fugue-watchdog must not wire LINE_WEBHOOK_URL for system alerts" >&2
  exit 1
fi

if grep -Fq 'DISCORD_WEBHOOK_URL:' "${WORKFLOW}"; then
  echo "FAIL: fugue-watchdog must not wire DISCORD_WEBHOOK_URL fallback for system alerts" >&2
  exit 1
fi

if grep -Fq 'DISCORD_NOTIFY_WEBHOOK_URL:' "${WORKFLOW}"; then
  echo "FAIL: fugue-watchdog must not wire DISCORD_NOTIFY_WEBHOOK_URL for system alerts" >&2
  exit 1
fi

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

echo "PASS [watchdog-alert-routing]"
