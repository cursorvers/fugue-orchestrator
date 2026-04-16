#!/usr/bin/env python3
import argparse
import base64
import datetime as dt
import hashlib
import hmac
import json
import os
import random
import re
import string
import sys
import time
import urllib.parse
import urllib.request


SELF_HANDLE_DEFAULT = "cursorvers"
X_API_BASE = "https://api.x.com/2"
XAI_BASE = "https://api.x.ai/v1/responses"
X_STATUS_ID_RE = re.compile(r"https?://(?:x|twitter)\.com/[^/]+/status/(\d+)", re.IGNORECASE)
PRIMARY_SOURCE_MAX_REF_DEPTH = max(1, int(os.getenv("X_AUTO_PRIMARY_SOURCE_MAX_REF_DEPTH", "4")))
AUTHOR_THREAD_SCAN_LIMIT = max(20, int(os.getenv("X_AUTO_AUTHOR_THREAD_SCAN_LIMIT", "100")))
TOPIC_NORMALIZATION_RULES = [
    ("medical-ai", {"medical ai", "medical-ai", "healthcare ai", "clinical ai"}),
    ("medical", {"medical", "medicine", "clinical", "healthcare"}),
    ("ai", {"ai", "artificial intelligence"}),
    ("governance", {"governance", "governed", "safety", "oversight"}),
    ("local-llm", {"local llm", "local-llm", "local_llm", "on-prem llm", "onprem llm"}),
    ("business", {"business", "management", "leadership"}),
    ("strategy", {"strategy", "strategic"}),
    ("workflow", {"workflow", "operations", "ops", "process", "productivity"}),
    ("curiosity", {"curiosity"}),
    ("vitality", {"vitality"}),
]


def b64url(data: bytes) -> str:
    return base64.b64encode(data).decode("utf-8")


def percent_encode(value: str) -> str:
    return urllib.parse.quote(value, safe="~")


def oauth1_header(method: str, url: str, query_params: dict) -> str:
    consumer_key = os.getenv("X_API_KEY", "")
    consumer_secret = os.getenv("X_API_KEY_SECRET", "")
    token = os.getenv("X_ACCESS_TOKEN", "")
    token_secret = os.getenv("X_ACCESS_TOKEN_SECRET", "")
    if not all([consumer_key, consumer_secret, token, token_secret]):
        raise RuntimeError("missing X API OAuth 1.0a credentials")

    oauth_params = {
        "oauth_consumer_key": consumer_key,
        "oauth_nonce": "".join(random.choices(string.ascii_letters + string.digits, k=32)),
        "oauth_signature_method": "HMAC-SHA1",
        "oauth_timestamp": str(int(time.time())),
        "oauth_token": token,
        "oauth_version": "1.0",
    }
    all_params = {**query_params, **oauth_params}
    param_string = "&".join(
        f"{percent_encode(str(k))}={percent_encode(str(all_params[k]))}"
        for k in sorted(all_params.keys())
    )
    base_string = "&".join(
        [
            method.upper(),
            percent_encode(url),
            percent_encode(param_string),
        ]
    )
    signing_key = "&".join([percent_encode(consumer_secret), percent_encode(token_secret)])
    signature = b64url(hmac.new(signing_key.encode(), base_string.encode(), hashlib.sha1).digest())
    oauth_params["oauth_signature"] = signature
    header = "OAuth " + ", ".join(
        f'{percent_encode(k)}="{percent_encode(v)}"' for k, v in sorted(oauth_params.items())
    )
    return header


def http_json(method: str, url: str, headers: dict | None = None, body: dict | None = None) -> dict:
    payload = None
    if body is not None:
        payload = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, method=method, headers=headers or {}, data=payload)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_user_id(handle: str) -> str:
    path = f"/users/by/username/{urllib.parse.quote(handle)}"
    url = X_API_BASE + path
    auth = oauth1_header("GET", url, {})
    res = http_json("GET", url, {"Authorization": auth})
    return res["data"]["id"]


