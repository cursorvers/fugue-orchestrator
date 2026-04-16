#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT_DIR}/scripts/local/integrations/xauto-blocked-recovery.sh"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

cat > "${TMP_DIR}/registry.json" <<'JSON'
[
  {
    "cursorvers_post_id": "cur-9",
    "source_url": "https://x.com/z/status/999",
    "author_handle": "zeta",
    "display_name": "Zeta",
    "topic_tags": ["medical", "clinical"],
    "conclusion_tag": "agreement",
    "pattern_tag": "quoted",
    "metadata": {
      "confidence": 0.88
    }
  }
]
JSON

cat > "${TMP_DIR}/draft-result.json" <<'JSON'
{
  "blocked": [
    {
      "draft_id": "draft-zeta",
      "source_url": "https://x.com/z/status/999",
      "quoted_author_handle": "zeta",
      "blocked_reason_canonical": "missing-non-x-primary-source"
    }
  ],
  "closeout": {
    "backfill_targets": [
      {
        "draft_id": "draft-zeta",
        "source_url": "https://x.com/z/status/999",
        "quoted_author_handle": "zeta"
      }
    ]
  }
}
JSON

mkdir -p "${TMP_DIR}/recovery-posts"
cat > "${TMP_DIR}/recovery-posts/zeta.json" <<'JSON'
[
  {
    "id": "zeta-1",
    "author_id": "author-zeta",
    "conversation_id": "thread-zeta",
    "text": "same source thread",
    "created_at": "2026-04-02T00:00:00Z",
    "entities": {
      "urls": [
        {"expanded_url": "https://x.com/z/status/999"}
      ]
    },
    "referenced_tweets": [
      {"type": "quoted", "id": "999"}
    ]
  },
  {
    "id": "999",
    "author_id": "author-src",
    "conversation_id": "thread-src",
    "text": "external source",
    "created_at": "2026-04-01T23:00:00Z",
    "entities": {
      "urls": [
        {"expanded_url": "https://example.com/recovered-article"}
      ]
    }
  }
]
JSON

RESULT="$(
  bash "${SCRIPT}" \
    --mode execute \
    --draft-result-input "${TMP_DIR}/draft-result.json" \
    --registry-input "${TMP_DIR}/registry.json" \
    --extract-mode heuristic \
    --generate-mode heuristic \
    --only-reason missing-non-x-primary-source \
    --max-candidates 1 \
    --min-chars 800 \
    --run-dir "${TMP_DIR}/run" \
    --recovery-posts-seed-dir "${TMP_DIR}/recovery-posts"
)"

printf '%s\n' "${RESULT}" | jq -e '.recovery.attempted_count == 1' >/dev/null
printf '%s\n' "${RESULT}" | jq -e '.recovery.recovered_count == 1' >/dev/null
printf '%s\n' "${RESULT}" | jq -e '.rerun_result.promotable | length == 1' >/dev/null
printf '%s\n' "${RESULT}" | jq -e '.rerun_result.promotable[0].quoted_author_handle == "zeta"' >/dev/null
printf '%s\n' "${RESULT}" | jq -e '.rerun_result.promotable[0].category == "医療AIガバナンス"' >/dev/null
test -f "${TMP_DIR}/run/xauto-blocked-recovery.registry.json"
test -f "${TMP_DIR}/run/xauto-blocked-recovery.result.json"
