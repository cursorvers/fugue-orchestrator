---
name: x-auto
description: |
  Shared adapter for x-auto queue operations across Claude and Codex.
  Use for queue inspection, approval, schedule changes, Notion sync, and health checks.
---

# x-auto

Use this adapter for x-auto queue work from either runtime.

Authority:
- `x-auto/CLAUDE.md`
- `claude-config/assets/skills/x-auto/scripts/x-auto-health.py`

Rules:
- Read `x-auto/CLAUDE.md` before making queue or posting changes.
- Respect Single Writer: only the Mac mini scheduler is the automatic poster.
- Thumbnail generation policy is delegated to `thumbnail-gen`; do not redefine it here.
- If you change queue state, keep Notion in sync in the same action.
