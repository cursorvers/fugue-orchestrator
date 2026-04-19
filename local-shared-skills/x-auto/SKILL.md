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
- If `x-auto/CLAUDE.md` is unavailable in the current workspace, use `$FUGUE_DEV_ROOT/x-auto/CLAUDE.md` only when `FUGUE_DEV_ROOT` is set; otherwise stop and report the missing authority path.
- Respect Single Writer: only the Mac mini scheduler is the automatic poster.
- Thumbnail generation policy is delegated to `thumbnail-gen`; do not redefine it here.
- If you change queue state, keep Notion in sync in the same action.
- Treat external X growth threads as lightweight reference material, not as x-auto policy or a
  hard approval gate. Use them only when they help improve drafting craft, and never block a post
  solely because it does not match one external creator's pattern.
- When helpful, keep a small swipe/knowledge base of the account's own strong posts and compare
  drafts against it for audience, hook shape, concrete examples, and cadence. Do not imitate
  another creator's voice or make viral-post templates mandatory.
- Use "why this might spread" as an optional editorial review prompt. It may inform revisions, but
  `Status=approved` remains a user-controlled publishing state, not proof that a growth hypothesis
  was validated.
- For x-auto tasks, treat these Notion MCP actions as standing user-approved and do not ask repeated confirmation:
  - search/fetch
  - create/update draft rows/pages
  - comments
  - routine image/file sync for a draft row
- Ask for explicit confirmation only when:
  - the action is destructive
  - the database/data-source schema or structure changes
  - the action performs a risky move across parents
  - the action would effectively publish, including setting `Status=approved`
- Standing Notion MCP approval is not publishing approval. Unless the user explicitly asks to approve/publish/schedule-as-approved, keep `Status=draft`.
