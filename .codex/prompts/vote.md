---
description: Continue the current task with local Kernel consensus
argument-hint: [FOCUS="..."]
---

# Continue Local Kernel Consensus

Continue the current task inside this Codex session with local Kernel consensus.

Execute immediately. Do not create or edit GitHub issues, pull requests, review comments, or issue comments. Do not inspect CI unless explicitly asked later. Backup-only GitHub Actions dispatch or repository_dispatch for task or audit logging is allowed, and when the user explicitly asks for production verification, live rerun or workflow_dispatch needed to complete that verification is also allowed.
If the user explicitly asks for production verification, live workflow inspection is mandatory and overrides the default no-CI rule for the minimum scope needed to finish the verification.

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
   - continue until the task reaches a real completion point; do not stop at a design memo or status-only checkpoint when concrete execution remains
   - do not end with a summary-only response when concrete next work remains
   - if the user explicitly asks for production verification, treat it as an execution obligation: continue through patch, push, dispatch or rerun, artifact or log inspection, and verdict confirmation until PASS or a concrete external blocker is evidenced
   - use available subagents when they help reduce context load or parallelize work
   - for non-trivial work, start with a lane plan that names at least 3 distinct active model families or providers
   - if the current state already carries `/kernel` round-3 handoff evidence, enter kernel handoff mode: preserve the active council, skip duplicate redesign rounds, and continue directly into execution plus post-implementation QA
   - the default operating council is `Codex + Claude + GLM`
   - for non-trivial planning, simulation, critique, implementation, verification, adjudication, and final recommendation, treat `Codex + Claude + GLM` as the required baseline council unless a bridge-authoritative runtime probe proves a lane unavailable
   - keep `Codex + Claude + GLM` active through the full task lifecycle whenever bridge-authoritative probes say those lanes are available
   - if one of `Codex`, `Claude`, or `GLM` drops during non-trivial work, launch a replacement lane or re-probe before continuing
   - do not treat 2-lane execution as sufficient when `Codex + Claude + GLM` are available
   - before major edits, define requirements, constraints, acceptance criteria, failure modes, and stop conditions; treat that packet as a hard gate for implementation
   - if the user explicitly asks for production verification, the requirements packet must define the live workflow or runtime path to exercise, the exact rerun or dispatch command or trigger path, the artifacts or logs to inspect, and the PASS fields required before reporting production success
   - provider priority for ordinary execution is fixed-cost first: Codex/GPT + Claude + GLM are the default subscribed council, Copilot CLI is the low-cost continuity fallback, and Gemini/xAI are metered specialist lanes reserved for `overflow` or `tie-break` only
   - when a metered specialist lane is activated, record `metered_reason`, `fallback_used`, `fallback_provider`, and `fallback_reason` in the runtime evidence
   - determine Claude and GLM lane availability from the configured bridge or runtime path, not from ad-hoc local binary checks alone
   - a missing local `glm` command does not prove GLM is unavailable when the delegate bridge or provider API route is configured
   - a failed direct `claude` CLI attempt does not prove Claude is unavailable when the configured bridge-authoritative path can still return a live lane
   - prefer bridge-authoritative probes or current-run bootstrap evidence over `which glm`, `which claude`, or similar shell-only checks
   - before returning `BLOCKED` for missing Claude or GLM, run the recovery matrix in the current run: re-probe the bridge-authoritative path, promote the approved fallback provider, restore the lane floor with sidecars, and record exact errors
   - only return `BLOCKED` for missing Claude or GLM after that recovery matrix has been attempted and failed with a concrete reason
   - when returning `BLOCKED`, name the missing lane, the attempted bridge-authoritative probe, and the concrete failure reason
   - for production verification tasks, local tests or readiness checks alone are insufficient to claim success when the requested proof depends on a live workflow or runtime; inspect the required live evidence before declaring production PASS
   - keep the main thread concise and operational
4. Enforce Kernel rules during execution:
   - parallel first: independent tasks must run in parallel
   - maintain at least 2 materially distinct active lanes for non-trivial work, and maintain at least 6 materially distinct active lanes for kernel handoff mode
   - if the main path is serial, create sidecar lanes for verification, monitoring, or review
   - for non-trivial work, run exactly 3 refinement rounds before major edits unless kernel handoff mode is already active from `/kernel` round 3
   - each refinement round must follow this exact order: `Plan -> Parallel Simulation -> Critical Review -> Problem Fix -> Replan`
   - `Parallel Simulation` and `Critical Review` are hard gates and cannot be skipped
   - if simulation or critical review exposes a design flaw or contradiction, repair and replan before implementation resumes
   - if simulation or critical review exposes an unresolved external blocker, run the recovery matrix before stopping; return `BLOCKED` only when recovery fails or the blocker is outside the session's control
   - for production verification tasks, return `BLOCKED` only when the live rerun or verification path has been attempted and failed with an external blocker that cannot be solved from the current session, and record the exact blocker evidence
   - in kernel handoff mode, do not repeat the redesign loop; continue immediately with council-backed implementation and then cross-model QA until the task is actually complete
   - after refinement, continue with council-backed implementation until the task is actually complete
   - when production verification is requested, do not stop after a patch, push, dispatch, or partial log read if concrete execution remains
   - implementation dialogue must keep this order: `Implementer Proposal -> Critic Challenge -> Integrator Decision -> Applied Change -> Verification`
   - record lane evidence at finish: which `Codex`, `Claude`, and `GLM` lanes stayed active, or why a required lane was blocked
   - do not request approval for exploratory convenience; exhaust local workspace evidence first
   - ordinary implementation, analysis, testing, refactoring, and safe local workspace writes must proceed without user confirmation
   - only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required to complete the current task
   - only ask for approval on critical or irreversible actions such as mass deletion, destructive file-system rewrites, secret or credential access, production writes, or explicit user-requested approvals
   - before any approval, escalated network command, or GitHub command that triggers an approval prompt, first quiesce active lanes that can still write to the current TTY
   - do not surface an approval prompt while background Codex activity is still emitting output into the same terminal
   - if lane quiescence cannot be achieved promptly, fail closed with a one-line `quiescence_timeout` status instead of surfacing the approval prompt
5. Return the exact acknowledgement line: `Local consensus mode is active.`
6. Continue the task. Do not stop after the acknowledgement.

Constraints:
- Keep output concise and operational.
- Treat `/vote` as local continuation, not GitHub issue-comment handoff.
- Do not create or edit GitHub issues, pull requests, review comments, or issue comments.
- Backup-only GitHub Actions dispatch or repository_dispatch for task or audit logging is allowed.
- Do not post to any other external service.
- Do not summarize repository state, CI state, or production state unless asked.
- Do not ask for confirmation just to start local consensus mode.
