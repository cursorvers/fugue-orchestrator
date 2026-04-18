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

assert_not_contains_regex() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Eq "${pattern}" "${file}"; then
    echo "FAIL [${label}]: found pattern '${pattern}' in ${file}" >&2
    failures=$((failures + 1))
  else
    echo "PASS [${label}]"
  fi
}

assert_not_contains "${ARTICLE_WORKFLOW}" "<<<<<<<" "article workflow has no merge markers"
assert_not_contains "${ARTICLE_WORKFLOW}" ">>>>>>>" "article workflow has no merge-marker tail"
assert_contains "${ARTICLE_WORKFLOW}" "claim_article_for_line_delivery" "article workflow claims delivery from Supabase RPC"
assert_contains "${ARTICLE_WORKFLOW}" "reconcile_article_line_delivery" "article workflow reconciles accepted delivery through RPC"
assert_contains "${ARTICLE_WORKFLOW}" "mark_article_line_delivery_accepted" "article workflow persists accepted state in Supabase"
assert_contains "${ARTICLE_WORKFLOW}" "mark_article_line_delivery_succeeded" "article workflow finalizes success in Supabase"
assert_contains "${ARTICLE_WORKFLOW}" "mark_article_line_delivery_failed" "article workflow marks failed sends in Supabase"
assert_contains "${ARTICLE_WORKFLOW}" "No claimable article found" "article workflow skips when no claimable article exists"
assert_contains "${ARTICLE_WORKFLOW}" "build_retry_key" "article workflow builds deterministic LINE retry key"
assert_contains "${ARTICLE_WORKFLOW}" "line-note-article:\${{ steps.article.outputs.article_id }}" "article workflow seeds retry key from article id"
assert_contains "${ARTICLE_WORKFLOW}" "LINE push request was already accepted for retry key" "article workflow handles duplicate retry-key acceptance"
assert_contains "${ARTICLE_WORKFLOW}" "Blocking rerun attempt" "article workflow blocks rerun attempts"
assert_contains "${ARTICLE_WORKFLOW}" "RUN_ATTEMPT: \${{ github.run_attempt }}" "article workflow wires github.run_attempt into quota gate"
assert_contains "${ARTICLE_WORKFLOW}" "skip_reason=\"rerun_blocked\"" "article workflow emits rerun_blocked skip reason"
assert_contains "${ARTICLE_WORKFLOW}" "Pause delivery after ambiguous send state" "article workflow pauses on ambiguous finalize state"
assert_contains "${ARTICLE_WORKFLOW}" "Quarantine ambiguous send state in Supabase" "article workflow quarantines ambiguous success in Supabase"
assert_contains "${ARTICLE_WORKFLOW}" "mark_article_line_delivery_quarantined" "article workflow calls quarantine RPC"
assert_contains "${ARTICLE_WORKFLOW}" "steps.send_line.outcome == 'success' && (steps.mark_accepted.outcome != 'success' || steps.finalize_delivery.outcome != 'success')" "article workflow pauses only for ambiguous finalize after successful send"
assert_contains "${ARTICLE_WORKFLOW}" "steps.send_line.outcome == 'success' && steps.mark_accepted.outcome == 'success'" "article workflow gates finalize on accepted-state success"
assert_contains "${ARTICLE_WORKFLOW}" "steps.article.outputs.reconcile_only != 'true'" "article workflow blocks resend when reconciliation path is selected"
assert_contains "${ARTICLE_WORKFLOW}" "REQUEST_ID_JSON=\"null\"" "article workflow sends null request id when LINE request id is empty"
assert_contains "${ARTICLE_WORKFLOW}" "\\\"p_line_request_id\\\": \${REQUEST_ID_JSON}" "article workflow avoids empty-string request id overwrites"
assert_contains "${ARTICLE_WORKFLOW}" "steps.quota_gate.outputs.gate_pass == 'true' && steps.article.outcome == 'success'" "article workflow only marks failure after a successful claim step"
assert_not_contains "${ARTICLE_WORKFLOW}" "REQUEST_URL=\"\${SUPABASE_URL}/rest/v1/articles" "article workflow no longer selects unpublished article directly"
assert_not_contains "${ARTICLE_WORKFLOW}" "Persist prepared delivery lock" "article workflow removed legacy prepared delivery lock"
assert_not_contains "${ARTICLE_WORKFLOW}" "Revalidate delivery lock" "article workflow removed legacy lock revalidation"
assert_not_contains_regex "${ARTICLE_WORKFLOW}" "actions/variables/LINE_NOTE_ARTICLE_PENDING_(ID|AT|STATE|REQUEST_ID)\" --jq '\\.value'" "article workflow no longer reads legacy pending lock variables for send gating"
assert_contains "${ARTICLE_WORKFLOW}" "RECEIPT_AT=\"\${ACCEPTED_AT:-}\"" "article workflow derives receipt timestamp when reconcile skips send"
assert_contains "${ARTICLE_WORKFLOW}" "Skipping initialization for \${name} because GitHub Variables cannot store empty strings." "article workflow skips empty variable initialization"
assert_contains "${ARTICLE_WORKFLOW}" "gh api -X DELETE \"repos/\${GITHUB_REPOSITORY}/actions/variables/\${name}\" >/dev/null 2>&1 || true" "article workflow deletes variables when asked to persist an empty value"
assert_contains "${ARTICLE_WORKFLOW}" "upsert_var \"LINE_NOTE_ARTICLE_PENDING_ID\" \"\"" "article workflow still clears legacy pending article id via delete semantics"
assert_contains "${ARTICLE_WORKFLOW}" "upsert_var \"LINE_NOTE_ARTICLE_PENDING_AT\" \"\"" "article workflow still clears legacy pending timestamp via delete semantics"
assert_contains "${VALUE_WORKFLOW}" "LINE_LAST_VALUE_SHARE_SENT_INDEX" "value workflow persists last sent rotation index"
assert_contains "${VALUE_WORKFLOW}" "skip_duplicate" "value workflow exposes duplicate guard output"
assert_contains "${VALUE_WORKFLOW}" "Heal rotation index after duplicate guard" "value workflow heals stale rotation index"
assert_contains "${VALUE_WORKFLOW}" "build_retry_key" "value workflow builds deterministic LINE retry key"
assert_contains "${VALUE_WORKFLOW}" "LINE broadcast request was already accepted for retry key" "value workflow handles duplicate retry-key acceptance"
assert_contains "${VALUE_WORKFLOW}" "Pause delivery after ambiguous broadcast state" "value workflow pauses on ambiguous receipt persistence"
assert_contains "${VALUE_WORKFLOW}" "Skipping initialization for \${name} because GitHub Variables cannot store empty strings." "value workflow skips empty variable initialization"
assert_contains "${VALUE_WORKFLOW}" "gh api -X DELETE \"repos/\${GITHUB_REPOSITORY}/actions/variables/\${name}\" >/dev/null 2>&1 || true" "value workflow deletes variables when clearing empty state"
assert_contains "${VALUE_WORKFLOW}" "Failed to read GitHub variable \${name}" "value workflow fails on unexpected variable read errors"
assert_contains "${VALUE_WORKFLOW}" "HTTP 404|Not Found" "value workflow treats deleted optional variables as empty"
assert_contains "${VALUE_WORKFLOW}" "upsert_var \"LINE_VALUE_SHARE_PENDING_INDEX\" \"\${CURRENT_INDEX}\"" "value workflow still creates prepared rotation lock"
assert_contains "${VALUE_WORKFLOW}" "|| gh api -X POST \"repos/\${GITHUB_REPOSITORY}/actions/variables\"" "value workflow creates missing GitHub variables when reserving state"
assert_contains "${VALUE_WORKFLOW}" "clear_var \"LINE_VALUE_SHARE_PENDING_INDEX\"" "value workflow clears success lock via delete semantics"

if (( failures > 0 )); then
  exit 1
fi

echo "line delivery dedup guard check passed"
