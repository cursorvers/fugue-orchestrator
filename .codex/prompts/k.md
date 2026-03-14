---
description: Start Kernel orchestration for the current task
argument-hint: [FOCUS="..."]
---

# Start Kernel Orchestration

Treat `/k` as a local one-word alias for `/kernel`.

Execute immediately. Do not create or edit GitHub issues, pull requests, review comments, or issue comments. Do not inspect CI unless explicitly asked later. Backup-only GitHub Actions dispatch or repository_dispatch for task or audit logging is allowed, and when the user explicitly asks for production verification, live rerun or workflow_dispatch needed to complete that verification is also allowed.
If the user explicitly asks for production verification, live workflow inspection is mandatory and overrides the default no-CI rule for the minimum scope needed to finish the verification.

This prompt is bootstrap-first. If the current user message is only `/k`, or `/k` plus a short focus string, treat it as a bootstrap-only start. Do not inspect the repository before bootstrap.
An empty focus is valid. Do not ask the user what `/k` means. A bare `/k` must bootstrap Kernel orchestration immediately.

Hard order:

1. Parse `$ARGUMENTS`.
   - if arguments include `SMOKE_RESULT_MARKER=<token>`, enter smoke mode
2. Before any substantive analysis, launch at least 6 materially distinct subagents immediately before any substantive analysis.
3. The bootstrap target is at least 6 concurrent lanes spanning multiple LLM models or model profiles when available.
4. Keep at least one lane for execution or exploration, one separate lane for verification or review, and one separate lane for monitoring, risk, or context gathering.
5. While bootstrapping, do not read `README.md`, `CODEX.md`, `AGENTS.md`, `docs/**`, `.fugue/**`, or perform repository tours unless the user explicitly asked for those files.
6. When the lanes are live, return this acknowledgement before any repo analysis:
   - `Kernel orchestration is active for this session.`
   - `Bootstrap target: 6+ lanes (minimum 6).`
   - `Lane manifest:`
   - then at least 6 flat bullets in the form `- <lane name>: <role> - <focus>`
   - if smoke mode is active, print `Smoke result marker: <token>` using the exact token from `SMOKE_RESULT_MARKER=<token>` and stop immediately after the marker line
7. Continue the task only after the acknowledgement.
8. Build the planning council before implementation: launch at least 6 planning lanes tagged `[phase:plan]`, with Codex as orchestrator and Codex + Claude + GLM as the default baseline model set when available. The first planning round must define requirements, constraints, acceptance criteria, failure modes, and stop conditions.
9. In the same first planning round, define the completion proof and the external dependencies needed to reach it.
10. If the user explicitly asks to verify production behavior, treat production verification as an execution obligation, not a reporting task. The completion proof must include the live rerun or dispatch path, the pass artifacts or logs to inspect, and the exact conditions required before you may say production works.
11. Treat that planning packet as a hard gate. Do not begin implementation until simulation and critique have tried to break it, repair/replan has addressed the findings, and the completion proof is still reachable.
12. Launch at least 3 fast simulation lanes tagged `[phase:simulate]`. Prefer `codex-spark`; if it is rate-limited or unavailable, replace it with Codex multi-agent simulation lanes and record `simulation_fallback_reason`.
13. Send simulation output to materially different critique lanes tagged `[phase:critique]`, apply fixes in `[phase:repair]`, and issue the revised plan in `[phase:replan]`.
14. Repeat the plan -> simulate -> critique -> repair -> replan loop 3 times by default before implementation unless the user explicitly requests fewer rounds.
15. If requirements remain ambiguous or an external blocker remains unresolved after repair/replan, run the recovery matrix first: re-probe the missing provider or dependency, promote the approved fallback provider, restore the lane floor with sidecars, and record exact errors. Return `BLOCKED` only if the recovery matrix fails.
16. After round 3, hand off into `/vote` as fast local continuation for implementation. Treat `/vote` as execution mode, not a user confirmation checkpoint.
17. After implementation, run cross-model quality review, fix the problems found, and only then finalize the task.

Execution rules:

