#!/usr/bin/env bash
set -euo pipefail

MODE="smoke"
RUN_DIR=""
SEED_INPUT="${X_AUTO_QUOTED_AUTHOR_SYNC_SEED_INPUT:-}"
POSTS_SEED_INPUT="${X_AUTO_QUOTED_AUTHOR_SYNC_POSTS_SEED_INPUT:-}"
X_HANDLE="${X_AUTO_QUOTED_AUTHOR_SYNC_HANDLE:-cursorvers}"
FETCH_LIMIT="${X_AUTO_QUOTED_AUTHOR_SYNC_LIMIT:-50}"
FROM_DATE="${X_AUTO_QUOTED_AUTHOR_SYNC_FROM_DATE:-}"
TO_DATE="${X_AUTO_QUOTED_AUTHOR_SYNC_TO_DATE:-}"
EXTRACT_MODE="${X_AUTO_QUOTED_AUTHOR_SYNC_EXTRACT_MODE:-auto}" # auto|xai|heuristic
WRITE_MODE="${X_AUTO_QUOTED_AUTHOR_SYNC_WRITE_MODE:-best-effort}" # off|best-effort|required
HELPER_SCRIPT=""

usage() {
  cat <<'EOF'
Usage: xauto-quoted-author-sync.sh [options]

Options:
  --mode <smoke|execute>   Run mode (default: smoke)
  --run-dir <path>         FUGUE run directory (optional)
  --seed-input <path>      Optional JSON array used for deterministic dry runs
  --posts-seed-input <path> Optional raw post JSON array for deterministic extraction tests
  --handle <x-handle>      X handle to inspect (default: cursorvers)
  --limit <n>              Max post count to inspect when fetching via X API
  --from-date <YYYY-MM-DD> Optional inclusive start date for X API fetch
  --to-date <YYYY-MM-DD>   Optional inclusive end date for X API fetch
  --extract-mode <mode>    auto|xai|heuristic (default: auto)
  -h, --help               Show help

Environment:
  X_AUTO_QUOTED_AUTHOR_SYNC_WRITE_MODE=off|best-effort|required
                           Control whether execute mode attempts Supabase writes.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --run-dir)
      RUN_DIR="${2:-}"
      shift 2
      ;;
    --seed-input)
      SEED_INPUT="${2:-}"
      shift 2
      ;;
    --posts-seed-input)
      POSTS_SEED_INPUT="${2:-}"
      shift 2
      ;;
    --handle)
      X_HANDLE="${2:-}"
      shift 2
      ;;
    --limit)
      FETCH_LIMIT="${2:-}"
      shift 2
      ;;
    --from-date)
      FROM_DATE="${2:-}"
      shift 2
      ;;
    --to-date)
      TO_DATE="${2:-}"
      shift 2
      ;;
    --extract-mode)
      EXTRACT_MODE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${MODE}" != "smoke" && "${MODE}" != "execute" ]]; then
  echo "Error: --mode must be smoke|execute" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HELPER_SCRIPT="${ROOT_DIR}/scripts/local/integrations/xauto_quoted_author_sync.py"

command -v curl >/dev/null 2>&1 || { echo "xauto-quoted-author-sync: curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "xauto-quoted-author-sync: jq is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "xauto-quoted-author-sync: python3 is required" >&2; exit 1; }
[[ -f "${HELPER_SCRIPT}" ]] || { echo "xauto-quoted-author-sync: missing helper script: ${HELPER_SCRIPT}" >&2; exit 1; }
if [[ -n "${SEED_INPUT}" ]]; then
  [[ -f "${SEED_INPUT}" ]] || { echo "xauto-quoted-author-sync: missing seed input: ${SEED_INPUT}" >&2; exit 1; }
fi
if [[ -n "${POSTS_SEED_INPUT}" ]]; then
  [[ -f "${POSTS_SEED_INPUT}" ]] || { echo "xauto-quoted-author-sync: missing posts seed input: ${POSTS_SEED_INPUT}" >&2; exit 1; }
