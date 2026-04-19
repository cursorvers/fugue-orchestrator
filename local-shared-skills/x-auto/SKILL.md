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
- `./CLAUDE.md` when the current workspace is the x-auto runtime root
- `$HOME/Dev/x-auto/CLAUDE.md` when invoked from x-auto data/cache roots such as `$HOME/.local/share/x-auto`
- `$FUGUE_DEV_ROOT/claude-config/assets/skills/x-auto/scripts/x-auto-health.py`

Rules:
- Read `x-auto/CLAUDE.md` before making queue or posting changes.
- If the current workspace is the x-auto runtime root, read `./CLAUDE.md` instead of `x-auto/CLAUDE.md`.
- Do not treat `$HOME/.local/share/x-auto` as the runtime root; it is a data/cache directory. If invoked there, switch authority lookup and runtime commands to `$HOME/Dev/x-auto` when that checkout exists.
- If `x-auto/CLAUDE.md` is unavailable in the current workspace, use `$FUGUE_DEV_ROOT/x-auto/CLAUDE.md` only when `FUGUE_DEV_ROOT` is set; otherwise stop and report the missing authority path.
- Respect Single Writer: only the Mac mini scheduler is the automatic poster.
- Treat live runtime config and tests as authoritative over stale prose guidance.
- After mutating live queue or Notion state, verify the active runtime, queue audit outcome, and scheduler health before calling the work complete.
- Secret resolution policy belongs to the runtime contract; do not override it from skill prose or ad-hoc environment assumptions.
- Thumbnail generation policy is delegated to `thumbnail-gen`; do not redefine it here.
- If you change queue state, keep Notion in sync in the same action.
- Incident 2026-04-19: `publish_core` can run against a legacy `x_poster` runtime where
  `post_tweet_with_image_quote` is absent and falls back to `post_tweet_with_image(text, image_path)`.
  Native X `quote_tweet_id` is disabled in publish plans and citations must be attached through
  `reply_lines`; never pass `quote_tweet_id` into the image-posting function. Regression tests must
  assert the image path call signature directly, not through permissive `*args, **kwargs` fakes.
- Treat external X growth threads as lightweight reference material, not as x-auto policy or a
  hard approval gate. Use them only when they help improve drafting craft, and never block a post
  solely because it does not match one external creator's pattern.
- When helpful, keep a small swipe/knowledge base of the account's own strong posts and compare
  drafts against it for audience, hook shape, concrete examples, and cadence. Do not imitate
  another creator's voice or make viral-post templates mandatory.
- Use "why this might spread" as an optional editorial review prompt. It may inform revisions, but
  `Status=approved` remains a controlled publishing state, not proof that a growth hypothesis was
  validated. Only explicit user approval or a valid consensus approval receipt may promote a draft
  into that state.
- For Japanese X drafting, apply durable account-style memories under `.codex/memories/x-auto-*.md`.
  In particular, Japanese `『』` hooks must not include a closing Japanese full stop inside the quote:
  prefer `『Claude Codeはプロンプト術ではなく運用設計です』` over `『Claude Codeはプロンプト術ではなく運用設計です。』`.
- For public-facing drafts, avoid overused reader-alienating phrases such as "この記事で刺さったのは".
  Lead with the user's own thesis, a concrete operational risk, or a decision rule instead.
- After creating or updating an x-auto draft, present the exact post body and key metadata in the
  current chat before ending the turn. Ask for approval before any action that would make it
  publishable, including setting `Status=approved`, immediate posting, or scheduling-as-approved,
  unless an explicit `--consensus-approve` action is backed by a valid `x-auto.consensus.receipt/v1`
  and the runtime publish gates pass.
- For x-auto tasks, treat these Notion MCP actions as standing user-approved and do not ask repeated confirmation:
  - search/fetch
  - create/update draft rows/pages
  - comments
  - routine image/file sync for a draft row
- Ask for explicit confirmation only when:
  - the action is destructive
  - the database/data-source schema or structure changes
  - the action performs a risky move across parents
  - the action would effectively publish, including setting `Status=approved`, unless the task
    explicitly uses valid consensus approval
- Standing Notion MCP approval is not publishing approval. Unless the user explicitly asks to approve/publish/schedule-as-approved or a valid consensus approval receipt is supplied, keep `Status=draft`.