def fetch_user_tweets_by_id(user_id: str, limit: int, from_date: str | None, to_date: str | None) -> list[dict]:
    tweets: list[dict] = []
    pagination_token = None
    while len(tweets) < limit:
        remaining = limit - len(tweets)
        batch_size = min(100, max(5, remaining))
        query = {
            "max_results": str(batch_size),
            "tweet.fields": "author_id,conversation_id,created_at,entities,referenced_tweets,attachments",
            "expansions": "referenced_tweets.id",
            "exclude": "retweets",
        }
        if pagination_token:
            query["pagination_token"] = pagination_token
        if from_date:
            query["start_time"] = from_date + "T00:00:00Z"
        if to_date:
            query["end_time"] = to_date + "T23:59:59Z"

        url = X_API_BASE + f"/users/{user_id}/tweets?" + urllib.parse.urlencode(query)
        auth = oauth1_header("GET", X_API_BASE + f"/users/{user_id}/tweets", query)
        res = http_json("GET", url, {"Authorization": auth})
        tweets.extend(res.get("data", []))
        pagination_token = res.get("meta", {}).get("next_token")
        if not pagination_token:
            break
    return tweets[:limit]


def fetch_user_tweets(handle: str, limit: int, from_date: str | None, to_date: str | None) -> list[dict]:
    user_id = fetch_user_id(handle)
    return fetch_user_tweets_by_id(user_id, limit, from_date, to_date)


def fetch_tweets_by_ids(tweet_ids: list[str]) -> dict[str, dict]:
    resolved: dict[str, dict] = {}
    chunk_size = 100
    for i in range(0, len(tweet_ids), chunk_size):
        chunk = [tweet_id for tweet_id in tweet_ids[i : i + chunk_size] if tweet_id]
        if not chunk:
            continue
        query = {
            "ids": ",".join(chunk),
            "tweet.fields": "author_id,conversation_id,created_at,entities,referenced_tweets,attachments",
            "expansions": "referenced_tweets.id",
        }
        url = X_API_BASE + "/tweets?" + urllib.parse.urlencode(query)
        auth = oauth1_header("GET", X_API_BASE + "/tweets", query)
        res = http_json("GET", url, {"Authorization": auth})
        for row in res.get("data", []):
            if row.get("id"):
                resolved[row["id"]] = row
        for row in res.get("includes", {}).get("tweets", []):
            if row.get("id"):
                resolved[row["id"]] = row
    return resolved


def parse_status_id(url: str) -> str:
    match = X_STATUS_ID_RE.search(url or "")
    return match.group(1) if match else ""


def is_x_url(url: str) -> bool:
    lowered = (url or "").lower()
    return "x.com/" in lowered or "twitter.com/" in lowered


def first_non_x_url(post: dict) -> str:
    entities = post.get("entities") or {}
    for url_obj in entities.get("urls", []):
        candidate = (url_obj.get("expanded_url") or url_obj.get("url") or "").strip()
        if candidate and not is_x_url(candidate):
            return candidate
    return ""


