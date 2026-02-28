---
description: Post /vote to a GitHub issue and verify FUGUE workflow dispatch
argument-hint: [ISSUE=<number>] [REPO=<owner/repo>] [INSTRUCTION="..."]
---

# Trigger FUGUE Vote

Post a `/vote` comment to a GitHub issue and confirm workflow dispatch.

Procedure:

1. Parse arguments from `$ARGUMENTS`:
   - `ISSUE=<number>` (optional, default: `190`)
   - `REPO=<owner/repo>` (optional, default: `cursorvers/fugue-orchestrator`)
   - `INSTRUCTION="...text..."` (optional)
2. Build comment body:
   - no instruction: `/vote`
   - with instruction:
     - first line: `/vote`
     - second and later lines: instruction text
3. Run:
   - `gh issue comment <ISSUE> --repo <REPO> --body <COMMENT_BODY>`
4. Report:
   - target issue/repo
   - posted comment summary

Constraints:
- Keep output concise and operational.
- Do not edit repository files for this command.
- Do not call `gh run list` or `gh run view` by default.
