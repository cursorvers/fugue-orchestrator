from __future__ import annotations

import argparse
import json
import logging
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta
from pathlib import Path

from config import POST_SCHEDULE, _get_secret
from post_generator import load_posts_from_json, save_posts_to_json
from schema import PostRecord, validate_post_record

BASE_DIR = Path(__file__).resolve().parent
TREND_STATE_FILE = BASE_DIR / "trend_state.json"
QUOTE_CANDIDATES_FILE = BASE_DIR / "quote_candidates.json"

XAI_API_KEY = _get_secret("XAI_API_KEY", (), required=False)
XAI_ENDPOINT = "https://api.x.ai/v1/responses"
XAI_MODEL = "grok-4-1-fast"
MIN_QUEUE_THRESHOLD = 9
DRAFTS_PER_RUN = 3
MAX_CHARS = 1000
REQUEST_TIMEOUT = 60
USER_AGENT = "x-auto-trend-scanner/1.0"

ACCOUNT_PROFILE_CONTEXT = "Cursorvers Inc. 代表。医師×ソロプレナー。医療AIガバナンス・Claude Code活用"
PILLAR_DESCRIPTIONS = {
    1: "医療AIインテリジェンス",
    2: "非エンジニアAIビルド",
    3: "AI時代の人間論",
}

LOGGER = logging.getLogger("auto_generator")


def _configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )


def _read_json(path: Path, default: object) -> object:
    if not path.exists():
        return default
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def _write_json(path: Path, payload: object) -> None:
    tmp_path = path.with_suffix(f"{path.suffix}.tmp")
    tmp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp_path.replace(path)


def _extract_output_text(response_payload: dict) -> str:
    texts: list[str] = []
    for item in response_payload.get("output", []):
        if not isinstance(item, dict):
            continue
        for content in item.get("content", []):
            if not isinstance(content, dict):
                continue
            text = content.get("text")
            if isinstance(text, str) and text.strip():
                texts.append(text.strip())
    return "\n".join(texts).strip()


def _extract_json_array(text: str) -> list[dict] | None:
    if not text:
        return None

    candidates: list[str] = [text.strip()]
    stripped = text.strip()
    if stripped.startswith("```") and stripped.endswith("```"):
        inner = stripped[3:-3].strip()
        if inner.startswith("json"):
            inner = inner[4:].strip()
        candidates.append(inner)

    start = stripped.find("[")
    end = stripped.rfind("]")
    if start != -1 and end > start:
        candidates.append(stripped[start : end + 1])

    seen: set[str] = set()
    for candidate in candidates:
        candidate = candidate.strip()
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        try:
            payload = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, list):
            return [item for item in payload if isinstance(item, dict)]
    return None


def _build_prompt(trend_state: dict, unreviewed_candidates: list[dict]) -> str:
    trend_context: list[dict] = []
    for family_name, family_payload in trend_state.get("families", {}).items():
        if not isinstance(family_payload, dict):
            continue
        trend_context.append(
            {
                "family": family_name,
                "summary": family_payload.get("summary", ""),
                "topics": family_payload.get("topics", []),
            }
        )

    quote_context = [
        {
            "account": item.get("account", ""),
            "text": item.get("text", ""),
            "url": item.get("url", ""),
            "relevance_family": item.get("relevance_family", ""),
            "scanned_at": item.get("scanned_at", ""),
        }
        for item in unreviewed_candidates
    ]

    return (
        "You are generating X/Twitter post drafts for a Japanese founder account.\n"
        f"Account profile: {ACCOUNT_PROFILE_CONTEXT}\n"
        "Three pillars:\n"
        f"- P1: {PILLAR_DESCRIPTIONS[1]}\n"
        f"- P2: {PILLAR_DESCRIPTIONS[2]}\n"
        f"- P3: {PILLAR_DESCRIPTIONS[3]}\n\n"
        "Recent trends from trend_state.json:\n"
        f"{json.dumps(trend_context, ensure_ascii=False, indent=2)}\n\n"
        "Unreviewed quote candidates from quote_candidates.json:\n"
        f"{json.dumps(quote_context, ensure_ascii=False, indent=2)}\n\n"
        "Generate exactly 3 Japanese posts, one per pillar.\n"
        "Required output fields per item: title, text, pillar, source_url.\n"
        "title: 15-30 chars.\n"
        "pillar: must be 1, 2, or 3, and use each value exactly once.\n\n"
        "## 文章スタイル（pillar別）\n"
        "P1/P2（説明・解説型）:\n"
        "- 一次情報（法規制、ガイドライン条文、市場データ、公式ドキュメント）を明記\n"
        "- 具体的な数字・条項番号・出典名を本文に含める\n"
        "- 「学びがある」と感じる情報密度を重視\n"
        "- 目標: 500-800文字。短くまとめず、根拠を丁寧に書く\n"
        "- source_urlは一次情報のURLを必ず設定\n\n"
        "P3（本質論・哲学型）:\n"
        "- 短く刺さる文章。250-400文字\n"
        "- 一人称、経験ベース、余韻を残す\n"
        "- 結論を断定しすぎない。問いかけで終わるのも可\n"
        "- source_urlは空文字可\n\n"
        "共通ルール:\n"
        "- generic platitudes禁止。具体性のない「AIは重要です」的表現は不可\n"
        "- x_searchで事実確認してから書くこと\n"
        "- 冒頭に『...』形式の印象的な一文を置く\n"
        "Return strict JSON only: an array of exactly 3 objects with this shape:\n"
        "[{\"title\":\"...\",\"text\":\"...\",\"pillar\":1,\"source_url\":\"https://... or empty string\"}]"
    )