def infer_primary_url_from_author_thread(
    post: dict,
    post_index: dict[str, dict],
    timeline_cache: dict[str, list[dict]],
    timeline_errors: dict[str, str],
) -> tuple[str, list[str]]:
    author_id = str(post.get("author_id", "")).strip()
    conversation_id = str(post.get("conversation_id", "")).strip()
    post_id = str(post.get("id", "")).strip()
    if not author_id or not conversation_id:
        return "", []
    local_matches = []
    for candidate in post_index.values():
        if str(candidate.get("author_id", "")).strip() != author_id:
            continue
        if str(candidate.get("conversation_id", "")).strip() != conversation_id:
            continue
        candidate_url = first_non_x_url(candidate)
        if candidate_url:
            local_matches.append(candidate)
    if local_matches:
        local_matches.sort(key=lambda row: (str(row.get("id", "")) != conversation_id, row.get("created_at", "")))
        for candidate in local_matches:
            candidate_url = first_non_x_url(candidate)
            if candidate_url:
                return candidate_url, ["author-conversation", author_id, conversation_id, str(candidate.get("id", post_id))]
    if author_id not in timeline_cache:
        try:
            timeline_cache[author_id] = fetch_user_tweets_by_id(author_id, AUTHOR_THREAD_SCAN_LIMIT, None, None)
        except Exception as exc:
            timeline_cache[author_id] = []
            timeline_errors[author_id] = str(exc)
    matches: list[dict] = []
    for candidate in timeline_cache[author_id]:
        if str(candidate.get("conversation_id", "")).strip() != conversation_id:
            continue
        candidate_url = first_non_x_url(candidate)
        if candidate_url:
            matches.append(candidate)
    if not matches:
        return "", []
    matches.sort(key=lambda row: (str(row.get("id", "")) != conversation_id, row.get("created_at", "")))
    for candidate in matches:
        candidate_url = first_non_x_url(candidate)
        if candidate_url:
            return candidate_url, ["author-conversation", author_id, conversation_id, str(candidate.get("id", post_id))]
    return "", []


def expand_post_index_with_references(
    seed_post_ids: list[str],
    post_index: dict[str, dict],
    max_depth: int,
) -> tuple[set[str], str]:
    frontier = {post_id for post_id in seed_post_ids if post_id}
    fetch_error = ""
    depth = 0
    seen = set()
    while frontier and depth < max_depth:
        unresolved = set()
        next_frontier = set()
        for post_id in frontier:
            if post_id in seen:
                continue
            seen.add(post_id)
            post = post_index.get(post_id)
            if not post:
                unresolved.add(post_id)
                continue
            for ref in post.get("referenced_tweets", []) or []:
                ref_id = str(ref.get("id", "")).strip()
                if not ref_id:
                    continue
                next_frontier.add(ref_id)
                if ref_id not in post_index:
                    unresolved.add(ref_id)
        if unresolved:
            try:
                fetched = fetch_tweets_by_ids(sorted(unresolved))
                post_index.update(fetched)
            except Exception as exc:
                fetch_error = str(exc)
                break
        frontier = next_frontier
        depth += 1
    return seen, fetch_error


