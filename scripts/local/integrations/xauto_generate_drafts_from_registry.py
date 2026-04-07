#!/usr/bin/env python3
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
import urllib.parse
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import xauto_quoted_author_sync as sync_helper  # noqa: E402


DEFAULT_MODEL = "grok-4.20-reasoning"
PROPER_NOUN_BLOCKLIST = {"cursorvers", "guidescope"}
DIVERSITY_THRESHOLD = 0.56
SIMILARITY_THRESHOLD = 0.74
TONE_PROFILES = {"middle", "polite"}
NUMERIC_CLAIM_RE = re.compile(r"(\d+(?:\.\d+)?\s*(?:%|％|倍|割|人|例|件|名|ヶ月|か月|年|週間|週|日)|[0-9一二三四五六七八九十]+割)")
UNSUPPORTED_AUTHORITY_RE = re.compile(r"\b(?:jama|nejm|nature medicine|thelancet|thelancetdigitalhealth)\b", re.IGNORECASE)
ASSERTIVE_TONE_RE = re.compile(r"(?:絶対|必ず|明らかに|完全に|断言できる|しかない|に違いない|で間違いない)")
POLITE_ENDING_RE = re.compile(r"(?:です|ます|ません|でしょう|ください|いたします|しております)$")
SENTENCE_SPLIT_RE = re.compile(r"[。！？!?]+")
TAG_LABELS = {
    "vitality": "活力",
    "curiosity": "好奇心",
    "achievement": "達成",
    "healthcare": "医療",
    "perspective": "視点",
    "medical": "医療",
    "medicine": "医療",
    "clinical": "臨床",
    "diagnosis": "診断",
    "medical_diagnosis": "医療診断",
    "ai": "AI",
    "medical ai": "医療AI",
    "medical-ai": "医療AI",
    "governance": "ガバナンス",
    "personal qualities": "資質",
    "local llm": "ローカルLLM",
    "local-llm": "ローカルLLM",
    "local_llm": "ローカルLLM",
    "business": "経営",
    "strategy": "戦略",
    "risk": "リスク",
    "workflow": "業務設計",
    "tool": "ツール活用",
    "ops": "運用",
    "security": "セキュリティ",
    "privacy": "プライバシー",
    "compliance": "コンプライアンス",
    "guidelines": "ガイドライン",
    "policy": "政策",
    "scaling": "普及設計",
    "harness": "検証基盤",
    "quality": "品質管理",
    "ai-tools": "AIツール",
    "cost": "コスト",
    "defense": "防御設計",
    "macstudio": "ローカル環境",
    "prompt-engineering": "プロンプト設計",
    "prompt_engineering": "プロンプト設計",
    "orchestration": "オーケストレーション",
    "orchestrator": "オーケストレーション",
    "capability": "能力開発",
    "career": "キャリア",
    "growth": "成長",
    "mindset": "思考法",
    "claude": "LLM運用",
    "llm": "LLM活用",
    "recommendation": "推奨設計",
    "system": "システム設計",
}
GENERIC_TOPICS = {"ai", "medical", "medicine", "healthcare", "clinical"}
TOPIC_PRIORITY = {
    "security": 5,
    "privacy": 5,
    "compliance": 5,
    "governance": 5,
    "guidelines": 4,
    "policy": 4,
    "scaling": 3,
    "strategy": 4,
    "workflow": 4,
    "business": 4,
    "local-llm": 4,
    "llm": 4,
    "orchestration": 4,
    "orchestrator": 4,
    "prompt-engineering": 4,
    "harness": 4,
    "quality": 4,
    "ai-tools": 3,
    "cost": 3,
    "defense": 3,
    "macstudio": 2,
    "capability": 3,
    "career": 3,
    "growth": 3,
    "mindset": 3,
    "ai": 1,
    "medical": 1,
    "medicine": 1,
    "healthcare": 1,
    "clinical": 1,
}
PRIMARY_SOURCE_STRATEGY_PRIORITY = {
    "direct": 4,
    "quoted-reference": 3,
    "author-conversation": 2,
    "cursorvers-reference": 1,
}


def safe_confidence(value, default: float = 0.5) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def topic_set(record: dict) -> set[str]:
    return {str(tag).strip().lower() for tag in record.get("topic_tags", []) if str(tag).strip()}


def stable_record_key(record: dict) -> str:
    primary_url = primary_source_url(record)
    source_url = str(record.get("source_url", "")).strip()
    author_handle = str(record.get("author_handle", "")).strip().lower()
    conclusion = str(record.get("conclusion_tag", "")).strip().lower()
    pattern_tag = str(record.get("pattern_tag", "")).strip().lower()
    metadata = record.get("metadata", {}) or {}
    source_hash = str(record.get("source_hash", "") or metadata.get("source_hash", "")).strip()
    event_hash = str(record.get("event_hash", "") or metadata.get("event_hash", "")).strip()
    return "|".join([primary_url, source_url, source_hash, event_hash, author_handle, conclusion, pattern_tag])


def primary_source_confidence(record: dict) -> float:
    metadata = record.get("metadata", {}) or {}
    confidence = safe_confidence(metadata.get("primary_source_confidence", 0.0), 0.0)
    return max(0.0, min(1.0, confidence))


def primary_source_strategy_rank(record: dict) -> int:
    metadata = record.get("metadata", {}) or {}
    strategy = str(metadata.get("primary_source_strategy", "")).strip().lower()
    return PRIMARY_SOURCE_STRATEGY_PRIORITY.get(strategy, 0)