def _call_xai(prompt: str) -> dict:
    if not XAI_API_KEY:
        raise RuntimeError("XAI_API_KEY not found in env or .secrets.json")

    payload = json.dumps(
        {
            "model": XAI_MODEL,
            "input": prompt,
            "tools": [{"type": "x_search", "x_search": {}}],
        }
    ).encode("utf-8")

    request = urllib.request.Request(
        XAI_ENDPOINT,
        data=payload,
        headers={
            "Authorization": f"Bearer {XAI_API_KEY}",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )

    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8"))


def _next_available_slots(posts: list[PostRecord], count: int) -> list[str]:
    scheduled_by_day: dict[str, list[datetime]] = {}
    for post in posts:
        scheduled_for = post.get("scheduled_for", "")
        if not isinstance(scheduled_for, str):
            continue
        try:
            scheduled_dt = datetime.strptime(scheduled_for, "%Y-%m-%d %H:%M")
        except ValueError:
            continue
        day_key = scheduled_dt.strftime("%Y-%m-%d")
        scheduled_by_day.setdefault(day_key, []).append(scheduled_dt)

    now = datetime.now()
    day_cursor = now.replace(hour=0, minute=0, second=0, microsecond=0)
    slots: list[str] = []

    while len(slots) < count:
        day_key = day_cursor.strftime("%Y-%m-%d")
        existing_for_day = scheduled_by_day.get(day_key, [])
        used_times = {item.strftime("%H:%M") for item in existing_for_day}
        available_for_day = max(0, 3 - len(existing_for_day))
        assigned_for_day = 0

        if available_for_day:
            for hhmm in POST_SCHEDULE:
                if hhmm in used_times:
                    continue
                candidate = datetime.strptime(f"{day_key} {hhmm}", "%Y-%m-%d %H:%M")
                if candidate <= now:
                    continue
                slots.append(candidate.strftime("%Y-%m-%d %H:%M"))
                used_times.add(hhmm)
                assigned_for_day += 1
                if len(slots) >= count or assigned_for_day >= available_for_day:
                    break

        day_cursor += timedelta(days=1)

    return slots


def _load_inputs() -> tuple[dict, dict]:
    trend_state = _read_json(TREND_STATE_FILE, {})
    quote_candidates = _read_json(QUOTE_CANDIDATES_FILE, {})
    if not isinstance(trend_state, dict):
        raise RuntimeError("trend_state.json is not a JSON object")
    if not isinstance(quote_candidates, dict):
        raise RuntimeError("quote_candidates.json is not a JSON object")
    return trend_state, quote_candidates


def _prepare_generated_posts(generated_items: list[dict], existing_posts: list[PostRecord]) -> tuple[list[PostRecord], set[str]]:
    unique_by_pillar: dict[int, dict] = {}
    for item in generated_items:
        try:
            pillar = int(item.get("pillar", 0))
        except (TypeError, ValueError):
            continue
        if pillar not in PILLAR_DESCRIPTIONS or pillar in unique_by_pillar:
            continue
        unique_by_pillar[pillar] = item

    if not unique_by_pillar:
        LOGGER.warning("xAI response contained no valid pillar posts")
        return [], set()

    scheduled_slots = _next_available_slots(existing_posts, len(unique_by_pillar))
    created_at = datetime.now().isoformat(timespec="seconds")
    prepared_posts: list[PostRecord] = []
    used_source_urls: set[str] = set()
    slot_index = 0

    for pillar in (1, 2, 3):
        if pillar not in unique_by_pillar:
            LOGGER.warning("No post generated for pillar %d; skipping", pillar)
            continue
        item = unique_by_pillar[pillar]
        title = str(item.get("title", "")).strip()
        text = str(item.get("text", "")).strip()
        source_url = str(item.get("source_url", "")).strip()
        if not title or not text:
            LOGGER.warning("Missing title/text for pillar %d; skipping", pillar)
            continue
        if len(title) < 5 or len(title) > 60:
            LOGGER.warning("Title length %d out of range for pillar %d; skipping", len(title), pillar)
            continue
        if len(text) < 100:
            LOGGER.warning("Text too short (%d chars) for pillar %d; skipping", len(text), pillar)
            continue
        if len(text) > MAX_CHARS:
            LOGGER.warning("Text too long (%d chars) for pillar %d; skipping", len(text), pillar)
            continue
        if slot_index >= len(scheduled_slots):
            LOGGER.warning("No more schedule slots available; skipping pillar %d", pillar)
            continue

        record: PostRecord = {
            "id": str(uuid.uuid4()),
            "scheduled_for": scheduled_slots[slot_index],
            "title": title,
            "text": text,
            "pillar": pillar,
            "status": "draft",
            "created_at": created_at,
        }
        if source_url:
            record["source_url"] = source_url
            used_source_urls.add(source_url)

        is_valid, warnings = validate_post_record(record)
        for warning in warnings:
            LOGGER.warning(warning)
        if not is_valid:
            LOGGER.warning("Validation failed for pillar %d; skipping", pillar)
            continue
        prepared_posts.append(record)
        slot_index += 1

    return prepared_posts, used_source_urls


def _mark_reviewed(quote_candidates: dict, used_source_urls: set[str]) -> None:
    if not used_source_urls:
        return
    candidates = quote_candidates.get("candidates", [])
    if not isinstance(candidates, list):
        return
    for item in candidates:
        if not isinstance(item, dict):
            continue
        url = str(item.get("url", "")).strip()
        if url and url in used_source_urls:
            item["reviewed"] = True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate X/Twitter draft posts from trend data.")
    parser.add_argument("--dry-run", action="store_true", help="Generate drafts without saving JSON files.")
    args = parser.parse_args(argv)

    _configure_logging()

    try:
        posts = load_posts_from_json()
        approved_count = sum(1 for post in posts if post.get("status") == "approved")
        if approved_count >= MIN_QUEUE_THRESHOLD:
            LOGGER.info("Queue sufficient")
            return 0

        trend_state, quote_candidates = _load_inputs()
        all_candidates = quote_candidates.get("candidates", [])
        if not isinstance(all_candidates, list):
            raise RuntimeError("quote_candidates.json candidates must be a list")
        unreviewed_candidates = [
            item for item in all_candidates if isinstance(item, dict) and not item.get("reviewed", False)
        ]

        prompt = _build_prompt(trend_state, unreviewed_candidates)

        try:
            response_payload = _call_xai(prompt)
        except Exception:
            LOGGER.error("xAI API call failed", exc_info=True)
            return 1

        raw_text = _extract_output_text(response_payload)
        generated_items = _extract_json_array(raw_text)
        if generated_items is None:
            LOGGER.error("Failed to parse xAI JSON response: %s", raw_text)
            return 1

        generated_posts, used_source_urls = _prepare_generated_posts(generated_items, posts)

        if args.dry_run:
            LOGGER.info(
                "Dry run complete generated=%d approved_count=%d used_quotes=%d",
                len(generated_posts),
                approved_count,
                len(used_source_urls),
            )
            return 0

        posts.extend(generated_posts)
        save_posts_to_json(posts)
        _mark_reviewed(quote_candidates, used_source_urls)
        _write_json(QUOTE_CANDIDATES_FILE, quote_candidates)

        LOGGER.info(
            "Draft generation complete generated=%d approved_count=%d reviewed_quotes=%d",
            len(generated_posts),
            approved_count,
            len(used_source_urls),
        )
        return 0
    except Exception:
        LOGGER.error("Auto generator failed", exc_info=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
