---
description: Continue the current task with local Kernel consensus
argument-hint: [FOCUS="..."]
---

# Continue Local Kernel Consensus

Continue the current task inside this Codex session with local Kernel consensus.

Execute immediately. Do not post to GitHub, do not create or edit issue comments, and do not inspect CI unless explicitly asked later.

Procedure:

1. Parse arguments from `$ARGUMENTS`:
   - optional focus or instruction text
   - if arguments include `SMOKE_RESULT_MARKER=<token>`, enter smoke mode
2. Reframe the current task as a Kernel-guided continuation:
   - preserve the current repo, task, and unfinished next step
   - continue implementation or analysis from the current state
   - for non-critical work, record local consensus evidence for the current run before phase completion proceeds
   - do not end with a summary-only response when concrete next work remains
   - use available subagents when they help reduce context load or parallelize work
   - keep the main thread concise and operational
3. Enforce Kernel rules during execution:
   - parallel first: independent tasks must run in parallel
   - maintain at least 2 materially distinct active lanes for non-trivial work
   - if the main path is serial, create sidecar lanes for verification, monitoring, or review
4. Return the exact acknowledgement line: `Local consensus mode is active.`
5. If smoke mode is active:
   - skip exploratory work
   - run `env -u RUN_CODEX_VOTE_SMOKE bash tests/test-codex-vote-prompt.sh`
   - print `Smoke verification: PASS` only if that command succeeds
   - print `Smoke result marker: <token>` using the exact token from `SMOKE_RESULT_MARKER=<token>`
6. Continue the task. Do not stop after the acknowledgement.

Constraints:
- Keep output concise and operational.
- Treat `/vote` as local continuation, not GitHub handoff.
- Reuse successful local auth or trust evidence across the run; do not re-request equivalent user auth for non-critical work.
- Do not post to GitHub or any external service.
- Do not summarize repository state, CI state, or production state unless asked.
- Do not ask for confirmation just to start local consensus mode.