def load_registry_records(args) -> list[dict]:
    if args.registry_seed_input:
        with open(args.registry_seed_input, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, dict):
            if isinstance(data.get("events"), list):
                # raw sync adapter output
                events = data["events"]
                sources = {row.get("source_hash", ""): row for row in data.get("sources", [])}
                authors = {row.get("normalized_key", ""): row for row in data.get("authors", [])}
                records = []
                for event in events:
                    source = sources.get(event.get("source_hash", ""), {})
                    author = authors.get(event.get("author_key", ""), {})
                    records.append(
                        {
                            "cursorvers_post_id": event.get("cursorvers_post_id", ""),
                            "source_url": source.get("source_url", ""),
                            "author_handle": author.get("canonical_handle", ""),
                            "display_name": author.get("display_name", ""),
                            "topic_tags": event.get("topic_tags", []),
                            "conclusion_tag": event.get("conclusion_tag", ""),
                            "pattern_tag": event.get("pattern_tag", ""),
                            "source_hash": event.get("source_hash", source.get("source_hash", "")),
                            "event_hash": event.get("event_hash", ""),
                            "metadata": event.get("metadata", {}),
                        }
                    )
                return records
            if isinstance(data.get("records"), list):
                return data["records"]
        if isinstance(data, list):
            return data
        raise RuntimeError("registry seed input must be a list or sync result object")

    if args.posts_seed_input:
        posts = sync_helper.load_posts_from_seed(args.posts_seed_input)
    else:
        posts = sync_helper.fetch_user_tweets(args.handle, args.limit, args.from_date or None, args.to_date or None)

    if args.extract_mode == "heuristic":
        records = sync_helper.heuristic_extract(posts, args.handle)
        return sync_helper.postprocess_records(records, posts)

    try:
        records = sync_helper.analyze_with_xai(posts, args.handle)
    except Exception:
        records = sync_helper.heuristic_extract(posts, args.handle)
    return sync_helper.postprocess_records(records, posts)


def score_record(record: dict) -> float:
    confidence = safe_confidence(record.get("metadata", {}).get("confidence", 0.5), 0.5)
    topics = topic_set(record)
    non_medical_bonus = 0.15 if not topics.intersection({"medical", "medicine", "clinical", "diagnosis"}) else 0.0
    author_bonus = 0.1 if record.get("author_handle") else 0.0
    source_bonus = 0.1 if record.get("source_url") else -1.0
    primary_bonus = 0.15 if primary_source_url(record) else 0.0
    source_quality_bonus = 0.12 * primary_source_confidence(record)
    strategy_bonus = 0.03 * primary_source_strategy_rank(record)
    return confidence + non_medical_bonus + author_bonus + source_bonus + primary_bonus + source_quality_bonus + strategy_bonus


def dedupe_and_select(records: list[dict], candidate_pool_size: int) -> tuple[list[dict], list[dict]]:
    selected: list[dict] = []
    rejected: list[dict] = []
    seen_sources = set()
    def sort_key(record: dict):
        return (
            -score_record(record),
            -primary_source_confidence(record),
            -primary_source_strategy_rank(record),
            -(1 if primary_source_url(record) else 0),
            str(record.get("source_url", "")).strip(),
            str(record.get("author_handle", "")).strip().lower(),
            stable_record_key(record),
        )

    for record in sorted(records, key=sort_key):
        source_url = record.get("source_url", "").strip()
        dedupe_key = primary_source_url(record) or source_url
        confidence = safe_confidence(record.get("metadata", {}).get("confidence", 0.5), 0.5)
        family = family_key(record)
        if not source_url:
            rejected.append({"reason": "missing-source-url", "record": record})
            continue
        if is_x_url(source_url) and not primary_source_url(record):
            if record.get("pattern_tag") == "reply":
                rejected.append({"reason": "x-only-reply-source", "record": record})
                continue
            if confidence < 0.7 and family in {"insight::reply", "encouragement::positive_feedback"}:
                rejected.append({"reason": "x-only-low-signal-source", "record": record})
                continue
        if dedupe_key in seen_sources:
            rejected.append({"reason": "duplicate-source-url", "record": record})
            continue
        selected.append(record)
        seen_sources.add(dedupe_key)
        if len(selected) >= candidate_pool_size:
            break
    return selected, rejected


def load_recent_drafts(path: str) -> list[dict]:
    if not path:
        return []
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if isinstance(data, dict):
        for key in ("accepted", "created", "drafts", "items"):
            if isinstance(data.get(key), list):
                return data[key]
    if isinstance(data, list):
        return data
    raise RuntimeError("recent drafts input must be a list or output object with accepted/created")


def map_category(record: dict) -> tuple[str, str, str]:
    topics = {str(tag).lower() for tag in record.get("topic_tags", [])}
    conclusion = str(record.get("conclusion_tag", "")).lower()
    pattern_tag = str(record.get("pattern_tag", "")).lower()
    if topics.intersection({"security", "privacy", "compliance", "ai-security", "defense"}):
        pillar = "P1-news"
        category = "セキュリティ"
    elif topics.intersection({"business", "strategy", "decision", "risk", "cost"}):
        pillar = "P3"
        category = "経営判断"
    elif topics.intersection({"medical-ai", "medical", "medicine", "clinical", "diagnosis", "governance", "policy", "scaling"}):
        pillar = "P1"
        category = "医療AIガバナンス"
    elif topics.intersection({"workflow", "tool", "ops", "productivity", "ai-tools", "harness", "quality", "orchestrator", "llm", "local-llm"}):
        pillar = "P2"
        category = "AI活用/運用"
    elif topics.intersection({"career", "mindset", "growth", "personal_growth"}):
        pillar = "P3"
        category = "キャリア/マインドセット"
    else:
        pillar = "P2"
        category = "AI/本質論"

    pattern_map = {
        "explicit_quote": "X投稿引用",
        "quoted": "X投稿引用",
        "quoted_agreement": "引用共鳴",
        "reply": "対話派生",
        "original": "視点提示",
    }
    pattern = pattern_map.get(pattern_tag, "")
    if not pattern:
        if conclusion in {"agreement", "possible_with_vitality"}:
            pattern = "本質提示"
        elif conclusion in {"broader_view", "confirmation_layers"}:
            pattern = "構造整理"
        else:
            pattern = "一次情報分析"
    return pillar, category, pattern