def enrich_records_with_primary_sources(records: list[dict], posts: list[dict]) -> list[dict]:
    post_index = {str(post.get("id", "")): post for post in posts if post.get("id")}
    timeline_cache: dict[str, list[dict]] = {}
    timeline_errors: dict[str, str] = {}
    reference_fetch_errors: list[str] = []
    seed_post_ids: list[str] = []
    for record in records:
        source_url = str(record.get("source_url", "")).strip()
        if source_url and is_x_url(source_url):
            status_id = parse_status_id(source_url)
            if status_id:
                seed_post_ids.append(status_id)
        cursorvers_post_id = str(record.get("cursorvers_post_id", "")).strip()
        if cursorvers_post_id:
            seed_post_ids.append(cursorvers_post_id)

    seen_reference_posts, fetch_ids_error = expand_post_index_with_references(
        seed_post_ids,
        post_index,
        PRIMARY_SOURCE_MAX_REF_DEPTH,
    )
    if fetch_ids_error:
        reference_fetch_errors.append(fetch_ids_error)

    def resolve_primary_url(post_id: str, depth: int, visited: set[str]) -> str:
        if not post_id or post_id in visited or depth > PRIMARY_SOURCE_MAX_REF_DEPTH:
            return ""
        visited.add(post_id)
        post = post_index.get(post_id)
        if not post:
            return ""
        direct_url = first_non_x_url(post)
        if direct_url:
            return direct_url
        for ref in post.get("referenced_tweets", []) or []:
            ref_id = str(ref.get("id", "")).strip()
            resolved = resolve_primary_url(ref_id, depth + 1, visited)
            if resolved:
                return resolved
        return ""

    enriched = []
    for record in records:
        metadata = dict(record.get("metadata") or {})
        source_url = str(record.get("source_url", "")).strip()
        cursorvers_post_id = str(record.get("cursorvers_post_id", "")).strip()
        primary_url = ""
        resolution_path: list[str] = []
        if source_url and not is_x_url(source_url):
            primary_url = source_url
            resolution_path = ["direct-source-url"]
        else:
            source_status_id = parse_status_id(source_url)
            if source_status_id:
                primary_url = resolve_primary_url(source_status_id, 0, set())
                if primary_url:
                    resolution_path = ["quoted-post", source_status_id]
                else:
                    source_post = post_index.get(source_status_id)
                    if source_post:
                        inferred_url, inferred_path = infer_primary_url_from_author_thread(
                            source_post,
                            post_index,
                            timeline_cache,
                            timeline_errors,
                        )
                        if inferred_url:
                            primary_url = inferred_url
                            resolution_path = inferred_path
            if not primary_url and cursorvers_post_id:
                primary_url = resolve_primary_url(cursorvers_post_id, 0, set())
                if primary_url:
                    resolution_path = ["cursorvers-post", cursorvers_post_id]
                else:
                    source_post = post_index.get(cursorvers_post_id)
                    if source_post:
                        inferred_url, inferred_path = infer_primary_url_from_author_thread(
                            source_post,
                            post_index,
                            timeline_cache,
                            timeline_errors,
                        )
                        if inferred_url:
                            primary_url = inferred_url
                            resolution_path = inferred_path
        recovery_errors: list[str] = []
        source_status_id = parse_status_id(source_url)
        if fetch_ids_error and ((source_status_id and source_status_id in seen_reference_posts) or (cursorvers_post_id and cursorvers_post_id in seen_reference_posts)):
            recovery_errors.append("fetch-referenced-posts-failed")
        if source_status_id:
            source_post = post_index.get(source_status_id)
            source_author_id = str((source_post or {}).get("author_id", "")).strip()
            if source_author_id and source_author_id in timeline_errors:
                recovery_errors.append("fetch-author-thread-failed")
        if cursorvers_post_id:
            cursorvers_post = post_index.get(cursorvers_post_id)
            cursorvers_author_id = str((cursorvers_post or {}).get("author_id", "")).strip()
            if cursorvers_author_id and cursorvers_author_id in timeline_errors:
                recovery_errors.append("fetch-author-thread-failed")
        if primary_url:
            metadata["primary_source_url"] = primary_url
            metadata["source_resolution_path"] = resolution_path
            metadata["primary_source_evidence_post_id"] = resolution_path[-1] if resolution_path else ""
            if resolution_path[:1] == ["direct-source-url"]:
                metadata["primary_source_strategy"] = "direct"
                metadata["primary_source_confidence"] = 1.0
            elif resolution_path[:1] == ["quoted-post"]:
                metadata["primary_source_strategy"] = "quoted-reference"
                metadata["primary_source_confidence"] = 0.92
            elif resolution_path[:1] == ["author-conversation"]:
                metadata["primary_source_strategy"] = "author-conversation"
                metadata["primary_source_confidence"] = 0.78
            else:
                metadata["primary_source_strategy"] = "cursorvers-reference"
                metadata["primary_source_confidence"] = 0.74
        if recovery_errors:
            metadata["source_recovery_errors"] = sorted(set(recovery_errors))
        record_with_meta = dict(record)
        record_with_meta["metadata"] = metadata
        enriched.append(record_with_meta)
    return enriched


