#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT_DIR}/scripts/local/integrations/xauto_quoted_author_sync.py"
ADAPTER="${ROOT_DIR}/scripts/local/integrations/xauto-quoted-author-sync.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

POSTS_SEED="${TMP_DIR}/posts.json"
RECORDS_SEED="${TMP_DIR}/records.json"
cat > "${POSTS_SEED}" <<'JSON'
[
  {
    "id": "cur-1",
    "text": "see this",
    "created_at": "2026-04-01T00:00:00Z",
    "entities": {
      "urls": [
        {"expanded_url": "https://x.com/example/status/111"}
      ]
    },
    "referenced_tweets": [
      {"type": "quoted", "id": "111"}
    ]
  },
  {
    "id": "111",
    "author_id": "user-1",
    "conversation_id": "thread-1",
    "text": "quoted source",
    "created_at": "2026-03-31T00:00:00Z",
    "entities": {
      "urls": [
        {"expanded_url": "https://example.com/source-article"}
      ]
    }
  },
  {
    "id": "cur-2",
    "text": "same thread child",
    "created_at": "2026-04-01T01:00:00Z",
    "entities": {
      "urls": [
        {"expanded_url": "https://x.com/example/status/222"}
      ]
    },
    "referenced_tweets": [
      {"type": "quoted", "id": "222"}
    ]
  },
  {
    "id": "222",
    "author_id": "user-2",
    "conversation_id": "thread-2",
    "text": "thread child without external url",
    "created_at": "2026-04-01T00:30:00Z",
    "entities": {
      "urls": []
    }
  },
  {
    "id": "thread-2",
    "author_id": "user-2",
    "conversation_id": "thread-2",
    "text": "thread head with article",
    "created_at": "2026-04-01T00:00:00Z",
    "entities": {
      "urls": [
        {"expanded_url": "https://example.com/thread-article"}
      ]
    }
  },
  {
    "id": "cur-3",
    "text": "deep reference chain",
    "created_at": "2026-04-01T02:00:00Z",
    "entities": {
      "urls": [
        {"expanded_url": "https://x.com/example/status/333"}
      ]
    },
    "referenced_tweets": [
      {"type": "quoted", "id": "333"}
    ]
  },
  {
    "id": "333",
    "author_id": "user-3",
    "conversation_id": "thread-3",
    "text": "level one",
    "created_at": "2026-04-01T01:30:00Z",
    "entities": {"urls": []},
    "referenced_tweets": [
      {"type": "quoted", "id": "444"}
    ]
  },
  {
    "id": "444",
    "author_id": "user-3",
    "conversation_id": "thread-3",
    "text": "level two",
    "created_at": "2026-04-01T01:20:00Z",
    "entities": {"urls": []},
    "referenced_tweets": [
      {"type": "quoted", "id": "555"}
    ]
  },
  {
    "id": "555",
    "author_id": "user-3",
    "conversation_id": "thread-3",
    "text": "level three",
    "created_at": "2026-04-01T01:10:00Z",
    "entities": {"urls": []},
    "referenced_tweets": [
      {"type": "quoted", "id": "666"}
    ]
  },
  {
    "id": "666",
    "author_id": "user-3",
    "conversation_id": "thread-3",
    "text": "level four article",
    "created_at": "2026-04-01T01:00:00Z",
    "entities": {
      "urls": [
        {"expanded_url": "https://example.com/deep-article"}
      ]
    }
  }
]
JSON

cat > "${RECORDS_SEED}" <<'JSON'
[
  {
    "cursorvers_post_id": "cur-2",
    "source_url": "https://x.com/example/status/111",
    "author_handle": "@MedDX_Innovator",
    "topic_tags": ["medical AI", "governance", "local LLM"],
    "conclusion_tag": "local LLM optimal for governed medical AI",
    "pattern_tag": "supportive-endorsement",
    "metadata": {"confidence": 0.9}
  }
]
JSON

OUT="${TMP_DIR}/out.json"
python3 "${HELPER}" --posts-seed-input "${POSTS_SEED}" --extract-mode heuristic --handle cursorvers > "${OUT}"

jq -e 'map(select(.source_url == "https://x.com/example/status/111" and .metadata.primary_source_url == "https://example.com/source-article")) | length == 1' "${OUT}" >/dev/null
jq -e 'map(select(.source_url == "https://x.com/example/status/222" and .metadata.primary_source_url == "https://example.com/thread-article")) | length == 1' "${OUT}" >/dev/null
jq -e 'map(select(.source_url == "https://x.com/example/status/222" and .metadata.primary_source_strategy == "author-conversation")) | length == 1' "${OUT}" >/dev/null
jq -e 'map(select(.source_url == "https://x.com/example/status/333" and .metadata.primary_source_url == "https://example.com/deep-article")) | length == 1' "${OUT}" >/dev/null
jq -e 'map(select(.source_url == "https://x.com/example/status/333" and .metadata.primary_source_strategy == "quoted-reference")) | length == 1' "${OUT}" >/dev/null

NORM_OUT="${TMP_DIR}/norm.json"
python3 - <<'PY' "${RECORDS_SEED}" "${POSTS_SEED}" > "${NORM_OUT}"
import json
import sys
from scripts.local.integrations import xauto_quoted_author_sync as s

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    records = json.load(fh)
with open(sys.argv[2], "r", encoding="utf-8") as fh:
    posts = json.load(fh)
print(json.dumps(s.postprocess_records(records, posts), ensure_ascii=False))
PY

jq -e '.[0].author_handle == "meddx_innovator"' "${NORM_OUT}" >/dev/null
jq -e '.[0].conclusion_tag == "local_llm_recommended"' "${NORM_OUT}" >/dev/null
jq -e '.[0].pattern_tag == "quoted_agreement"' "${NORM_OUT}" >/dev/null
jq -e '.[0].topic_tags == ["medical-ai","governance","local-llm"]' "${NORM_OUT}" >/dev/null

env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u SUPABASE_ACCESS_TOKEN \
bash "${ADAPTER}" \
  --mode smoke \
  --seed-input "${NORM_OUT}" \
  --run-dir "${TMP_DIR}/adapter-run" >/dev/null

grep -Fq "primary_source_url" "${TMP_DIR}/adapter-run/xauto-quoted-author-sync.sql"
grep -Fq "on conflict (event_hash) do nothing" "${TMP_DIR}/adapter-run/xauto-quoted-author-sync.sql"
grep -Fq "source_type" "${TMP_DIR}/adapter-run/xauto-quoted-author-sync.sql"

echo "xauto quoted author sync enrichment check passed"