def concept_label(record: dict) -> str:
    mapping = {
        "vitality_over_age": "年齢ではなく活力で見直す視点",
        "possible_with_vitality": "活力が可能性を広げる視点",
        "vitality_suffices": "活力が可能性を広げる視点",
        "agreement": "短い言葉が本質を突く瞬間",
        "broader_view": "視野を一段広げる問い",
        "confirmation_layers": "確認層を増やして強くする発想",
        "local_llm_recommended": "制約下で最適解を組み直す視点",
    }
    conclusion = str(record.get("conclusion_tag", ""))
    if conclusion in mapping:
        return mapping[conclusion]
    topic_label = topic_phrase(record)
    if topic_label:
        return f"{topic_label}を実務へ引き戻す視点"
    return "実務を一段深くする視点"


def topic_phrase(record: dict) -> str:
    tags = [str(tag).strip() for tag in record.get("topic_tags", []) if str(tag).strip()]
    if not tags:
        return "AI活用"
    tags = sorted(
        tags,
        key=lambda raw: (
            -TOPIC_PRIORITY.get(str(raw).lower(), 2),
            str(raw).lower() in GENERIC_TOPICS,
            str(raw).lower(),
        ),
    )
    labels = []
    seen = set()
    for tag in tags:
        lowered = tag.lower()
        label = TAG_LABELS.get(lowered)
        if not label and re.fullmatch(r"[a-z0-9 _-]+", lowered):
            label = TAG_LABELS.get(lowered.replace("_", " ").replace("-", " "))
        if not label:
            label = tag.replace("-", " ").replace("_", " ").strip() or "AI活用"
        if label in seen:
            continue
        labels.append(label)
        seen.add(label)
        if len(labels) >= 2:
            break
    return "、".join(labels) if labels else "AI活用"


def source_assertions(record: dict) -> list[str]:
    handle = record.get("author_handle", "")
    concept = concept_label(record)
    source_url = record.get("source_url", "")
    primary_url = primary_source_url(record)
    assertions = []
    if handle:
        assertions.append(f"@{handle} の投稿を手がかりに、{concept}を一般化して捉え直す。")
    else:
        assertions.append(f"外部投稿を手がかりに、{concept}を一般化して捉え直す。")
    if primary_url:
        assertions.append(f"Primary source: {primary_url}")
    if source_url and source_url != primary_url:
        assertions.append(f"Discovery source: {source_url}")
    return assertions


def primary_source_url(record: dict) -> str:
    metadata = record.get("metadata", {}) or {}
    for key in ("primary_source_url", "external_source_url", "canonical_article_url"):
        value = str(metadata.get(key, "")).strip()
        if value and not is_x_url(value):
            return value
    return ""


def has_untraceable_numeric_claim(text: str) -> bool:
    return bool(NUMERIC_CLAIM_RE.search(text or ""))


def has_unsupported_authority_reference(text: str) -> bool:
    return bool(UNSUPPORTED_AUTHORITY_RE.search(text or ""))


def tone_balance_violation_reason(text: str, tone_profile: str = "middle") -> str | None:
    normalized = sanitize_text(text or "")
    if not normalized:
        return None

    assertive_hits = len(ASSERTIVE_TONE_RE.findall(normalized))
    if assertive_hits >= 2:
        return "tone-balance-assertive-overload"

    sentences = [chunk.strip() for chunk in SENTENCE_SPLIT_RE.split(normalized) if chunk.strip()]
    if not sentences:
        return None

    polite_sentences = sum(1 for sentence in sentences if POLITE_ENDING_RE.search(sentence))
    if tone_profile != "polite" and assertive_hits == 0 and (polite_sentences / len(sentences)) >= 0.7:
        return "tone-balance-overpolite-overload"

    return None


def is_x_url(url: str) -> bool:
    lowered = url.lower()
    return "x.com/" in lowered or "twitter.com/" in lowered


def source_domain(url: str) -> str:
    if not url:
        return ""
    parsed = urllib.parse.urlparse(url)
    return parsed.netloc.lower()


def family_key(record: dict) -> str:
    conclusion = str(record.get("conclusion_tag", "")).strip().lower()
    pattern_tag = str(record.get("pattern_tag", "")).strip().lower()
    return f"{conclusion}::{pattern_tag}"


def normalize_text_for_similarity(text: str) -> str:
    text = sanitize_text(text).lower()
    text = re.sub(r"\s+", "", text)
    return text


def char_ngrams(text: str, n: int = 3) -> set[str]:
    if len(text) < n:
        return {text} if text else set()
    return {text[i : i + n] for i in range(0, len(text) - n + 1)}


def text_similarity(left: str, right: str) -> float:
    left_set = char_ngrams(normalize_text_for_similarity(left))
    right_set = char_ngrams(normalize_text_for_similarity(right))
    if not left_set or not right_set:
        return 0.0
    overlap = left_set & right_set
    union = left_set | right_set
    return len(overlap) / len(union)


def draft_signature(candidate: dict) -> str:
    return f"{candidate.get('title', '')}\n{candidate.get('body', '')}"


def summarize_recent_history(recent_drafts: list[dict]) -> dict:
    summary = {
        "domains": set(),
        "authors": set(),
        "categories": set(),
        "families": set(),
        "signatures": [],
    }
    for draft in recent_drafts:
        source_url = str(draft.get("source_url", "")).strip()
        if source_url:
            summary["domains"].add(source_domain(source_url))
        author_handle = str(draft.get("quoted_author_handle", "")).strip().lower()
        if author_handle:
            summary["authors"].add(author_handle)
        category = str(draft.get("category", "")).strip()
        if category:
            summary["categories"].add(category)
        diversity_hint = draft.get("diversity_hint", {}) or {}
        family = f"{str(diversity_hint.get('conclusion_tag', '')).strip().lower()}::{str(diversity_hint.get('pattern_tag', '')).strip().lower()}"
        if family != "::":
            summary["families"].add(family)
        signature = draft_signature(draft)
        if signature.strip():
            summary["signatures"].append(signature)
    return summary


def contains_proper_noun_leak(text: str, record: dict) -> bool:
    lowered = text.lower()
    if "http://" in lowered or "https://" in lowered or "x.com/" in lowered or "twitter.com/" in lowered:
        return True
    author_handle = str(record.get("author_handle", "")).lower()
    if author_handle and author_handle in lowered:
        return True
    return any(token in lowered for token in PROPER_NOUN_BLOCKLIST)


