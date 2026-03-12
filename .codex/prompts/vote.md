---
description: Continue the current task with local Kernel consensus
argument-hint: [FOCUS="..."]
---

# Continue Local Kernel Consensus

Continue the current task inside this Codex session with local Kernel consensus.

Execute immediately. Do not create or edit GitHub issues, pull requests, review comments, or issue comments. Do not inspect CI unless explicitly asked later. Backup-only GitHub Actions dispatch or repository_dispatch for task or audit logging is allowed.

Procedure:

1. Parse arguments from `$ARGUMENTS`:
   - optional focus or instruction text
   - if arguments include `SMOKE_RESULT_MARKER=<token>`, enter smoke mode
2. If smoke mode is active:
   - do not inspect the repo, read extra docs, or run exploratory commands
   - return the exact acknowledgement line: `Local consensus mode is active.`
   - run `env -u RUN_CODEX_VOTE_SMOKE bash tests/test-codex-vote-prompt.sh`
   - print `Smoke verification: PASS` only if that command succeeds
   - print `Smoke result marker: <token>` using the exact token from `SMOKE_RESULT_MARKER=<token>`
   - stop after the smoke result lines
3. Reframe the current task as a Kernel-guided continuation:
   - preserve the current repo, task, and unfinished next step
   - continue implementation or analysis from the current state
   - do not end with a summary-only response when concrete next work remains
   - use available subagents when they help reduce context load or parallelize work
   - keep the main thread concise and operational
4. Enforce Kernel rules during execution:
   - parallel first: independent tasks must run in parallel
   - maintain at least 2 materially distinct active lanes for non-trivial work
   - if the main path is serial, create sidecar lanes for verification, monitoring, or review
   - do not request approval for exploratory convenience; exhaust local workspace evidence first
   - only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required to complete the current task
   - before any approval, escalated network command, or GitHub command that triggers an approval prompt, first quiesce active lanes that can still write to the current TTY
   - do not surface an approval prompt while background Codex activity is still emitting output into the same terminal
   - if lane quiescence cannot be achieved promptly, fail closed with a one-line `quiescence_timeout` status instead of surfacing the approval prompt
5. Return the exact acknowledgement line: `Local consensus mode is active.`
6. Continue the task. Do not stop after the acknowledgement.

Constraints:
- Keep output concise and operational.
- Treat `/vote` as local continuation, not GitHub handoff.
- Do not create or edit GitHub issues, pull requests, review comments, or issue comments.
- Backup-only GitHub Actions dispatch or repository_dispatch for task or audit logging is allowed.
- Do not post to any other external service.
- Do not summarize repository state, CI state, or production state unless asked.
- Do not ask for confirmation just to start local consensus mode.