fi
if ! [[ "${FETCH_LIMIT}" =~ ^[0-9]+$ ]] || (( FETCH_LIMIT < 1 )); then
  echo "xauto-quoted-author-sync: --limit must be an integer >= 1" >&2
  exit 2
fi
if [[ "${EXTRACT_MODE}" != "auto" && "${EXTRACT_MODE}" != "xai" && "${EXTRACT_MODE}" != "heuristic" ]]; then
  echo "xauto-quoted-author-sync: --extract-mode must be auto|xai|heuristic" >&2
  exit 2
fi

to_bool_env() {
  local v
  v="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  if [[ "${v}" == "true" || "${v}" == "1" || "${v}" == "yes" || "${v}" == "on" ]]; then
    printf '%s' "true"
  else
    printf '%s' "false"
  fi
}

normalize_url() {
  local raw="${1:-}"
  if [[ -z "${raw}" ]]; then
    printf '%s' ""
    return 0
  fi
  python3 - "${raw}" <<'PY'
import sys
from urllib.parse import urlparse, urlunparse

raw = sys.argv[1].strip()
if not raw:
    print("")
    raise SystemExit(0)

parsed = urlparse(raw)
scheme = (parsed.scheme or "https").lower()
netloc = parsed.netloc.lower()
path = parsed.path.rstrip("/")
if not path:
    path = "/"
print(urlunparse((scheme, netloc, path, "", "", "")))
PY
}

normalize_handle() {
  local raw="${1:-}"
  raw="$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^@+//; s/^[[:space:]]+|[[:space:]]+$//g')"
  printf '%s' "${raw}"
}

extract_url_domain() {
  local raw="${1:-}"
  python3 - "${raw}" <<'PY'
import sys
from urllib.parse import urlparse

raw = sys.argv[1].strip()
if not raw:
    print("")
    raise SystemExit(0)

parsed = urlparse(raw)
print((parsed.netloc or "").lower())
PY
}

uuid5_from_text() {
  local namespace="$1"
  local value="$2"
  python3 - "${namespace}" "${value}" <<'PY'
import sys
import uuid

namespace = uuid.UUID(sys.argv[1])
value = sys.argv[2]
print(str(uuid.uuid5(namespace, value)))
PY
}

derive_project_ref_from_service_role() {
  local token="${SUPABASE_SERVICE_ROLE_KEY:-}"
  if [[ -z "${token}" ]]; then
    printf '%s' ""
    return 0
  fi
  python3 - "${token}" <<'PY'
import base64
import json
import sys

token = sys.argv[1]
parts = token.split(".")
if len(parts) < 2:
    print("")
    raise SystemExit(0)
payload = parts[1]
payload += "=" * (-len(payload) % 4)
try:
    data = json.loads(base64.urlsafe_b64decode(payload.encode()).decode())
except Exception:
    print("")
    raise SystemExit(0)
print(data.get("ref", ""))
PY
}

derive_supabase_url() {
  if [[ -n "${SUPABASE_URL:-}" ]]; then
    printf '%s' "${SUPABASE_URL}"
    return 0
  fi
  local ref
  ref="$(derive_project_ref_from_service_role)"
  if [[ -n "${ref}" ]]; then
    printf 'https://%s.supabase.co' "${ref}"
    return 0
  fi
  printf '%s' ""
}

postgrest_request() {
  local method="$1"
  local url="$2"
  local payload_file="${3:-}"
  local prefer="${4:-return=minimal}"
  local output_file="$5"
  if [[ -n "${payload_file}" ]]; then
    curl -sS -o "${output_file}" -w '%{http_code}' -X "${method}" "${url}" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Content-Type: application/json" \
      -H "Prefer: ${prefer}" \
      --data @"${payload_file}"
  else
    curl -sS -o "${output_file}" -w '%{http_code}' -X "${method}" "${url}" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
      -H "Prefer: ${prefer}"
  fi
}

