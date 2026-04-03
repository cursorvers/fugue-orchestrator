#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "GITHUB_REPOSITORY is required." >&2
  exit 1
fi

delete_var() {
  local name="$1"
  gh api -X DELETE "repos/${GITHUB_REPOSITORY}/actions/variables/${name}" >/dev/null 2>&1 || true
}

delete_var "LINE_NOTE_ARTICLE_PENDING_ID"
delete_var "LINE_NOTE_ARTICLE_PENDING_AT"
delete_var "LINE_NOTE_ARTICLE_PENDING_STATE"
delete_var "LINE_NOTE_ARTICLE_PENDING_REQUEST_ID"

cat <<EOF
Deleted LINE_NOTE_ARTICLE_PENDING_* variables for ${GITHUB_REPOSITORY}
Note: line-send-note-article now claims delivery in Supabase via claim_article_for_line_delivery.
These variables are retained for audit compatibility and no longer control send eligibility.
EOF
