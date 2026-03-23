#!/usr/bin/env python3
import argparse
import collections
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

try:
    from config import POST_QUEUE_FILE
except Exception:
    POST_QUEUE_FILE = Path(__file__).resolve().parent / "post_queue.json"

MAX_DAILY_POSTS = 3
QUEUE_FILE = Path(POST_QUEUE_FILE)
SCHEDULE_FORMAT = "%Y-%m-%d %H:%M"
NOTE_MARKER = "note.com/"
TERMINAL_STATUSES = {"posted", "failed", "missed", "duplicate_blocked"}


def load_posts(queue_file):
    with queue_file.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, list):
        raise ValueError(f"{queue_file} must contain a JSON array")
    return data


def save_posts(queue_file, posts):
    with queue_file.open("w", encoding="utf-8") as handle:
        json.dump(posts, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def parse_scheduled(value):
    text = str(value or "").strip()
    if not text:
        return None
    try:
        return datetime.strptime(text, SCHEDULE_FORMAT)
    except ValueError:
        return None


def normalize_text(text):
    collapsed = " ".join(str(text or "").split())
    return collapsed.lower()


def text_prefix(text, limit=100):
    return normalize_text(text)[:limit]


def meaningful_text_length(text):
    return len(" ".join(str(text or "").split()))


def contains_note_link(post):
    return NOTE_MARKER in str(post.get("text", "")).lower()


def has_image(post):
    return bool(str(post.get("image_path", "")).strip())


def post_title(post):
    title = str(post.get("title", "")).strip()
    if title:
        return title
    post_id = str(post.get("id", "")).strip()
    if post_id:
        return f"[{post_id}]"
    return "[untitled]"


def is_non_terminal(post):
    return str(post.get("status", "")).strip() not in TERMINAL_STATUSES


def is_orphan_notion(post):
    notion_page_id = str(post.get("notion_page_id", "")).strip()
    title = str(post.get("title", "")).strip()
    return bool(notion_page_id) and not title and meaningful_text_length(post.get("text", "")) < 10


def resolve_image_path(image_path, base_dir):
    raw_path = str(image_path or "").strip()
    if not raw_path:
        return None
    path = Path(os.path.expanduser(raw_path))
    if not path.is_absolute():
        path = base_dir / path
    return path


def make_issue(check, severity, posts, detail):
    return {
        "check": check,
        "severity": severity,
        "posts": posts,
        "detail": detail,
    }


def audit_posts(posts, now=None):
    now = now or datetime.now()
    issues = []
    approved_posts = [post for post in posts if str(post.get("status", "")).strip() == "approved"]

    duplicate_text_groups = collections.defaultdict(list)
    for post in posts:
        if not is_non_terminal(post):
            continue
        prefix = text_prefix(post.get("text", ""))
        if prefix:
            duplicate_text_groups[prefix].append(post)
    for prefix, group in duplicate_text_groups.items():
        if len(group) > 1:
            issues.append(
                make_issue(
                    "DUPLICATE_TEXT",
                    "error",
                    [post_title(post) for post in group],
                    f"{len(group)} non-terminal posts share the same normalized first 100 chars: {prefix[:60]!r}",
                )
            )

    duplicate_schedule_groups = collections.defaultdict(list)
    for post in approved_posts:
        scheduled_for = str(post.get("scheduled_for", "")).strip()
        if scheduled_for:
            duplicate_schedule_groups[scheduled_for].append(post)
    for scheduled_for, group in duplicate_schedule_groups.items():
        if len(group) > 1:
            issues.append(
                make_issue(
                    "DUPLICATE_SCHEDULE",
                    "error",
                    [post_title(post) for post in group],
                    f"{len(group)} approved posts are scheduled for {scheduled_for}",
                )
            )

    approved_by_date = collections.defaultdict(list)
    for post in approved_posts:
        scheduled_at = parse_scheduled(post.get("scheduled_for"))
        if scheduled_at is not None:
            approved_by_date[scheduled_at.date().isoformat()].append(post)
    for day, group in approved_by_date.items():
        if len(group) > MAX_DAILY_POSTS:
            issues.append(
                make_issue(
                    "DAILY_OVERLOAD",
                    "error",
                    [post_title(post) for post in group],
                    f"{day} has {len(group)} approved posts (max {MAX_DAILY_POSTS})",
                )
            )

    for post in posts:
        status = str(post.get("status", "")).strip()
        if status in {"approved", "draft"} and not str(post.get("title", "")).strip():
            issues.append(
                make_issue(
                    "MISSING_TITLE",
                    "warning",
                    [post_title(post)],
                    f"{status} post is missing a title",
                )
            )

    for post in posts:
        if contains_note_link(post) and has_image(post):
            issues.append(
                make_issue(
                    "NOTE_WITH_IMAGE",
                    "warning",
                    [post_title(post)],
                    "note.com post has image_path set",
                )
            )

    for post in approved_posts:
        if not contains_note_link(post) and not has_image(post):
            issues.append(
                make_issue(
                    "NON_NOTE_WITHOUT_IMAGE",
                    "error",
                    [post_title(post)],
                    "approved non-note post is missing image_path",
                )
            )

    for post in posts:
        image_path = resolve_image_path(post.get("image_path", ""), QUEUE_FILE.parent)
        if image_path is not None and not os.path.exists(image_path):
            issues.append(
                make_issue(
                    "IMAGE_FILE_MISSING",
                    "error",
                    [post_title(post)],
                    f"image file does not exist: {image_path}",
                )
            )

    past_cutoff = now - timedelta(minutes=30)
    for post in approved_posts:
        scheduled_at = parse_scheduled(post.get("scheduled_for"))
        if scheduled_at is not None and scheduled_at < past_cutoff:
            issues.append(
                make_issue(
                    "PAST_SCHEDULE",
                    "warning",
                    [post_title(post)],
                    f"approved post is scheduled in the past: {scheduled_at.strftime(SCHEDULE_FORMAT)}",
                )
            )

    for post in posts:
        if is_orphan_notion(post):
            issues.append(
                make_issue(
                    "ORPHAN_NOTION",
                    "warning",
                    [post_title(post)],
                    "notion_page_id is present but title is empty and text is shorter than 10 chars",
                )
            )

    has_error = any(issue["severity"] == "error" for issue in issues)
    return {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "total_posts": len(posts),
        "approved": len(approved_posts),
        "issues": issues,
        "status": "FAIL" if has_error else "PASS",
    }


def apply_fixes(posts):
    fixed_posts = []
    changes = []
    schedule_usage = set()

    for post in posts:
        if is_orphan_notion(post):
            changes.append(f"removed orphan notion post {post_title(post)}")
            continue
        fixed_posts.append(dict(post))

    for post in fixed_posts:
        if contains_note_link(post) and has_image(post):
            post.pop("image_path", None)
            changes.append(f"cleared image_path for note post {post_title(post)}")

    for post in fixed_posts:
        if str(post.get("status", "")).strip() != "approved":
            continue
        scheduled_at = parse_scheduled(post.get("scheduled_for"))
        if scheduled_at is None:
            continue
        candidate = scheduled_at
        candidate_text = candidate.strftime(SCHEDULE_FORMAT)
        if candidate_text not in schedule_usage:
            schedule_usage.add(candidate_text)
            continue
        while candidate_text in schedule_usage:
            candidate += timedelta(minutes=1)
            candidate_text = candidate.strftime(SCHEDULE_FORMAT)
        post["scheduled_for"] = candidate_text
        schedule_usage.add(candidate_text)
        changes.append(f"moved approved post {post_title(post)} to {candidate_text}")

    return fixed_posts, changes


def truncate(value, limit):
    text = str(value)
    if len(text) <= limit:
        return text
    return text[: limit - 3] + "..."


def render_human(report, fix_changes=None):
    lines = [
        f"Timestamp: {report['timestamp']}",
        f"Total Posts: {report['total_posts']}",
        f"Approved: {report['approved']}",
        f"Status: {report['status']}",
    ]

    if fix_changes:
        lines.append("")
        lines.append("Fixes Applied:")
        for change in fix_changes:
            lines.append(f"- {change}")

    issues = report["issues"]
    lines.append("")
    if not issues:
        lines.append("No issues found.")
        return "\n".join(lines)

    headers = ("Severity", "Check", "Posts", "Detail")
    rows = [
        (
            issue["severity"],
            issue["check"],
            truncate(" | ".join(issue["posts"]), 40),
            truncate(issue["detail"], 90),
        )
        for issue in issues
    ]
    widths = [len(header) for header in headers]
    for row in rows:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], len(value))

    header_line = "  ".join(header.ljust(widths[index]) for index, header in enumerate(headers))
    separator = "  ".join("-" * widths[index] for index in range(len(headers)))
    lines.extend([header_line, separator])
    for row in rows:
        lines.append("  ".join(value.ljust(widths[index]) for index, value in enumerate(row)))
    return "\n".join(lines)


def render_json(report):
    return json.dumps(report, ensure_ascii=False, indent=2)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Audit the post queue for common issues.")
    parser.add_argument("--fix", action="store_true", help="Auto-fix removable or safe issues.")
    parser.add_argument("--human", action="store_true", help="Print a human-readable table instead of JSON.")
    args = parser.parse_args(argv if argv is not None else sys.argv[1:])

    try:
        posts = load_posts(QUEUE_FILE)
    except Exception as exc:
        report = {
            "timestamp": datetime.now().isoformat(timespec="seconds"),
            "total_posts": 0,
            "approved": 0,
            "issues": [make_issue("LOAD_ERROR", "error", [], str(exc))],
            "status": "FAIL",
        }
        output = render_human(report) if args.human else render_json(report)
        sys.stdout.write(output + "\n")
        return 1

    fix_changes = []
    if args.fix:
        posts, fix_changes = apply_fixes(posts)
        if fix_changes:
            save_posts(QUEUE_FILE, posts)

    report = audit_posts(posts)
    output = render_human(report, fix_changes=fix_changes if args.human else None) if args.human else render_json(report)
    sys.stdout.write(output + "\n")
    return 1 if report["status"] == "FAIL" else 0


if __name__ == "__main__":
    raise SystemExit(main())
