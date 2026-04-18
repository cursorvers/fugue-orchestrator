#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DELIVERY_AUDIT="${ROOT_DIR}/.github/workflows/delivery-audit.yml"
ARTICLE_WORKFLOW="${ROOT_DIR}/.github/workflows/line-send-note-article.yml"
VALUE_WORKFLOW="${ROOT_DIR}/.github/workflows/line-value-share.yml"
RICHMENU_WORKFLOW="${ROOT_DIR}/.github/workflows/line-richmenu-deploy.yml"
WATCHDOG_WORKFLOW="${ROOT_DIR}/.github/workflows/fugue-watchdog.yml"

BLOCKED_DISCORD_WEBHOOKS=(
  "DISCORD_WEBHOOK_URL"
  "DISCORD_ADMIN_WEBHOOK_URL"
  "DISCORD_MANUS_WEBHOOK_URL"
  "DISCORD_MAINT_WEBHOOK_URL"
)

failures=0

assert_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "${needle}" "${file}"; then
    echo "PASS [${label}]"
  else
    echo "FAIL [${label}]: missing '${needle}' in ${file}" >&2
    failures=$((failures + 1))
  fi
}

assert_not_contains_block() {
  local file="$1"
  local start="$2"
  local end="$3"
  local needle="$4"
  local label="$5"
  if awk -v start="${start}" -v end="${end}" -v needle="${needle}" '
    index($0, start) { in_block=1 }
    in_block && index($0, needle) { found=1 }
    end != "" && in_block && index($0, end) { in_block=0 }
    END { exit found ? 0 : 1 }
  ' "${file}"; then
    echo "FAIL [${label}]: found '${needle}' in ${file}" >&2
    failures=$((failures + 1))
  else
    echo "PASS [${label}]"
  fi
}

assert_not_contains_token() {
  local file="$1"
  local needle="$2"
  local label="$3"
  if grep -Fq "${needle}" "${file}"; then
    echo "FAIL [${label}]: found '${needle}' in ${file}" >&2
    failures=$((failures + 1))
  else
    echo "PASS [${label}]"
  fi
}

assert_contains "${DELIVERY_AUDIT}" "Discord System Webhook Health Check" "delivery audit checks system webhook"
assert_contains "${DELIVERY_AUDIT}" 'DISCORD_SYSTEM_WEBHOOK: ${{ secrets.DISCORD_SYSTEM_WEBHOOK }}' "delivery audit wires system webhook"
assert_contains "${DELIVERY_AUDIT}" "Discord system anomaly notification sent." "delivery audit reports system notification delivery"
assert_contains "${DELIVERY_AUDIT}" "because it was created from \${failed_head_sha}, not current \${GITHUB_SHA}" "delivery audit does not rerun stale failed workflow attempts"
assert_contains "${DELIVERY_AUDIT}" "because it was created from workflow path \${failed_workflow_path}, not current \${workflow_path}" "delivery audit does not rerun failed workflows from stale workflow paths"
assert_contains "${DELIVERY_AUDIT}" "{id, run_number, created_at, head_sha, path}" "delivery audit captures failed run workflow path for rerun guard"
assert_contains "${DELIVERY_AUDIT}" "{id, path}" "delivery audit resolves canonical workflow path metadata"
assert_contains "${DELIVERY_AUDIT}" "LINE_DELIVERY_PAUSED: \${{ vars.LINE_DELIVERY_PAUSED }}" "delivery audit reads LINE pause state"
assert_contains "${DELIVERY_AUDIT}" "status=\"PAUSED\"" "delivery audit reports paused LINE state instead of unmitigated errors"
assert_contains "${DELIVERY_AUDIT}" "LINE quota exhaustion predicted but delivery is already paused" "delivery audit treats paused quota exhaustion as mitigated"
assert_not_contains_block "${DELIVERY_AUDIT}" "Notify Discord on anomaly" "Remediate transient GHA failures" "DISCORD_WEBHOOK_URL" "delivery audit anomaly does not use client webhook"

assert_contains "${ARTICLE_WORKFLOW}" 'DISCORD_SYSTEM_WEBHOOK: ${{ secrets.DISCORD_SYSTEM_WEBHOOK }}' "article failure notification wires system webhook"
assert_not_contains_block "${ARTICLE_WORKFLOW}" "Notify Discord on failure" "" "DISCORD_WEBHOOK_URL" "article failure notification does not use client webhook"

assert_contains "${VALUE_WORKFLOW}" 'DISCORD_SYSTEM_WEBHOOK: ${{ secrets.DISCORD_SYSTEM_WEBHOOK }}' "value failure notification wires system webhook"
assert_not_contains_block "${VALUE_WORKFLOW}" "Notify Discord on failure" "" "DISCORD_WEBHOOK_URL" "value failure notification does not use client webhook"

assert_contains "${RICHMENU_WORKFLOW}" 'DISCORD_SYSTEM_WEBHOOK: ${{ secrets.DISCORD_SYSTEM_WEBHOOK }}' "rich menu failure notification wires system webhook"
assert_not_contains_block "${RICHMENU_WORKFLOW}" "Notify Discord on failure" "" "DISCORD_WEBHOOK_URL" "rich menu failure notification does not use client webhook"

for blocked_webhook in "${BLOCKED_DISCORD_WEBHOOKS[@]}"; do
  assert_not_contains_token "${DELIVERY_AUDIT}" "${blocked_webhook}" "delivery audit excludes ${blocked_webhook}"
  assert_not_contains_token "${ARTICLE_WORKFLOW}" "${blocked_webhook}" "line-send-note-article excludes ${blocked_webhook}"
  assert_not_contains_token "${VALUE_WORKFLOW}" "${blocked_webhook}" "line-value-share excludes ${blocked_webhook}"
  assert_not_contains_token "${RICHMENU_WORKFLOW}" "${blocked_webhook}" "line-richmenu-deploy excludes ${blocked_webhook}"
  assert_not_contains_token "${WATCHDOG_WORKFLOW}" "${blocked_webhook}" "fugue-watchdog excludes ${blocked_webhook}"
done

if (( failures > 0 )); then
  exit 1
fi

echo "delivery system Discord routing check passed"
