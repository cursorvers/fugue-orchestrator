#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTICLE_WORKFLOW="${ROOT_DIR}/.github/workflows/line-send-note-article.yml"
VALUE_WORKFLOW="${ROOT_DIR}/.github/workflows/line-value-share.yml"

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

assert_not_contains() {
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

assert_not_contains "${ARTICLE_WORKFLOW}" "<<<<<<<" "article workflow has no merge markers"
assert_not_contains "${ARTICLE_WORKFLOW}" ">>>>>>>" "article workflow has no merge-marker tail"
assert_contains "${ARTICLE_WORKFLOW}" "LINE_NOTE_ARTICLE_PENDING_STATE" "article workflow tracks pending state"
assert_contains "${ARTICLE_WORKFLOW}" "accepted_pending_reconcile" "article workflow has reconcile mode"
assert_contains "${ARTICLE_WORKFLOW}" "Prepared delivery lock persisted" "article workflow writes prepared lock before send"
assert_contains "${ARTICLE_WORKFLOW}" "continue-on-error: true" "article workflow makes prepared lock best effort"
assert_contains "${ARTICLE_WORKFLOW}" "Accepted pending article reconciled without resend" "article workflow reconciles accepted pending article"
assert_contains "${ARTICLE_WORKFLOW}" "Pending delivery lock cleared" "article workflow clears pending lock after recovery"
assert_contains "${ARTICLE_WORKFLOW}" "continue-on-error: true" "article workflow tolerates audit/guard persistence failure paths"
assert_contains "${ARTICLE_WORKFLOW}" "id=eq.\${ARTICLE_ID}&is_notified=eq.false" "article workflow marks notified idempotently"
assert_contains "${VALUE_WORKFLOW}" "LINE_LAST_VALUE_SHARE_SENT_INDEX" "value workflow persists last sent rotation index"
assert_contains "${VALUE_WORKFLOW}" "skip_duplicate" "value workflow exposes duplicate guard output"
assert_contains "${VALUE_WORKFLOW}" "Heal rotation index after duplicate guard" "value workflow heals stale rotation index"

if (( failures > 0 )); then
  exit 1
fi

echo "line delivery dedup guard check passed"