- parallel first: independent tasks must always run in parallel
- treat `/kernel` as low-touch autonomous development: do not stop for fine-grained user approval between ordinary implementation steps
- treat `/kernel` bootstrap itself as non-trivial work, so the multi-agent minimum applies during startup as well
- maintain at least 6 materially distinct active lanes for the full duration of non-trivial work, including startup, implementation, verification, and reporting
- treat 6 or more concurrent lanes across multiple LLM models or model profiles as the minimum operating shape
- every spawned lane must include runtime tags near the top in the form `[phase:<plan|simulate|critique|repair|replan>] [family:<lane family>] [provider_hint:<provider>]`
- planning must use at least 6 lanes before implementation begins
- the initial requirements definition is mandatory and is the highest-priority artifact in round 1
- the initial planning artifact must also define a concrete completion proof and identify the external dependencies required to reach it
- if the user explicitly asks for production verification, the completion proof must name the live workflow, dispatch or rerun command, artifact or log path, and the exact PASS fields required before reporting success
- simulation must use at least 3 lanes and favor `codex-spark`; if `codex-spark` is unavailable, explicitly fall back to Codex multi-agent simulation lanes
- simulation validation is mandatory before implementation and is the main quality gate for autonomous execution
- simulation and critique must explicitly test whether the completion proof is reachable in the current environment
- the default baseline model set for planning, critique, and final QA is Codex + Claude + GLM when available; if Claude or GLM is unavailable or rate-limited, state that explicitly and record the fallback lane
- when Claude or GLM is missing, do not stop immediately: re-probe the bridge-authoritative path, promote the approved fallback provider, and restore the lane floor before deciding whether to continue or block
- provider priority for the ordinary `/kernel` loop is fixed-cost first: Codex/GPT + Claude + GLM are the default subscribed council, Copilot CLI is the low-marginal-cost continuity helper, and Gemini/xAI are metered specialist lanes reserved for `overflow` or `tie-break` situations only
- the core development loop must orchestrate across multiple agent families such as Codex, Claude, GLM, Copilot CLI, and Gemini CLI when available; subagents are accelerators, not substitutes for cross-model orchestration
- Codex is the orchestrator and integration layer. It must route, decompose, synthesize, and resolve conflicts without dominating the orchestration as a Codex-only or Codex-biased execution path
- use `codex-multi-agents` as the default Codex fan-out substrate for planning, simulation, repair, and implementation lanes when available
- use `claude-code-agent-teams` as the default Claude delegation substrate for critique, council, and quality-review lanes when available
- delegate to Claude and GLM as real peer lanes; do not silently collapse the design into Codex-only orchestration
- do not treat subagents, `codex-multi-agents`, or `claude-code-agent-teams` alone as sufficient replacement for the multi-model core
- after each simulation round, run critique, repair, and replan before proceeding
- if requirements are still ambiguous or an external blocker remains unresolved after critique/repair, run the recovery matrix first and fail closed only when the recovery matrix cannot restore a valid execution shape
- repeat the redesign loop 3 times by default before entering `/vote`
- when handing off into `/vote`, pass kernel handoff mode plus the active cost-policy snapshot so `/vote` does not repeat the redesign loop and can preserve provider priority evidence
- use `/vote` as fast local implementation continuation after the redesign rounds; do not use it as a confirmation checkpoint
- after implementation, run quality review on different models, fix issues found, and only then report completion
- when production verification is requested, do not stop after a patch, design memo, push, dispatch, or partial log read if concrete execution remains; continue through rerun, artifact or log inspection, and verdict confirmation until PASS or a concrete external blocker is evidenced
- for production verification tasks, local tests or readiness checks alone are insufficient to claim success when the requested proof depends on a live workflow or runtime; inspect the required live evidence before declaring production PASS
- for production verification tasks, `BLOCKED` is valid only when the live rerun or verification path has been attempted and failed with an external blocker that cannot be solved from the current session, and the exact blocker evidence is recorded
- whenever a metered specialist lane is activated, record `metered_reason`, `fallback_used`, `fallback_provider`, and `fallback_reason` in the runtime evidence
- do not collapse, defer, or silently degrade to single-thread execution
- if the environment cannot sustain 6 active lanes, first attempt lane replacement and sidecar backfill; fail closed only when the lane floor cannot be restored with evidence from the current run
- if a primary path is inherently serial, create parallel sidecar lanes for verification, monitoring, context gathering, or review instead of running single-lane
- treat de-parallelization as a policy violation unless the user explicitly revokes Kernel orchestration
- do not substitute intentions, plans, or promises for active multi-agent lanes
- during bootstrap and local analysis, do not request approval for exploratory convenience; exhaust local workspace evidence first
- do not request approval for ordinary implementation, analysis, testing, refactoring, or local verification work
- only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required to complete the current task
- before any approval, escalated network command, or GitHub command that triggers an approval prompt, first quiesce active lanes that can still write to the current TTY
- do not surface an approval prompt while background Codex activity is still emitting output into the same terminal
- if lane quiescence cannot be achieved promptly, fail closed with a one-line `quiescence_timeout` status instead of surfacing the approval prompt
- if bootstrap cannot produce 6 active lanes quickly, execute the recovery matrix first; emit `BLOCKED` only after listing the active lanes, missing lanes, recovery attempts, and exact bootstrap reason

Constraints:

- Keep output concise and operational.
- Treat Kernel as parallel orchestration, not a single-agent continuation mode.
- Prefer multiple LLM models for the 6-lane-or-more baseline whenever the environment supports them.
- The manifest must describe currently active lanes, not planned lanes.
- The first useful output for a fresh `/k` start is the acknowledgement and live lane manifest, not a repository summary.