def heuristic_extract(posts: list[dict], self_handle: str) -> list[dict]:
    url_pattern = re.compile(r"https?://[^\s)]+")
    records = []
    for post in posts:
        text = post.get("text", "")
        entities = post.get("entities") or {}
        urls = [u.get("expanded_url") or u.get("url") for u in entities.get("urls", []) if u.get("expanded_url") or u.get("url")]
        if not urls:
            urls = url_pattern.findall(text)
        mentions = [m.get("username", "") for m in entities.get("mentions", []) if m.get("username")]
        author_handle = ""
        for mention in mentions:
            if mention.lower() != self_handle.lower():
                author_handle = mention
                break
        for source_url in urls:
            records.append(
                {
                    "cursorvers_post_id": post.get("id", ""),
                    "source_url": source_url,
                    "author_handle": author_handle,
                    "display_name": "",
                    "topic_tags": [],
                    "conclusion_tag": "",
                    "pattern_tag": "",
                    "metadata": {
                        "extractor": "heuristic",
                        "post_created_at": post.get("created_at", ""),
                    },
                }
            )
    return records


def normalize_topic_tags(tags: list[str]) -> list[str]:
    normalized: list[str] = []
    seen = set()
    for raw_tag in tags or []:
        cleaned = str(raw_tag).strip()
        if not cleaned:
            continue
        lowered = cleaned.lower()
        canonical = ""
        for label, variants in TOPIC_NORMALIZATION_RULES:
            if lowered == label or lowered in variants:
                canonical = label
                break
        if not canonical:
            canonical = re.sub(r"[^a-z0-9]+", "-", lowered).strip("-") or lowered
        if canonical not in seen:
            normalized.append(canonical)
            seen.add(canonical)
    return normalized


def normalize_conclusion_tag(tag: str) -> str:
    lowered = str(tag or "").strip().lower()
    if not lowered:
        return ""
    if "vitality" in lowered and ("curiosity" in lowered or "possible" in lowered or "suffice" in lowered):
        return "possible_with_vitality"
    if "vitality" in lowered:
        return "vitality_over_age"
    if "local" in lowered and "llm" in lowered:
        return "local_llm_recommended"
    if "broader" in lowered or "wider" in lowered or "view" in lowered:
        return "broader_view"
    if "confirm" in lowered or "layer" in lowered:
        return "confirmation_layers"
    if "agree" in lowered or "affirm" in lowered or "endorse" in lowered:
        return "agreement"
    return re.sub(r"[^a-z0-9]+", "_", lowered).strip("_")


def normalize_pattern_tag(tag: str) -> str:
    lowered = str(tag or "").strip().lower()
    if not lowered:
        return ""
    if "quote" in lowered:
        return "quoted"
    if "reply" in lowered:
        return "reply"
    if "support" in lowered or "endorse" in lowered or "advocacy" in lowered:
        return "quoted_agreement"
    if "original" in lowered:
        return "original"
    return re.sub(r"[^a-z0-9]+", "_", lowered).strip("_")


def normalize_records(records: list[dict]) -> list[dict]:
    normalized = []
    for record in records:
        updated = dict(record)
        metadata = dict(updated.get("metadata") or {})
        raw_topic_tags = [str(tag) for tag in updated.get("topic_tags", []) if str(tag).strip()]
        raw_conclusion_tag = str(updated.get("conclusion_tag", "")).strip()
        raw_pattern_tag = str(updated.get("pattern_tag", "")).strip()
        updated["author_handle"] = str(updated.get("author_handle", "")).strip().lstrip("@").lower()
        updated["topic_tags"] = normalize_topic_tags(raw_topic_tags)
        updated["conclusion_tag"] = normalize_conclusion_tag(raw_conclusion_tag)
        updated["pattern_tag"] = normalize_pattern_tag(raw_pattern_tag)
        source_url = str(updated.get("source_url", "")).strip()
        if source_url and not is_x_url(source_url) and not str(metadata.get("primary_source_url", "")).strip():
            metadata["primary_source_url"] = source_url
        if raw_topic_tags and raw_topic_tags != updated["topic_tags"]:
            metadata["raw_topic_tags"] = raw_topic_tags
        if raw_conclusion_tag and raw_conclusion_tag != updated["conclusion_tag"]:
            metadata["raw_conclusion_tag"] = raw_conclusion_tag
        if raw_pattern_tag and raw_pattern_tag != updated["pattern_tag"]:
            metadata["raw_pattern_tag"] = raw_pattern_tag
        updated["metadata"] = metadata
        normalized.append(updated)
    return normalized


