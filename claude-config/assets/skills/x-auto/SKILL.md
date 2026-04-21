---
name: x-auto
description: |
  Thin adapter for x-auto queue operations in Claude-backed runtime roots.
  Use for queue inspection, approval, schedule changes, Notion sync, and health checks.
---

# x-auto

Use this adapter for x-auto queue work from Claude-side skill roots.

Authority:
- `x-auto/CLAUDE.md`
- `./CLAUDE.md` when the current workspace is the x-auto runtime root
- `$HOME/Dev/x-auto/CLAUDE.md` when invoked from x-auto data/cache roots such as `$HOME/.local/share/x-auto`
- `$FUGUE_DEV_ROOT/claude-config/assets/skills/x-auto/scripts/x-auto-health.py`

Rules:
- Read `x-auto/CLAUDE.md` before making queue or posting changes.
- If the current workspace is the x-auto runtime root, read `./CLAUDE.md` instead of `x-auto/CLAUDE.md`.
- Do not treat `$HOME/.local/share/x-auto` as the runtime root; it is a data/cache directory. If invoked there, switch authority lookup and runtime commands to `$HOME/Dev/x-auto` when that checkout exists.
- If `x-auto/CLAUDE.md` is unavailable in the current workspace, use `$HOME/Dev/x-auto/CLAUDE.md` as the authority document when that checkout exists; otherwise stop and report the missing authority path.
- Respect Single Writer: only the Mac mini scheduler is the automatic poster.
- Thumbnail generation policy is delegated to `thumbnail-gen`; do not redefine it here.
- If you change queue state, keep Notion in sync in the same action.
- When the user gives an explicit posting instruction, including approve, publish, schedule, or
  schedule-as-approved, do not ask for additional user approval/authentication for that posting
  decision. Drive the draft through the current-completion workflow with multi-agent consensus and
  promote it only when a valid `x-auto.consensus.receipt/v1` is produced and runtime publish gates
  pass.
- A valid consensus receipt is the required substitute for human approval on explicit posting
  instructions. If consensus fails, keep `Status=draft`, record the blocking reason, and report it;
  do not fall back to single-agent approval or ask the user to authenticate the same posting action.
- For x-auto tasks, treat these Notion MCP actions as standing user-approved and do not ask repeated confirmation:
  - search/fetch
  - create/update draft rows/pages
  - comments
  - routine image/file sync for a draft row
- Ask for explicit confirmation only when:
  - the action is destructive
  - the database/data-source schema or structure changes
  - the action performs a risky move across parents
  - the action would effectively publish, including setting `Status=approved`, and there is neither
    an explicit posting instruction nor a valid consensus approval receipt
- Standing Notion MCP approval is not publishing approval. Unless the user explicitly asks to approve/publish/schedule/schedule-as-approved and valid consensus approval is supplied, keep `Status=draft`.
