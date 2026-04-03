#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "GITHUB_REPOSITORY is required." >&2
  exit 1
fi

upsert_var() {
  local name="$1"
  local value="$2"
  { gh api -X PATCH "repos/${GITHUB_REPOSITORY}/actions/variables/${name}" \
      -f name="${name}" -f value="${value}" >/dev/null 2>&1 \
    || gh api -X POST "repos/${GITHUB_REPOSITORY}/actions/variables" \
      -f name="${name}" -f value="${value}" >/dev/null 2>&1; }
}

upsert_var "LINE_NOTE_ARTICLE_PENDING_ID" ""
upsert_var "LINE_NOTE_ARTICLE_PENDING_AT" ""
upsert_var "LINE_NOTE_ARTICLE_PENDING_STATE" ""
upsert_var "LINE_NOTE_ARTICLE_PENDING_REQUEST_ID" ""

echo "Cleared LINE_NOTE_ARTICLE_PENDING_* variables for ${GITHUB_REPOSITORY}"
