---
description: Start Kernel orchestration for the current task
argument-hint: [FOCUS="..."]
---

# Start Kernel Orchestration

Start Kernel orchestration for the current task inside this Codex session.

Execute immediately. Do not post to GitHub, do not create or edit issue comments, and do not inspect CI unless explicitly asked later.

Procedure:

1. Parse arguments from `$ARGUMENTS`:
   - optional focus or instruction text
2. Reframe the current task as a Kernel-orchestrated execution:
   - preserve the current task and context
   - decompose the work into independent lanes before proceeding
   - start parallel excitation immediately for independent lanes
   - use multiple subagents or equivalent parallel lanes by default
   - reserve the main thread for routing, synthesis, conflict resolution, and final integration
3. Enforce Kernel rules during execution:
   - parallel first: independent tasks must always run in parallel
   - maintain at least 2 materially distinct active lanes for the full duration of non-trivial work, including startup, implementation, verification, and reporting
   - do not collapse, defer, or silently degrade to single-thread execution
   - if a primary path is inherently serial, create parallel sidecar lanes for verification, monitoring, context gathering, or review instead of running single-lane
   - treat de-parallelization as a policy violation unless the user explicitly revokes Kernel orchestration
4. Return a short acknowledgement that Kernel orchestration is active.
5. Continue the task. Do not stop after the acknowledgement.

Constraints:
- Keep output concise and operational.
- Treat Kernel as parallel orchestration, not a single-agent continuation mode.
- Do not post to GitHub or any external service.
- Do not summarize repository state, CI state, or production state unless asked.
- Do not ask for confirmation just to start Kernel orchestration.