json_escape_sql() {
  printf "%s" "${1}" | sed "s/'/''/g"
}

base64_decode() {
  if base64 --help >/dev/null 2>&1; then
    base64 --decode
  else
    base64 -D
  fi
}

seed_json='[]'
if [[ -n "${SEED_INPUT}" ]]; then
  seed_json="$(cat "${SEED_INPUT}")"
else
  helper_args=(
    "${HELPER_SCRIPT}"
    --handle "${X_HANDLE}"
    --limit "${FETCH_LIMIT}"
    --extract-mode "${EXTRACT_MODE}"
  )
  if [[ -n "${FROM_DATE}" ]]; then
    helper_args+=(--from-date "${FROM_DATE}")
  fi
  if [[ -n "${TO_DATE}" ]]; then
    helper_args+=(--to-date "${TO_DATE}")
  fi
  if [[ -n "${POSTS_SEED_INPUT}" ]]; then
    helper_args+=(--posts-seed-input "${POSTS_SEED_INPUT}")
  fi
  seed_json="$(python3 "${helper_args[@]}")"
fi

normalized_json="$(
  printf '%s' "${seed_json}" | jq -c '
    if type == "array" then . else [] end
    | map({
        notion_page_id: (.notion_page_id // ""),
        cursorvers_post_id: (.cursorvers_post_id // ""),
        source_url: (.source_url // .url // ""),
        author_handle: (.author_handle // .canonical_handle // .author // ""),
        display_name: (.display_name // ""),
        topic_tags: ((.topic_tags // []) | if type == "array" then map(tostring) else [] end),
        conclusion_tag: (.conclusion_tag // ""),
        pattern_tag: (.pattern_tag // ""),
        metadata: (.metadata // {})
      })
    | map(select(.source_url != ""))
  '
)"

tmp_dir=""
if [[ -n "${RUN_DIR}" ]]; then
  mkdir -p "${RUN_DIR}"
  tmp_dir="${RUN_DIR}"
else
  tmp_dir="$(mktemp -d)"
fi

result_path="${tmp_dir}/xauto-quoted-author-sync.result.json"
sql_path="${tmp_dir}/xauto-quoted-author-sync.sql"
meta_path="${tmp_dir}/xauto-quoted-author-sync.meta"
bridge_response_path="${tmp_dir}/xauto-quoted-author-sync.bridge.json"

authors_json='[]'
sources_json='[]'
events_json='[]'
AUTHOR_NAMESPACE_UUID="e8c35f15-7f08-4c18-a807-bb349a5c2f9c"
SOURCE_NAMESPACE_UUID="bd8934d2-a4d0-4714-8b12-0c79de147f97"
EVENT_NAMESPACE_UUID="2ef52b4d-d770-45a3-8c78-d10b010e9085"
CURRENT_TS_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

while IFS= read -r item; do
  source_url="$(printf '%s' "${item}" | jq -r '.source_url // ""')"
  author_handle="$(printf '%s' "${item}" | jq -r '.author_handle // ""')"
  display_name="$(printf '%s' "${item}" | jq -r '.display_name // ""')"
  notion_page_id="$(printf '%s' "${item}" | jq -r '.notion_page_id // ""')"
  cursorvers_post_id="$(printf '%s' "${item}" | jq -r '.cursorvers_post_id // ""')"
  event_kind="$(printf '%s' "${item}" | jq -r '.event_kind // (.metadata.event_kind // "discovered")')"
  conclusion_tag="$(printf '%s' "${item}" | jq -r '.conclusion_tag // ""')"
  pattern_tag="$(printf '%s' "${item}" | jq -r '.pattern_tag // ""')"
  topic_tags="$(printf '%s' "${item}" | jq -c '.topic_tags // []')"
  metadata="$(printf '%s' "${item}" | jq -c '.metadata // {}')"

  normalized_source_url="$(normalize_url "${source_url}")"
  normalized_handle="$(normalize_handle "${author_handle}")"

  source_hash="$(printf '%s' "${normalized_source_url}" | shasum -a 256 | awk '{print $1}')"
  if [[ -n "${normalized_handle}" ]]; then
    author_key="$(printf '%s' "x:${normalized_handle}" | shasum -a 256 | awk '{print $1}')"
  else
    author_key="$(printf '%s' "x:unknown:${source_hash}" | shasum -a 256 | awk '{print $1}')"
  fi
  author_id="$(uuid5_from_text "${AUTHOR_NAMESPACE_UUID}" "${author_key}")"
  source_id="$(uuid5_from_text "${SOURCE_NAMESPACE_UUID}" "${source_hash}")"
  event_hash="$(printf '%s' "${event_kind}|${notion_page_id}|${cursorvers_post_id}|${source_hash}|${author_key}|${conclusion_tag}|${pattern_tag}" | shasum -a 256 | awk '{print $1}')"
  event_id="$(uuid5_from_text "${EVENT_NAMESPACE_UUID}" "${event_hash}")"

  authors_json="$(
    jq -c \
      --arg author_id "${author_id}" \
      --arg normalized_key "${author_key}" \
      --arg canonical_handle "${normalized_handle}" \
      --arg display_name "${display_name}" \
      --arg current_ts "${CURRENT_TS_UTC}" \
      '
        . + [{
          author_id: $author_id,
          platform: "x",
          normalized_key: $normalized_key,
          canonical_handle: $canonical_handle,
          display_name: $display_name,
          last_seen_at: $current_ts
        }]
      ' <<< "${authors_json}"
  )"

  sources_json="$(
    jq -c \
      --arg source_id "${source_id}" \
      --arg normalized_source_url "${normalized_source_url}" \
      --arg source_hash "${source_hash}" \
      --arg source_url "${source_url}" \
      --arg source_domain "$(extract_url_domain "${normalized_source_url}")" \
      --arg author_id "${author_id}" \
      --arg author_key "${author_key}" \
      --argjson metadata "${metadata}" \
      '
        . + [{
          source_id: $source_id,
          normalized_source_url: $normalized_source_url,
          source_hash: $source_hash,
          source_url: $source_url,
          source_domain: $source_domain,
          source_type: (if ($normalized_source_url | test("https?://(x|twitter)\\.com/"; "i")) then "x-post" else "external" end),
          author_id: $author_id,
          author_key: $author_key,
          metadata: $metadata
        }]
      ' <<< "${sources_json}"
  )"

  events_json="$(
    jq -c \
      --arg event_id "${event_id}" \
      --arg event_hash "${event_hash}" \
      --arg notion_page_id "${notion_page_id}" \
      --arg cursorvers_post_id "${cursorvers_post_id}" \
      --arg author_id "${author_id}" \
      --arg author_key "${author_key}" \
      --arg source_id "${source_id}" \
      --arg source_hash "${source_hash}" \
      --arg event_kind "${event_kind}" \
      --arg conclusion_tag "${conclusion_tag}" \
      --arg pattern_tag "${pattern_tag}" \
      --argjson topic_tags "${topic_tags}" \
      --argjson metadata "${metadata}" \
      '
        . + [{
          event_id: $event_id,
          event_hash: $event_hash,
          notion_page_id: $notion_page_id,
          cursorvers_post_id: $cursorvers_post_id,
          author_id: $author_id,
          author_key: $author_key,
          source_id: $source_id,
          source_hash: $source_hash,
          event_kind: $event_kind,
          topic_tags: $topic_tags,
          conclusion_tag: $conclusion_tag,
          pattern_tag: $pattern_tag,
          metadata: $metadata
        }]
      ' <<< "${events_json}"
  )"
done < <(printf '%s' "${normalized_json}" | jq -c '.[]')

authors_json="$(printf '%s' "${authors_json}" | jq -c 'unique_by(.normalized_key)')"
sources_json="$(printf '%s' "${sources_json}" | jq -c 'unique_by(.source_hash)')"
events_json="$(printf '%s' "${events_json}" | jq -c 'unique_by(.event_hash)')"

jq -n \
  --arg mode "${MODE}" \
  --arg issue_title "${FUGUE_ISSUE_TITLE:-}" \
  --arg issue_url "${FUGUE_ISSUE_URL:-}" \
  --arg write_mode "${WRITE_MODE}" \
  --argjson authors "${authors_json}" \
  --argjson sources "${sources_json}" \
  --argjson events "${events_json}" \
  '{
    system: "x-auto-quoted-author-sync",
    mode: $mode,
    write_mode: $write_mode,
    issue_title: $issue_title,
    issue_url: $issue_url,
    authors: $authors,
    sources: $sources,
    events: $events
  }' > "${result_path}"

{
  printf '%s\n' "-- x-auto quoted author sync generated SQL"
  printf '%s\n' "-- generated_at_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\n' ""
  printf '%s' "${authors_json}" | jq -r '.[] | @base64' | while IFS= read -r row; do
    obj="$(printf '%s' "${row}" | base64_decode)"
    author_id="$(printf '%s' "${obj}" | jq -r '.author_id')"
    normalized_key="$(printf '%s' "${obj}" | jq -r '.normalized_key')"
    canonical_handle="$(printf '%s' "${obj}" | jq -r '.canonical_handle')"
    display_name="$(printf '%s' "${obj}" | jq -r '.display_name')"
    printf "insert into public.quoted_authors (author_id, platform, canonical_handle, display_name, normalized_key, first_seen_at, last_seen_at)\n"
    printf "values ('%s', 'x', '%s', %s, '%s', now(), now())\n" \
      "$(json_escape_sql "${author_id}")" \
      "$(json_escape_sql "${canonical_handle}")" \
      "$([[ -n "${display_name}" ]] && printf "'%s'" "$(json_escape_sql "${display_name}")" || printf "null")" \
      "$(json_escape_sql "${normalized_key}")"
    printf "on conflict (platform, normalized_key) do update set canonical_handle = excluded.canonical_handle, display_name = coalesce(excluded.display_name, public.quoted_authors.display_name), last_seen_at = now();\n\n"
  done
  printf '%s' "${sources_json}" | jq -r '.[] | @base64' | while IFS= read -r row; do
    obj="$(printf '%s' "${row}" | base64_decode)"
    source_id="$(printf '%s' "${obj}" | jq -r '.source_id')"
    source_url="$(printf '%s' "${obj}" | jq -r '.source_url')"
    normalized_source_url="$(printf '%s' "${obj}" | jq -r '.normalized_source_url')"
    source_hash="$(printf '%s' "${obj}" | jq -r '.source_hash')"
    source_domain="$(printf '%s' "${obj}" | jq -r '.source_domain')"
    source_type="$(printf '%s' "${obj}" | jq -r '.source_type')"
    author_id="$(printf '%s' "${obj}" | jq -r '.author_id')"
    author_key="$(printf '%s' "${obj}" | jq -r '.author_key')"
    metadata_literal="$(printf '%s' "${obj}" | jq -c '.metadata // {}')"
    printf "insert into public.quoted_sources (source_id, author_id, source_url, normalized_source_url, source_type, source_domain, source_hash, metadata, created_at)\n"
    printf "select '%s', a.author_id, '%s', '%s', '%s', %s, '%s', '%s'::jsonb, now()\n" \
      "$(json_escape_sql "${source_id}")" \
      "$(json_escape_sql "${source_url}")" \
      "$(json_escape_sql "${normalized_source_url}")" \
      "$(json_escape_sql "${source_type}")" \
      "$([[ -n "${source_domain}" ]] && printf "'%s'" "$(json_escape_sql "${source_domain}")" || printf "null")" \
      "$(json_escape_sql "${source_hash}")" \
      "$(json_escape_sql "${metadata_literal}")"
    printf "from public.quoted_authors a\n"
    printf "where a.platform = 'x' and a.normalized_key = '%s'\n" "$(json_escape_sql "${author_key}")"
    printf "union all\n"
    printf "select '%s', '%s', '%s', '%s', %s, '%s', '%s'::jsonb, now()\n" \
      "$(json_escape_sql "${source_id}")" \
      "$(json_escape_sql "${author_id}")" \
      "$(json_escape_sql "${source_url}")" \
      "$(json_escape_sql "${normalized_source_url}")" \
      "$(json_escape_sql "${source_type}")" \
      "$([[ -n "${source_domain}" ]] && printf "'%s'" "$(json_escape_sql "${source_domain}")" || printf "null")" \
      "$(json_escape_sql "${source_hash}")" \
      "$(json_escape_sql "${metadata_literal}")"
    printf "where not exists (select 1 from public.quoted_authors a where a.platform = 'x' and a.normalized_key = '%s')\n" "$(json_escape_sql "${author_key}")"
    printf "on conflict (normalized_source_url) do update set source_url = excluded.source_url, source_domain = coalesce(excluded.source_domain, public.quoted_sources.source_domain), source_type = excluded.source_type, metadata = public.quoted_sources.metadata || excluded.metadata;\n\n"
  done
  printf '%s' "${events_json}" | jq -r '.[] | @base64' | while IFS= read -r row; do
    obj="$(printf '%s' "${row}" | base64_decode)"
    event_id="$(printf '%s' "${obj}" | jq -r '.event_id')"
    event_hash="$(printf '%s' "${obj}" | jq -r '.event_hash')"
    notion_page_id="$(printf '%s' "${obj}" | jq -r '.notion_page_id')"
    cursorvers_post_id="$(printf '%s' "${obj}" | jq -r '.cursorvers_post_id')"
    author_id="$(printf '%s' "${obj}" | jq -r '.author_id')"
    author_key="$(printf '%s' "${obj}" | jq -r '.author_key')"
    source_id="$(printf '%s' "${obj}" | jq -r '.source_id')"
    source_hash="$(printf '%s' "${obj}" | jq -r '.source_hash')"
    event_kind="$(printf '%s' "${obj}" | jq -r '.event_kind')"
    topic_tags_literal="$(printf '%s' "${obj}" | jq -r '(.topic_tags // []) | @json')"
    conclusion_tag="$(printf '%s' "${obj}" | jq -r '.conclusion_tag')"
    pattern_tag="$(printf '%s' "${obj}" | jq -r '.pattern_tag')"
    metadata_literal="$(printf '%s' "${obj}" | jq -c '.metadata // {}')"
    printf "insert into public.quote_events (event_id, event_hash, source_id, author_id, notion_page_id, cursorvers_post_id, event_kind, topic_tags, conclusion_tag, pattern_tag, context)\n"
    printf "select '%s', '%s', s.source_id, a.author_id, %s, %s, '%s', '%s'::jsonb, %s, %s, '%s'::jsonb\n" \
      "$(json_escape_sql "${event_id}")" \
      "$(json_escape_sql "${event_hash}")" \
      "$([[ -n "${notion_page_id}" ]] && printf "'%s'" "$(json_escape_sql "${notion_page_id}")" || printf "null")" \
      "$([[ -n "${cursorvers_post_id}" ]] && printf "'%s'" "$(json_escape_sql "${cursorvers_post_id}")" || printf "null")" \
      "$(json_escape_sql "${event_kind}")" \
      "$(json_escape_sql "${topic_tags_literal}")" \
      "$([[ -n "${conclusion_tag}" ]] && printf "'%s'" "$(json_escape_sql "${conclusion_tag}")" || printf "null")" \
      "$([[ -n "${pattern_tag}" ]] && printf "'%s'" "$(json_escape_sql "${pattern_tag}")" || printf "null")" \
      "$(json_escape_sql "${metadata_literal}")"
    printf "from public.quoted_sources s\n"
    printf "left join public.quoted_authors a on a.platform = 'x' and a.normalized_key = '%s'\n" "$(json_escape_sql "${author_key}")"
    printf "where s.source_hash = '%s' and s.source_id = '%s'\n" "$(json_escape_sql "${source_hash}")" "$(json_escape_sql "${source_id}")"
    printf "on conflict (event_hash) do nothing;\n\n"
  done
} > "${sql_path}"

bridge_status="not-attempted"
bridge_http="n/a"
supabase_url="$(derive_supabase_url)"
schema_probe_http="n/a"
schema_probe_file="${tmp_dir}/xauto-quoted-author-sync.schema.json"
authors_payload_path="${tmp_dir}/xauto-quoted-author-sync.authors.payload.json"
sources_payload_path="${tmp_dir}/xauto-quoted-author-sync.sources.payload.json"
events_payload_path="${tmp_dir}/xauto-quoted-author-sync.events.payload.json"

printf '%s' "${authors_json}" | jq -c --arg current_ts "${CURRENT_TS_UTC}" '
  map(
    {
      author_id,
      platform,
      normalized_key,
      canonical_handle,
      display_name,
      last_seen_at: $current_ts
    }
    | with_entries(select(.value != null and .value != ""))
  )
' > "${authors_payload_path}"

printf '%s' "${sources_json}" | jq -c '
  map(
    {
      source_id,
      author_id,
      source_url,
      normalized_source_url,
      source_type,
      source_domain,
      source_hash,
      metadata
    }
    | with_entries(select(.value != null and .value != ""))
  )
' > "${sources_payload_path}"

printf '%s' "${events_json}" | jq -c '
  map(
    {
      event_id,
      event_hash,
      source_id,
      author_id,
      notion_page_id,
      cursorvers_post_id,
      event_kind,
      topic_tags,
      conclusion_tag,
      pattern_tag,
      context: .metadata
    }
    | with_entries(select(.value != null and .value != ""))
  )
' > "${events_payload_path}"

if [[ "${MODE}" == "smoke" ]]; then
  if [[ -n "${supabase_url}" && -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    schema_probe_http="$(postgrest_request "GET" "${supabase_url}/rest/v1/quoted_authors?select=author_id&limit=1" "" "return=minimal" "${schema_probe_file}")"
    bridge_http="${schema_probe_http}"
    if [[ "${schema_probe_http}" == "200" || "${schema_probe_http}" == "206" ]]; then
      bridge_status="smoke-ok"
    elif [[ "${schema_probe_http}" == "404" ]]; then
      bridge_status="schema-missing"
    else
      bridge_status="smoke-error"
    fi
  else
    bridge_status="skipped-missing-creds"
  fi
else
  should_write="false"
  case "${WRITE_MODE}" in
    off)
      should_write="false"
      ;;
    best-effort|required)
      should_write="true"
      ;;
    *)
      echo "xauto-quoted-author-sync: invalid write mode: ${WRITE_MODE}" >&2
      exit 2
      ;;
  esac

  if [[ "${should_write}" == "true" && -n "${supabase_url}" && -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    schema_probe_http="$(postgrest_request "GET" "${supabase_url}/rest/v1/quoted_authors?select=author_id&limit=1" "" "return=minimal" "${schema_probe_file}")"
    if [[ "${schema_probe_http}" == "404" ]]; then
      bridge_status="schema-missing"
      bridge_http="${schema_probe_http}"
      cp "${schema_probe_file}" "${bridge_response_path}" 2>/dev/null || true
      if [[ "${WRITE_MODE}" == "required" ]]; then
        echo "xauto-quoted-author-sync: required quoted-author schema is missing" >&2
        exit 1
      fi
    else
      set +e
      authors_http="$(postgrest_request "POST" "${supabase_url}/rest/v1/quoted_authors?on_conflict=platform,normalized_key" "${authors_payload_path}" "resolution=merge-duplicates,return=minimal" "${tmp_dir}/quoted-authors.write.json")"
      authors_rc=$?
      if (( authors_rc == 0 )) && [[ "${authors_http}" =~ ^20[01]$|^204$ ]]; then
        sources_http="$(postgrest_request "POST" "${supabase_url}/rest/v1/quoted_sources?on_conflict=normalized_source_url" "${sources_payload_path}" "resolution=merge-duplicates,return=minimal" "${tmp_dir}/quoted-sources.write.json")"
        sources_rc=$?
      else
        sources_rc=1
        sources_http="n/a"
      fi
      if (( sources_rc == 0 )) && [[ "${sources_http}" =~ ^20[01]$|^204$ ]]; then
        events_http="$(postgrest_request "POST" "${supabase_url}/rest/v1/quote_events?on_conflict=event_hash" "${events_payload_path}" "resolution=merge-duplicates,return=minimal" "${tmp_dir}/quote-events.write.json")"
        events_rc=$?
      else
        events_rc=1
        events_http="n/a"
      fi
      set -e
      jq -n \
        --arg schema_probe_http "${schema_probe_http}" \
        --arg authors_http "${authors_http:-n/a}" \
        --arg sources_http "${sources_http:-n/a}" \
        --arg events_http "${events_http:-n/a}" \
        --arg authors_status "$([[ ${authors_rc:-1} -eq 0 ]] && printf ok || printf error)" \
        --arg sources_status "$([[ ${sources_rc:-1} -eq 0 ]] && printf ok || printf error)" \
        --arg events_status "$([[ ${events_rc:-1} -eq 0 ]] && printf ok || printf error)" \
        '{
          schema_probe_http: $schema_probe_http,
          authors: {status: $authors_status, http: $authors_http},
          sources: {status: $sources_status, http: $sources_http},
          events: {status: $events_status, http: $events_http}
        }' > "${bridge_response_path}"
      if (( ${authors_rc:-1} == 0 )) && [[ "${authors_http}" =~ ^20[01]$|^204$ ]] &&
         (( ${sources_rc:-1} == 0 )) && [[ "${sources_http}" =~ ^20[01]$|^204$ ]] &&
         (( ${events_rc:-1} == 0 )) && [[ "${events_http}" =~ ^20[01]$|^204$ ]]; then
        bridge_status="applied"
        bridge_http="${events_http}"
      else
        bridge_status="apply-error"
        bridge_http="${events_http:-${sources_http:-${authors_http:-n/a}}}"
        if [[ "${WRITE_MODE}" == "required" ]]; then
          echo "xauto-quoted-author-sync: required Supabase write failed" >&2
          exit 1
        fi
      fi
    fi
  elif [[ "${should_write}" == "true" ]]; then
    bridge_status="deferred-missing-creds"
    if [[ "${WRITE_MODE}" == "required" ]]; then
      echo "xauto-quoted-author-sync: required Supabase credentials are missing" >&2
      exit 1
    fi
  else
    bridge_status="write-disabled"
  fi
fi

{
  echo "system=x-auto-quoted-author-sync"
  echo "mode=${MODE}"
  echo "write_mode=${WRITE_MODE}"
  echo "seed_input=${SEED_INPUT}"
  echo "posts_seed_input=${POSTS_SEED_INPUT}"
  echo "handle=${X_HANDLE}"
  echo "limit=${FETCH_LIMIT}"
  echo "from_date=${FROM_DATE}"
  echo "to_date=${TO_DATE}"
  echo "extract_mode=${EXTRACT_MODE}"
  echo "authors_count=$(jq 'length' <<< "${authors_json}")"
  echo "sources_count=$(jq 'length' <<< "${sources_json}")"
  echo "events_count=$(jq 'length' <<< "${events_json}")"
  echo "supabase_url=${supabase_url}"
  echo "bridge_status=${bridge_status}"
  echo "bridge_http=${bridge_http}"
  echo "schema_probe_http=${schema_probe_http}"
  echo "sql_path=${sql_path}"
  echo "result_path=${result_path}"
} > "${meta_path}"

cat "${result_path}"
