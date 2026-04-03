#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION_FILE="${ROOT_DIR}/supabase/migrations/20260403110000_line_article_claim_rpc.sql"
HARDENING_MIGRATION_FILE="${ROOT_DIR}/supabase/migrations/20260403123000_line_article_ambiguous_quarantine.sql"
RUNBOOK_FILE="${ROOT_DIR}/docs/runbook/line-article-claim-migration.md"

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

test -f "${MIGRATION_FILE}" || {
  echo "FAIL [migration exists]: missing ${MIGRATION_FILE}" >&2
  exit 1
}

test -f "${HARDENING_MIGRATION_FILE}" || {
  echo "FAIL [hardening migration exists]: missing ${HARDENING_MIGRATION_FILE}" >&2
  exit 1
}

test -f "${RUNBOOK_FILE}" || {
  echo "FAIL [runbook exists]: missing ${RUNBOOK_FILE}" >&2
  exit 1
}

assert_contains "${MIGRATION_FILE}" "claim_article_for_line_delivery" "migration defines claim RPC"
assert_contains "${MIGRATION_FILE}" "mark_article_line_delivery_accepted" "migration defines accepted RPC"
assert_contains "${MIGRATION_FILE}" "mark_article_line_delivery_succeeded" "migration defines success RPC"
assert_contains "${MIGRATION_FILE}" "mark_article_line_delivery_failed" "migration defines failure RPC"
assert_contains "${MIGRATION_FILE}" "FOR UPDATE SKIP LOCKED" "migration uses row-level claim locking"
assert_contains "${MIGRATION_FILE}" "line_delivery_claim_token" "migration adds claim token column"
assert_contains "${MIGRATION_FILE}" "'reconcile'::text" "migration exposes reconcile mode for accepted rows"
assert_contains "${HARDENING_MIGRATION_FILE}" "mark_article_line_delivery_quarantined" "hardening migration defines quarantine RPC"
assert_contains "${HARDENING_MIGRATION_FILE}" "'quarantined'" "hardening migration adds quarantined status"
assert_contains "${HARDENING_MIGRATION_FILE}" "NULLIF(p_line_request_id, '')" "hardening migration preserves request id on empty input"
assert_contains "${RUNBOOK_FILE}" "workflow 切替方針" "runbook describes workflow migration"
assert_contains "${RUNBOOK_FILE}" "claim_article_for_line_delivery" "runbook references claim RPC"
assert_contains "${RUNBOOK_FILE}" "mark_article_line_delivery_quarantined" "runbook documents quarantine RPC"

if (( failures > 0 )); then
  exit 1
fi

echo "line article claim migration check passed"