def sanitize_text(text: str) -> str:
    text = re.sub(r"https?://\S+", "", text)
    text = re.sub(r"@[A-Za-z0-9_]+", "ある発信", text)
    for token in PROPER_NOUN_BLOCKLIST:
        text = re.sub(token, "ある組織", text, flags=re.IGNORECASE)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def heuristic_draft(record: dict, min_chars: int) -> dict:
    pillar, category, pattern = map_category(record)
    concept = concept_label(record)
    topic_label = topic_phrase(record)
    variant = int(hashlib.sha256(stable_record_key(record).encode("utf-8")).hexdigest()[:8], 16) % 3
    category_focus = {
        "セキュリティ": "守りの設計",
        "経営判断": "意思決定の条件",
        "医療AIガバナンス": "説明責任と運用条件",
        "AI活用/運用": "再現可能な運用設計",
        "キャリア/マインドセット": "視点の置き方",
        "AI/本質論": "判断条件の整理",
    }.get(category, "判断条件の整理")
    category_risk = {
        "セキュリティ": "安全策が後付けになると、導入後に止め方だけが議論になりやすい。",
        "経営判断": "判断軸が曖昧なままだと、良い実験でも組織に残る学びへ変わりにくい。",
        "医療AIガバナンス": "精度だけを見ても、説明責任や監督体制が薄いと現場には定着しない。",
        "AI活用/運用": "便利さだけで進めると、担当者依存の運用になって再現性を失いやすい。",
        "キャリア/マインドセット": "納得感だけで受け取ると、次の行動へつながる学びになりにくい。",
        "AI/本質論": "言い切りだけで捉えると、実務へ持ち込む条件が抜け落ちやすい。",
    }.get(category, "強い結論だけで捉えると、実務へ持ち込む条件が抜け落ちやすい。")
    category_action = {
        "セキュリティ": f"{topic_label}を扱うなら、想定外の入力でどう止めるかまで先に置くほうが実装へつなげやすい。",
        "経営判断": f"{topic_label}を経営の論点として扱うなら、何を捨てず何を優先するかを明文化しておくほうが扱いやすい。",
        "医療AIガバナンス": f"{topic_label}を現場へ持ち込むなら、説明の順番と監督の置き場を先に決めておくほうが安定しやすい。",
        "AI活用/運用": f"{topic_label}を業務へ乗せるなら、誰でも同じ結果に寄せられる運用線を作ることが先になりやすい。",
        "キャリア/マインドセット": f"{topic_label}を自分の仕事へ引き戻すなら、次の判断をどう変えるかまで言葉にしておきたい。",
        "AI/本質論": f"{topic_label}は、便利さの話よりも先に前提条件を並べ替える材料として読むと使いやすい。",
    }.get(category, f"{topic_label}を扱うときは、前提条件と判断点を先に整理したほうが長く使いやすい。")
    title_templates = {
        "X投稿引用": [
            f"{topic_label}を短い投稿から考え直す",
            f"{topic_label}を現場目線で読み替える",
            f"{topic_label}から実務の論点を引き出す",
        ],
        "引用共鳴": [
            f"{topic_label}は短い共感で輪郭が出る",
            f"{topic_label}の本質は短い反応に表れる",
            f"{topic_label}は一言の反応で深さが見える",
        ],
        "対話派生": [
            f"{topic_label}は問い返しで深くなる",
            f"{topic_label}は対話にすると設計が見える",
            f"{topic_label}は反応の差で論点が浮く",
        ],
        "構造整理": [
            f"{topic_label}は確認層で強くなる",
            f"{topic_label}は構造化すると実装しやすい",
            f"{topic_label}は整理した瞬間に運用へ近づく",
        ],
        "本質提示": [
            f"{topic_label}を実務へ戻す視点",
            f"{topic_label}の本質を現場の言葉へ戻す",
            f"{topic_label}は結論より前提で決まる",
        ],
        "一次情報分析": [
            f"{topic_label}を一次情報から見直す",
            f"{topic_label}は一次情報で輪郭が変わる",
            f"{topic_label}は元ネタまで辿ると違って見える",
        ],
        "視点提示": [
            f"{topic_label}を一段深く考える",
            f"{topic_label}は視点を変えるだけで実装が変わる",
            f"{topic_label}を判断条件から捉え直す",
        ],
    }
    title = title_templates.get(pattern, [f"{topic_label}を実務へ引き戻す"])[variant % len(title_templates.get(pattern, [f"{topic_label}を実務へ引き戻す"]))]
    intro_templates = [
        f"最近、{concept}を思い出させる材料に触れて、改めて大事なのは発信の強さそのものではなく、そこから何を実務へ持ち帰るかだと感じた。",
        f"{concept}という論点は、短い発信ほど本質だけが残る。だからこそ表現の勢いより、どんな判断条件が背後にあるかを拾い直したい。",
        f"短い発信でも、{concept}のように仕事の見方を変える材料になることがある。見るべきなのは結論の派手さではなく、その結論が成立する条件だ。",
    ]
    diagnosis_templates = [
        f"{topic_label}は便利さの話に見えても、実際には{category_focus}の話へ戻ってくる。{category_risk}",
        f"{topic_label}の論点は賛成か反対かに流れやすいが、実装で効くのは{category_focus}をどう置くかだ。{category_risk}",
        f"{topic_label}を扱うときに差が出るのは、機能の多さよりも{category_focus}を先に描けるかどうかだ。{category_risk}",
    ]
    pivot_templates = [
        f"今回の材料は、{concept}を感想で終わらせず、判断条件へ翻訳し直す必要があることを示している。{category_action}",
        f"重要なのは、{concept}を引用のための強い一言として消費しないことだ。{category_action}",
        f"要するに、{concept}は勢いのある断言より、条件を並べ替える入口として読むほうが使いやすい。{category_action}",
    ]
    application_templates = [
        f"現場で問うべきなのは、{topic_label}を入れるかどうかではなく、どの前提を先に明文化するかだ。責任の置き方、確認の順番、止めどころまで言葉にすると議論を前へ進めやすい。",
        f"{topic_label}を本当に使える知見へ変えるには、誰の不安に答える話なのか、どの工程を変える話なのかを分けて考えたほうが扱いやすい。そこで初めて発信は運用の材料になりやすい。",
        f"{topic_label}は結論だけ抜き出すと既視感へ戻りやすい。前提条件、例外時の扱い、継続の条件まで並べると、実務の言葉として使いやすくなる。",
    ]
    closing_templates = [
        f"結局、{topic_label}で差が出やすいのは派手な結論ではなく、成立条件を先に整えられるかどうかだ。短い発信を深い学びへ変えるには、その翻訳の手間を惜しまないほうがいい。",
        f"短い発信から大きな論点を取り出せる組織は、流行だけで動きにくい。{topic_label}も、条件付きで読み直すだけでずっと長く使える知見になる。",
        f"{topic_label}は答えを急ぐテーマほど、条件整理の質が効く。発信の熱量を借りるより、自分たちの判断線へ引き直すほうが結果として強い。",
    ]
    supplement_templates = [
        f"とくに{category}の文脈では、導入判断よりも先に『何が揃えば進めてよいか』を言える状態を作ることが重要になる。",
        f"{topic_label}をめぐる議論は広がりやすいが、判断点を三つ程度に絞るだけでも実務の解像度はかなり上がる。",
        f"引用だけが増える状態を避けるには、次の会話で何を確認するかまで残す運用に変えるのが有効だ。",
        f"{topic_label}を扱うチームほど、例外時の扱いと責任の所在を先に言葉にしておくと、後戻りのコストをかなり下げられる。",
        f"短い発信をその場の感想で終わらせず、判断条件のメモとして残すだけでも、次回の議論はかなり具体的になる。",
        f"{category_focus}を先に描けるかどうかで、同じ情報を見ても次の一手の質は大きく変わる。",
        f"{topic_label}は流行語として消費しやすいが、確認項目へ翻訳した瞬間に初めて運用の知見になる。",
    ]
    paragraphs = [
        intro_templates[variant],
        diagnosis_templates[(variant + 1) % len(diagnosis_templates)],
        pivot_templates[(variant + 2) % len(pivot_templates)],
        application_templates[variant],
        closing_templates[(variant + 1) % len(closing_templates)],
    ]
    used = set(paragraphs)
    rotated_supplements = supplement_templates[variant:] + supplement_templates[:variant]
    for supplement in rotated_supplements:
        if len(sanitize_text("\n\n".join(paragraphs))) >= min_chars:
            break
        if supplement in used:
            continue
        paragraphs.append(supplement)
        used.add(supplement)
    tail_templates = [
        f"要するに、{topic_label}をめぐる議論は結論の強さよりも条件整理の質で差が出やすい。だからこそ一次情報や元の文脈まで辿り、判断線を自分の言葉で引き直す姿勢は外しにくい。",
        f"最終的には、{topic_label}をどう評価するかより、どの条件で採用し、どの条件で止めるかを言える状態を作ることが実務では効いてくる。",
        f"{topic_label}を長く使える知見に変えるには、熱量の強い表現よりも、次の判断に使える条件整理として残すほうが機能しやすい。",
    ]
    tail_idx = 0
    while len(sanitize_text("\n\n".join(paragraphs))) < min_chars:
        tail = tail_templates[(variant + tail_idx) % len(tail_templates)] if tail_idx < len(tail_templates) else f"{topic_label}については、誰がどう判断し、何を確認し、どこで止めるかまで具体化して初めて実務の知見になる。"
        if tail not in used:
            paragraphs.append(tail)
            used.add(tail)
        tail_idx += 1
        if tail_idx > len(tail_templates) + 2:
            break
    body = sanitize_text("\n\n".join(paragraphs))
    if len(body) < min_chars:
        body = body + "\n\n" + sanitize_text(f"{topic_label}を扱うときは、前提条件、例外時の扱い、説明の順番を揃えて初めて継続可能な運用になる。この確認を省かない姿勢そのものが、短い発信を長く使える知見へ変える。")
    return {
        "title": title,
        "body": body,
        "pillar": pillar,
        "category": category,
        "pattern": pattern,
        "source_assertions": source_assertions(record),
    }


