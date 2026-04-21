#!/usr/bin/env python3
"""x-auto pipeline health check CLI.

Canonical repo copy used by eval wrappers to avoid hardcoding a single
orchestrator home-skill path.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

SERVICE_LABEL = "com.cursorvers.x-auto"
PLIST = Path.home() / "Library" / "LaunchAgents" / f"{SERVICE_LABEL}.plist"
HEARTBEAT_MAX_AGE_SECONDS = 120

FAILURES: list[str] = []
WARNINGS: list[str] = []
COLLISION_WINDOW = timedelta(minutes=3)


def _safe_run(argv: list[str]) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(argv, capture_output=True, text=True)
    except (OSError, PermissionError):
        return None


def _launchctl_service_text() -> str:
    label = f"gui/{os.getuid()}/{SERVICE_LABEL}"
    result = _safe_run(["launchctl", "print", label])
    if result is None:
        return ""
    if result.returncode == 0:
        return result.stdout
    return ""


def _launchd_working_directory() -> Path | None:
    output = _launchctl_service_text()
    for line in output.splitlines():
        marker = "working directory = "
        if marker in line:
            return Path(line.split(marker, 1)[1].strip())
    return None


def _running_scheduler_root() -> Path | None:
    result = _safe_run(["ps", "-axo", "pid=,ppid=,command="])
    if result is None:
        return None
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if "scheduler.py" not in line or "x-auto-health.py" in line:
            continue
        parts = line.split(None, 2)
        if len(parts) < 3:
            continue
        command = parts[2]
        for token in command.split():
            if token.endswith("/scheduler.py"):
                return Path(token).resolve().parent
    return None


def _looks_like_runtime_root(path: Path) -> bool:
    return (
        (path / "scheduler.py").exists()
        and ((path / "logs").exists() or (path / "post_queue.json").exists())
    )


def _resolve_base_dir() -> Path:
    candidates: list[Path] = []
    env_dir = os.environ.get("X_AUTO_DIR", "").strip()
    if env_dir:
        candidates.append(Path(env_dir).expanduser())
    launchd_root = _launchd_working_directory()
    if launchd_root is not None:
        candidates.append(launchd_root)
    running_root = _running_scheduler_root()
    if running_root is not None:
        candidates.append(running_root)
    candidates.extend(
        [
            Path.home() / "Dev" / "x-auto",
            Path.home() / "Documents" / "x-auto",
        ]
    )
    seen: set[Path] = set()
    for candidate in candidates:
        resolved = candidate.expanduser().resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        if _looks_like_runtime_root(resolved):
            return resolved
    return (Path.home() / "Dev" / "x-auto").resolve()


BASE_DIR = _resolve_base_dir()
QUEUE_FILE = BASE_DIR / "post_queue.json"
LOG_FILE = BASE_DIR / "logs" / "scheduler.log"
ERR_LOG_FILE = BASE_DIR / "logs" / "scheduler.err.log"
HEARTBEAT_FILE = BASE_DIR / "logs" / "heartbeat.json"
SECRETS_FILE = BASE_DIR / ".secrets.json"

RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RESET = "\033[0m"


def ok(msg: str) -> None:
    print(f"  {GREEN}OK{RESET}  {msg}")


def warn(msg: str) -> None:
    WARNINGS.append(msg)
    print(f"  {YELLOW}WARN{RESET} {msg}")


def fail(msg: str) -> None:
    FAILURES.append(msg)
    print(f"  {RED}FAIL{RESET} {msg}")


def check_scheduler_process() -> bool:
    result = _safe_run(["ps", "-axo", "pid=,ppid=,command="])
    if result is None:
        warn("Could not inspect process table from this environment")
        return False
    matches: list[tuple[str, str, str]] = []
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if "scheduler.py" not in line or "x-auto-health.py" in line:
            continue
        parts = line.split(None, 2)
        if len(parts) < 3:
            continue
        matches.append((parts[0], parts[1], parts[2]))

    if matches:
        pids = ", ".join(pid for pid, _, _ in matches)
        ok(f"Scheduler running (PID: {pids})")
        pid, ppid, _ = matches[0]
        parent_result = _safe_run(["ps", "-p", ppid, "-o", "command="])
        parent = parent_result.stdout.strip() if parent_result is not None else ""
        if parent and "launchd" not in parent:
            warn(f"Scheduler parent is not launchd (pid={pid}, ppid={ppid}: {parent[:90]})")
        return True
    fail("Scheduler not running")
    return False


def check_heartbeat() -> None:
    if not HEARTBEAT_FILE.exists():
        warn("No heartbeat.json found (scheduler may not have Phase 1 code)")
        return

    try:
        data = json.loads(HEARTBEAT_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        fail("heartbeat.json is corrupted or unreadable")
        return

    ts = data.get("timestamp", "")
    try:
        hb_time = datetime.fromisoformat(ts)
        age = (datetime.now() - hb_time).total_seconds()
        if age <= HEARTBEAT_MAX_AGE_SECONDS:
            ok(f"Heartbeat fresh ({int(age)}s ago, pid={data.get('pid')})")
        else:
            fail(f"Heartbeat stale ({int(age)}s ago — scheduler may be dead)")
    except (ValueError, TypeError):
        fail(f"heartbeat.json has invalid timestamp: {ts}")

    approved = data.get("approved_count", 0)
    depth = data.get("queue_depth", 0)
    if approved < 3:
        warn(f"Low approved count: {approved} (queue depth: {depth})")
    else:
        ok(f"Queue: {approved} approved / {depth} total")


def check_queue_health() -> None:
    if not QUEUE_FILE.exists():
        fail(f"Queue file not found: {QUEUE_FILE}")
        return

    posts = json.loads(QUEUE_FILE.read_text(encoding="utf-8"))
    total = len(posts)
    pending = [p for p in posts if not p.get("posted", False)]
    approved = [p for p in pending if p.get("status") == "approved"]

    date_only = []
    missing_time = []
    for post in approved:
        scheduled_for = post.get("scheduled_for", "")
        if not scheduled_for:
            missing_time.append(post)
        elif " " not in scheduled_for:
            date_only.append(post)

    ok(f"Queue: {total} total, {len(pending)} pending, {len(approved)} approved")
    if len(approved) < 7:
        warn(f"Low queue: {len(approved)} approved (min 7)")

    if date_only:
        warn(f"{len(date_only)} posts have date-only scheduled_for (will be skipped):")
        for post in date_only:
            title = post.get("title", "") or post.get("text", "")[:30]
            print(f"         {post['scheduled_for']} | {title}")

    if missing_time:
        fail(f"{len(missing_time)} posts have no scheduled_for")

    today = datetime.now().strftime("%Y-%m-%d")
    today_posts = [p for p in approved if p.get("scheduled_for", "").startswith(today)]
    if today_posts:
        ok(f"Today's schedule ({today}):")
        for post in sorted(today_posts, key=lambda item: item.get("scheduled_for", "")):
            title = post.get("title", "") or post.get("text", "")[:30]
            scheduled_for = post.get("scheduled_for", "")
            has_image = "img" if post.get("image_path") else "NO-IMG"
            print(f"         {scheduled_for[11:]} | [{has_image}] {title}")


def check_secrets() -> None:
    if SECRETS_FILE.exists():
        mode = oct(SECRETS_FILE.stat().st_mode)[-3:]
        if mode == "600":
            ok(f".secrets.json exists (mode {mode})")
        else:
            warn(f".secrets.json mode is {mode} (should be 600)")
    else:
        warn(".secrets.json not found (will use env/Keychain)")


def check_launchd() -> None:
    if not PLIST.exists():
        fail(f"Plist not found: {PLIST}")
        return

    ok(f"Canonical plist: {PLIST}")

    service_text = _launchctl_service_text()
    if service_text:
        ok(f"launchd agent registered ({SERVICE_LABEL})")
        working_dir = _launchd_working_directory()
        if working_dir and working_dir.resolve() != BASE_DIR:
            fail(f"launchd working directory drift: {working_dir} != {BASE_DIR}")
    else:
        warn("launchd agent not registered (using nohup?)")


def check_logs() -> None:
    if not LOG_FILE.exists():
        warn("No scheduler.log found")
        return

    lines = LOG_FILE.read_text(encoding="utf-8").strip().split("\n")
    if not lines:
        warn("scheduler.log is empty")
        return

    ok(f"Last log: {lines[-1][:80]}")

    errors = [line for line in lines[-20:] if "ERROR" in line or "Exception" in line]
    if errors:
        warn(f"{len(errors)} recent errors in log")
        for error in errors[-3:]:
            print(f"         {error[:80]}")

    if ERR_LOG_FILE.exists():
        err_lines = ERR_LOG_FILE.read_text(encoding="utf-8").strip().split("\n")
        cutoff = datetime.now() - COLLISION_WINDOW
        collisions = []
        for line in err_lines[-200:]:
            if "Another scheduler is running" not in line:
                continue
            try:
                timestamp = datetime.fromisoformat(line[:19].replace(" ", "T"))
            except ValueError:
                timestamp = None
            if timestamp is None or timestamp >= cutoff:
                collisions.append(line)
        if collisions:
            fail(
                f"launchd/manual collision detected: {len(collisions)} recent duplicate scheduler starts"
            )


def check_images() -> None:
    if not QUEUE_FILE.exists():
        return

    posts = json.loads(QUEUE_FILE.read_text(encoding="utf-8"))
    missing = []
    for post in posts:
        if post.get("posted") or post.get("status") != "approved":
            continue
        image_path = post.get("image_path", "")
        if image_path and not Path(image_path).exists():
            title = post.get("title", "") or post.get("text", "")[:30]
            missing.append(f"{image_path} ({title})")

    if missing:
        fail(f"{len(missing)} approved posts have missing image files:")
        for item in missing:
            print(f"         {item}")
    else:
        ok("All approved posts have valid image files (or no image required)")


def main() -> None:
    print("=== x-auto Health Check ===\n")
    print(f"Runtime root: {BASE_DIR}\n")
    check_scheduler_process()
    check_heartbeat()
    print()
    check_queue_health()
    print()
    check_secrets()
    check_launchd()
    print()
    check_logs()
    print()
    check_images()
    print()
    if FAILURES:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