def postprocess_records(records: list[dict], posts: list[dict]) -> list[dict]:
    return normalize_records(enrich_records_with_primary_sources(records, posts))


def analyze_with_xai(posts: list[dict], self_handle: str) -> list[dict]:
    api_key = os.getenv("XAI_API_KEY", "")
    if not api_key:
        raise RuntimeError("missing XAI_API_KEY")
    model = os.getenv("FUGUE_XAI_MODEL", os.getenv("XAI_MODEL", "grok-4.20-reasoning"))
    prompt = (
        "You are extracting quoted-author provenance from posts by "
        f"@{self_handle}. Return only JSON.\n"
        "Given the post list, identify external quoted or referenced sources and the likely author handle.\n"
        "Return an array of objects with keys: cursorvers_post_id, source_url, author_handle, display_name, "
        "topic_tags, conclusion_tag, pattern_tag, metadata.\n"
        "Rules:\n"
        "- Prefer explicit quoted or linked external sources.\n"
        "- If author is unknown, use empty string.\n"
        "- topic_tags must be a short array of strings.\n"
        "- metadata must include extractor=\"xai\" and confidence 0..1.\n"
        "- Do not include commentary or markdown.\n"
        f"Posts JSON:\n{json.dumps(posts, ensure_ascii=False)}"
    )
    body = {
        "model": model,
        "input": [{"role": "user", "content": prompt}],
        "temperature": 0.1,
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    res = http_json("POST", XAI_BASE, headers, body)
    output_text_parts = []
    for item in res.get("output", []):
        for content in item.get("content", []):
            if content.get("type") in ("output_text", "text"):
                output_text_parts.append(content.get("text", ""))
    raw_text = "".join(output_text_parts).strip()
    if not raw_text:
        raise RuntimeError("xAI response did not include output text")
    return json.loads(raw_text)


def load_posts_from_seed(path: str) -> list[dict]:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if isinstance(data, dict) and "posts" in data and isinstance(data["posts"], list):
        return data["posts"]
    if isinstance(data, list):
        return data
    raise RuntimeError("seed input must be a post array or {posts:[...]}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--handle", default=os.getenv("X_AUTO_QUOTED_AUTHOR_SYNC_HANDLE", SELF_HANDLE_DEFAULT))
    parser.add_argument("--limit", type=int, default=int(os.getenv("X_AUTO_QUOTED_AUTHOR_SYNC_LIMIT", "50")))
    parser.add_argument("--from-date", default=os.getenv("X_AUTO_QUOTED_AUTHOR_SYNC_FROM_DATE", ""))
    parser.add_argument("--to-date", default=os.getenv("X_AUTO_QUOTED_AUTHOR_SYNC_TO_DATE", ""))
    parser.add_argument("--posts-seed-input", default="")
    parser.add_argument("--extract-mode", default=os.getenv("X_AUTO_QUOTED_AUTHOR_SYNC_EXTRACT_MODE", "auto"))
    args = parser.parse_args()

    if args.posts_seed_input:
        posts = load_posts_from_seed(args.posts_seed_input)
    else:
        posts = fetch_user_tweets(args.handle, args.limit, args.from_date or None, args.to_date or None)

    if args.extract_mode == "heuristic":
        records = heuristic_extract(posts, args.handle)
    else:
        try:
            records = analyze_with_xai(posts, args.handle)
        except Exception:
            records = heuristic_extract(posts, args.handle)

    records = postprocess_records(records, posts)

    json.dump(records, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