def generate_with_xai(record: dict, min_chars: int) -> dict:
    api_key = os.getenv("XAI_API_KEY", "")
    if not api_key:
        raise RuntimeError("missing XAI_API_KEY")
    model = os.getenv("FUGUE_XAI_MODEL", os.getenv("XAI_MODEL", DEFAULT_MODEL))
    pillar, category, pattern = map_category(record)
    concept = concept_label(record)
    body_prompt = {
        "record": {
            "author_handle": record.get("author_handle", ""),
            "topic_tags": record.get("topic_tags", []),
            "conclusion_tag": record.get("conclusion_tag", ""),
            "pattern_tag": record.get("pattern_tag", ""),
            "source_url": record.get("source_url", ""),
            "concept": concept,
        },
        "target": {
            "pillar": pillar,
            "category": category,
            "pattern": pattern,
            "body_chars_min": min_chars,
            "body_chars_max": 1500,
        },
        "rules": [
            "Return JSON only.",
            "Write in Japanese.",
            "Do not include URLs in title or body.",
            "Do not include handles, company names, product names, or brand names in title or body.",
            "Use 4 compact paragraphs with a practical editorial tone.",
            "Keep the Japanese tone in the middle register: calm plain-form by default, avoid absolute assertions, and avoid making every sentence polite.",
            "Use light softening only where certainty is limited, and do not stack hard assertions across consecutive sentences.",
            "Keep source_assertions as a short array of 1-2 internal justification strings.",
        ],
        "output_schema": {
            "title": "string",
            "body": "string",
            "source_assertions": ["string"],
        },
    }
    body = {
        "model": model,
        "input": [
            {
                "role": "user",
                "content": "Generate one x-auto draft candidate as strict JSON.\n" + json.dumps(body_prompt, ensure_ascii=False),
            }
        ],
        "temperature": 0.2,
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    res = sync_helper.http_json("POST", sync_helper.XAI_BASE, headers, body)
    output_text_parts = []
    for item in res.get("output", []):
        for content in item.get("content", []):
            if content.get("type") in ("output_text", "text"):
                output_text_parts.append(content.get("text", ""))
    raw_text = "".join(output_text_parts).strip()
    draft = json.loads(raw_text)
    draft["pillar"] = map_category(record)[0]
    draft["category"] = map_category(record)[1]
    draft["pattern"] = map_category(record)[2]
    draft["body"] = sanitize_text(draft.get("body", ""))
    draft["title"] = sanitize_text(draft.get("title", ""))
    return draft


def compute_diversity_score(record: dict, candidate: dict, accepted: list[dict], recent_history: dict) -> float:
    score = 0.45
    author_handle = str(record.get("author_handle", "")).strip().lower()
    category = str(candidate.get("category", "")).strip()
    family = family_key(record)
    primary_url = primary_source_url(record)
    domain = source_domain(primary_url or candidate.get("source_url", ""))
    topics = topic_set(record)
    non_medical = not topics.intersection({"medical", "medicine", "clinical", "diagnosis", "healthcare"})

    if primary_url:
        score += 0.2
        score += 0.08 * primary_source_confidence(record)
        score += 0.02 * primary_source_strategy_rank(record)
    elif not is_x_url(candidate.get("source_url", "")):
        score += 0.1
    else:
        score -= 0.12

    accepted_authors = {str(item.get("quoted_author_handle", "")).strip().lower() for item in accepted}
    accepted_domains = {source_domain(item.get("source_url", "")) for item in accepted}
    accepted_categories = {str(item.get("category", "")).strip() for item in accepted}
    accepted_families = {
        f"{str((item.get('diversity_hint', {}) or {}).get('conclusion_tag', '')).strip().lower()}::{str((item.get('diversity_hint', {}) or {}).get('pattern_tag', '')).strip().lower()}"
        for item in accepted
    }

    if author_handle and author_handle in accepted_authors:
        score -= 0.14
    elif author_handle:
        score += 0.08
    if domain and domain in accepted_domains:
        score -= 0.12
    elif domain:
        score += 0.08
    if category and category in accepted_categories:
        score -= 0.06
    elif category:
        score += 0.04
    if family != "::" and family in accepted_families:
        score -= 0.18
    elif family != "::":
        score += 0.06
    if non_medical:
        score += 0.08

    if author_handle and author_handle in recent_history["authors"]:
        score -= 0.06
    if domain and domain in recent_history["domains"]:
        score -= 0.05
    if family != "::" and family in recent_history["families"]:
        score -= 0.08
    if category and category in recent_history["categories"]:
        score -= 0.04

    return max(0.0, min(1.0, round(score, 3)))


def similarity_to_recent(candidate: dict, accepted: list[dict], recent_history: dict) -> float:
    signature = draft_signature(candidate)
    comparisons = [draft_signature(item) for item in accepted] + list(recent_history["signatures"])
    if not comparisons:
        return 0.0
    return round(max(text_similarity(signature, other) for other in comparisons), 3)


def build_candidate_payload(record: dict, draft: dict, idx: int, today: str, tone_profile: str) -> dict:
    candidate = {
        "draft_id": f"{today}-xauto-local-{idx:02d}",
        "schema_version": "x-auto-draft-candidate.v1",
        "record_key": stable_record_key(record),
        "source_hash": str(record.get("source_hash", "") or (record.get("metadata", {}) or {}).get("source_hash", "")),
        "event_hash": str(record.get("event_hash", "") or (record.get("metadata", {}) or {}).get("event_hash", "")),
        "title": draft["title"],
        "status": "draft",
        "posted": False,
        "scheduled_for": "",
        "source_url": record.get("source_url", ""),
        "source_urls": [record.get("source_url", "")],
        "body": draft["body"],
        "body_ja": draft["body"],
        "text": draft["body"],
        "image_path": None,
        "tweet_id": None,
        "pillar": draft["pillar"],
        "category": draft["category"],
        "pattern": draft["pattern"],
        "notion_page_id": None,
        "source_assertions": draft.get("source_assertions") or source_assertions(record),
        "quoted_author_handle": record.get("author_handle", ""),
        "dispatchable": False,
        "promotable": False,
        "tone_profile": tone_profile,
        "diversity_hint": {
            "conclusion_tag": record.get("conclusion_tag", ""),
            "pattern_tag": record.get("pattern_tag", ""),
            "topic_tags": record.get("topic_tags", []),
            "confidence": record.get("metadata", {}).get("confidence", None),
            "primary_source_url": primary_source_url(record),
            "source_domain": source_domain(primary_source_url(record) or record.get("source_url", "")),
            "primary_source_strategy": record.get("metadata", {}).get("primary_source_strategy", ""),
            "primary_source_confidence": record.get("metadata", {}).get("primary_source_confidence", None),
        },
    }
    primary_url = primary_source_url(record)
    if primary_url:
        candidate["source_urls"] = list(dict.fromkeys([primary_url, record.get("source_url", "")]))
        candidate["source_url"] = primary_url
        candidate["review_eligibility"] = "eligible"
        candidate["review_blockers"] = []
    elif is_x_url(record.get("source_url", "")):
        candidate["review_eligibility"] = "blocked"
        candidate["review_blockers"] = ["missing-non-x-primary-source"]
    else:
        candidate["review_eligibility"] = "eligible"
        candidate["review_blockers"] = []
    return candidate


def build_candidate(record: dict, idx: int, min_chars: int, generate_mode: str, tone_profile: str, today: str) -> tuple[dict | None, dict | None]:
    try:
        if generate_mode == "heuristic":
            draft = heuristic_draft(record, min_chars)
        else:
            try:
                draft = generate_with_xai(record, min_chars)
            except Exception:
                draft = heuristic_draft(record, min_chars)
        if len(draft["body"]) < min_chars:
            draft = heuristic_draft(record, min_chars)
        if contains_proper_noun_leak(draft["title"], record) or contains_proper_noun_leak(draft["body"], record):
            draft = heuristic_draft(record, min_chars)
        if contains_proper_noun_leak(draft["title"], record) or contains_proper_noun_leak(draft["body"], record):
            return None, {"reason": "proper-noun-or-url-leak", "record": record}
        if has_unsupported_authority_reference(draft["title"]) or has_unsupported_authority_reference(draft["body"]):
            return None, {"reason": "unsupported-authority-reference", "record": record}
        if has_untraceable_numeric_claim(draft["title"]) or has_untraceable_numeric_claim(draft["body"]):
            return None, {"reason": "untraceable-numeric-claim", "record": record}
        candidate = build_candidate_payload(record, draft, idx, today, tone_profile)
        tone_balance_reason = tone_balance_violation_reason(draft["body"], tone_profile)
        if tone_balance_reason:
            candidate["review_eligibility"] = "blocked"
            candidate["review_blockers"] = list(dict.fromkeys(candidate.get("review_blockers", []) + [tone_balance_reason]))
        return candidate, None
    except Exception as exc:
        return None, {"reason": "generation-error", "error": str(exc), "record": record}


def blocked_reason_text(reason: str) -> str:
    return {
        "missing-non-x-primary-source": "非Xの一次情報ソースが見つからないため、レビュー対象に昇格できない。",
        "low-diversity-score": "最近の採用候補と比べて多様性が不足している。",
        "too-similar-to-recent": "最近の採用候補と本文・論点が近すぎる。",
        "candidate-limit-reached": "採用上限に達したため今回は見送る。",
        "tone-balance-assertive-overload": "断定が連続しすぎており、中間トーンの publish 基準から外れている。",
        "tone-balance-overpolite-overload": "です/ます調に寄りすぎており、中間トーンの publish 基準から外れている。",
    }.get(reason, "追加の確認が必要なため今回は保留。")


def blocked_operator_action(reason: str, record: dict, candidate: dict | None = None) -> str:
    if reason == "missing-non-x-primary-source":
        handle = str(record.get("author_handle", "")).strip()
        if handle:
            return f"@{handle} の元投稿・同一スレッド・外部リンク先を再探索し、非X一次情報URLを補完する。"
        return "元投稿と関連スレッドを再探索し、非X一次情報URLを補完する。"
    if reason == "low-diversity-score":
        return "同一カテゴリ・同一発信者の直近候補を減らし、別ドメイン候補を優先する。"
    if reason == "too-similar-to-recent":
        return "本文骨格を再生成するか、別の論点ファミリへ差し替える。"
    if reason == "candidate-limit-reached":
        return "今回は保留し、次回バッチで再評価する。"
    if reason == "tone-balance-assertive-overload":
        return "強い断定を減らし、観察・条件・含みを入れた常体へ戻す。"
    if reason == "tone-balance-overpolite-overload":
        return "本文の主終止を常体へ戻し、丁寧語は landing line に限定する。"
    return "追加確認のうえ手動で再評価する。"


def annotate_blocked_candidate(candidate: dict, record: dict, reason: str) -> dict:
    annotated = dict(candidate)
    annotated["blocked_reason_canonical"] = reason
    annotated["blocked_reason_text"] = blocked_reason_text(reason)
    annotated["operator_action"] = blocked_operator_action(reason, record, candidate)
    annotated["metric_snapshot"] = {
        "diversity_score": annotated.get("diversity_score"),
        "similarity_to_recent": annotated.get("similarity_to_recent"),
        "review_blockers": annotated.get("review_blockers", []),
        "primary_source_url": ((annotated.get("diversity_hint", {}) or {}).get("primary_source_url", "")),
        "source_domain": ((annotated.get("diversity_hint", {}) or {}).get("source_domain", "")),
    }
    return annotated


def build_closeout(created: list[dict], blocked: list[dict], rejected: list[dict]) -> dict:
    reason_counts: dict[str, int] = {}
    blocked_draft_ids = {str(item.get("draft_id", "")).strip() for item in blocked if str(item.get("draft_id", "")).strip()}
    for item in blocked:
        reason = str(item.get("blocked_reason_canonical", "")).strip()
        if reason:
            reason_counts[reason] = reason_counts.get(reason, 0) + 1
    for item in rejected:
        draft_id = str(item.get("draft_id", "")).strip()
        if draft_id and draft_id in blocked_draft_ids:
            continue
        reason = str(item.get("reason", "")).strip()
        if reason and reason not in reason_counts:
            reason_counts[reason] = reason_counts.get(reason, 0) + 1
    backfill_targets = []
    for item in blocked:
        if item.get("blocked_reason_canonical") != "missing-non-x-primary-source":
            continue
        backfill_targets.append(
            {
                "draft_id": item.get("draft_id", ""),
                "title": item.get("title", ""),
                "quoted_author_handle": item.get("quoted_author_handle", ""),
                "source_url": item.get("source_url", ""),
                "source_domain": ((item.get("diversity_hint", {}) or {}).get("source_domain", "")),
                "suggested_action": item.get("operator_action", ""),
                "priority": "high" if safe_confidence((item.get("diversity_hint", {}) or {}).get("confidence", 0.0), 0.0) >= 0.8 else "normal",
            }
        )
    top_reason = max(reason_counts.items(), key=lambda kv: kv[1])[0] if reason_counts else ""
    next_actions = []
    if top_reason == "missing-non-x-primary-source":
        next_actions.append("blocked候補の元投稿・同一スレッド・外部リンク先を再探索して、非X一次情報URLを補完する。")
    if any(item.get("blocked_reason_canonical") == "too-similar-to-recent" for item in blocked):
        next_actions.append("既視感が強い候補は本文骨格を再生成するか、別ファミリ候補へ差し替える。")
    if any(str(item.get("blocked_reason_canonical", "")).startswith("tone-balance-") for item in blocked):
        next_actions.append("本文を常体ベースへ戻し、断定または丁寧語の偏りを解消して再生成する。")
    if not next_actions and created:
        next_actions.append("promotable 候補を優先してレビューし、残りは次回バッチで再評価する。")
    return {
        "status": "ready" if not blocked else "partial-blocked",
        "blocked_reason_counts": reason_counts,
        "backfill_targets": backfill_targets,
        "operator_next_actions": next_actions,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--handle", default=os.getenv("X_AUTO_QUOTED_AUTHOR_SYNC_HANDLE", "cursorvers"))
    parser.add_argument("--limit", type=int, default=int(os.getenv("X_AUTO_DRAFT_LOCAL_LIMIT", "20")))
    parser.add_argument("--max-candidates", type=int, default=3)
    parser.add_argument("--min-chars", type=int, default=800)
    parser.add_argument("--from-date", default=os.getenv("X_AUTO_QUOTED_AUTHOR_SYNC_FROM_DATE", ""))
    parser.add_argument("--to-date", default=os.getenv("X_AUTO_QUOTED_AUTHOR_SYNC_TO_DATE", ""))
    parser.add_argument("--extract-mode", default=os.getenv("X_AUTO_QUOTED_AUTHOR_SYNC_EXTRACT_MODE", "auto"))
    parser.add_argument("--generate-mode", default=os.getenv("X_AUTO_DRAFT_LOCAL_GENERATE_MODE", "auto"))
    parser.add_argument("--tone-profile", default=os.getenv("X_AUTO_DRAFT_TONE_PROFILE", "middle"))
    parser.add_argument("--registry-seed-input", default="")
    parser.add_argument("--posts-seed-input", default="")
    parser.add_argument("--recent-drafts-input", default=os.getenv("X_AUTO_DRAFT_RECENT_INPUT", ""))
    parser.add_argument("--registry-dump-output", default="")
    args = parser.parse_args()

    if args.generate_mode not in {"auto", "xai", "heuristic"}:
        raise RuntimeError("generate-mode must be auto|xai|heuristic")
    if args.tone_profile not in TONE_PROFILES:
        raise RuntimeError("tone-profile must be middle|polite")
    records = load_registry_records(args)
    if args.registry_dump_output:
        dump_path = Path(args.registry_dump_output)
        dump_path.parent.mkdir(parents=True, exist_ok=True)
        with open(dump_path, "w", encoding="utf-8") as fh:
            json.dump({"records": records}, fh, ensure_ascii=False, indent=2)
    recent_drafts = load_recent_drafts(args.recent_drafts_input)
    candidate_pool_size = max(args.max_candidates * 3, args.max_candidates)
    chosen_records, rejected = dedupe_and_select(records, candidate_pool_size)
    created = []
    accepted = []
    blocked = []
    recent_history = summarize_recent_history(recent_drafts)
    today = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d")
    for idx, record in enumerate(chosen_records, start=1):
        generate_mode = "heuristic" if args.generate_mode == "heuristic" else "auto"
        candidate, error = build_candidate(record, idx, args.min_chars, generate_mode, args.tone_profile, today)
        if candidate:
            candidate["diversity_score"] = compute_diversity_score(record, candidate, accepted, recent_history)
            candidate["similarity_to_recent"] = similarity_to_recent(candidate, accepted, recent_history)
            candidate["acceptance_status"] = "pending-review"
            candidate["acceptance_reasons"] = []
            if candidate["review_eligibility"] != "eligible":
                blocking_reason = candidate.get("review_blockers", ["missing-non-x-primary-source"])[0]
                candidate["acceptance_status"] = "rejected"
                candidate["acceptance_reasons"].append("review-eligibility-blocked")
                candidate["acceptance_reasons"].append(blocking_reason)
                candidate = annotate_blocked_candidate(candidate, record, blocking_reason)
                blocked.append(candidate)
                rejected.append(
                    {
                        "reason": "review-eligibility-blocked",
                        "draft_id": candidate["draft_id"],
                        "review_blockers": candidate.get("review_blockers", []),
                        "blocking_reason": blocking_reason,
                        "record": record,
                    }
                )
            elif candidate["diversity_score"] < DIVERSITY_THRESHOLD:
                candidate["acceptance_status"] = "rejected"
                candidate["acceptance_reasons"].append("low-diversity-score")
                candidate = annotate_blocked_candidate(candidate, record, "low-diversity-score")
                blocked.append(candidate)
                rejected.append(
                    {
                        "reason": "low-diversity-score",
                        "draft_id": candidate["draft_id"],
                        "diversity_score": candidate["diversity_score"],
                        "record": record,
                    }
                )
            elif candidate["similarity_to_recent"] > SIMILARITY_THRESHOLD:
                candidate["acceptance_status"] = "rejected"
                candidate["acceptance_reasons"].append("too-similar-to-recent")
                candidate = annotate_blocked_candidate(candidate, record, "too-similar-to-recent")
                blocked.append(candidate)
                rejected.append(
                    {
                        "reason": "too-similar-to-recent",
                        "draft_id": candidate["draft_id"],
                        "similarity_to_recent": candidate["similarity_to_recent"],
                        "record": record,
                    }
                )
            elif len(accepted) >= args.max_candidates:
                candidate["acceptance_status"] = "rejected"
                candidate["acceptance_reasons"].append("candidate-limit-reached")
                candidate = annotate_blocked_candidate(candidate, record, "candidate-limit-reached")
                blocked.append(candidate)
                rejected.append(
                    {
                        "reason": "candidate-limit-reached",
                        "draft_id": candidate["draft_id"],
                        "record": record,
                    }
                )
            else:
                candidate["acceptance_status"] = "accepted"
                candidate["dispatchable"] = True
                candidate["promotable"] = True
                accepted.append(candidate)
            created.append(candidate)
        elif error:
            rejected.append(error)
    result = {
        "generator": "registry-local.v1",
        "created": created,
        "accepted": accepted,
        "promotable": accepted,
        "blocked": blocked,
        "rejected": rejected,
        "closeout": build_closeout(created, blocked, rejected),
        "summary": {
            "created_count": len(created),
            "accepted_count": len(accepted),
            "promotable_count": len(accepted),
            "blocked_count": len(blocked),
            "rejected_count": len(rejected),
            "input_records_count": len(records),
            "selected_records_count": len(chosen_records),
        },
    }
    json.dump(result, sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
