# CODEX.md - Kernel Adapter

Role: Codex is the sovereign orchestrator for `Kernel`.

Primary policy source:

1. `AGENTS.md`
2. `docs/requirements-gpt54-codex-kernel.md`
3. `docs/kernel-preimplementation-readiness.md`
4. `docs/kernel-unattended-runtime-substrate.md`
5. `docs/kernel-codex-import-strategy.md`
6. `docs/kernel-fugue-migration-audit.md`

If a file conflicts with `AGENTS.md`, `AGENTS.md` wins.

## Read Order

1. Read `AGENTS.md` first.
2. Read this file for Codex-specific orchestration role.
3. In a fresh Codex session opened at this repository root, run `/kernel` before non-trivial work.
4. Read only the Kernel document sections needed for the active task.
5. Load deeper workflow docs only when blocked.

## Kernel Role

- Codex owns control-plane state.
- Codex performs task-shape classification.
- Codex selects adaptive lane topology.
- Codex integrates council outputs.
- Codex decides `ok_to_execute`.
- Claude may participate only as executor, adapter, or council lane.

## Runtime Boundary

- Kernel should absorb `Symphony`-like unattended runtime primitives, not replace Kernel control-plane doctrine with Symphony.
- Accepted runtime primitives include:
  - daemon scheduler / poll loop
  - per-issue isolated workspace lifecycle
  - retry / reconciliation / restart recovery
  - repo-owned workflow contract for future runs
- Rejected ownership transfer includes:
  - control-plane sovereignty
  - council math
  - `ok_to_execute`
  - provider-neutral adapter contract

## Slash Prompt Contract

- The supported entrypoint for Kernel work in this repository is a fresh Codex session started at the repository root and then `/kernel`.
- `/k` is a local one-word alias for `/kernel` in this repository and must obey the same Kernel bootstrap contract.
- The supported local adapter path is `kernel` or `codex-prompt-launch kernel`, both of which must route through `codex-kernel-guard launch` when guard prerequisites are available.
- Treat `codex-kernel-guard launch` as the local execution authority for Kernel orchestration; shell wrappers and prompt launchers are adapters, not the source of truth.
- The authoritative prompt for this repository is `.codex/prompts/kernel.md`.
- The local alias prompt for one-word chat-box startup is `.codex/prompts/k.md`.
- Do not rely on `~/.codex/prompts/kernel.md` alone for repository work; treat the global prompt as convenience only.
- Hot reload is not guaranteed. After changing `.codex/prompts/kernel.md`, start a new Codex session before assuming the update is active.
- If `/kernel` is not recognized, restart Codex from this repository root and retry before doing manual fallback work.
- Bare `/kernel` inside the Codex chat UI is not a local SLO path for this repository; it remains upstream Codex CLI/TUI behavior until proven otherwise.
- `/kernel` bootstrap must launch at least 6 active subagent lanes before the first acknowledgement.
- The minimum operating target is 6 or more concurrent lanes across multiple LLM models or model profiles.
- After bootstrap, `/kernel` must run a 3-round redesign loop by default: at least 6 planning lanes, then at least 3 simulation lanes, then critique, repair, and replan.
- `/kernel` is intended for low-touch autonomous development. Do not stop for fine-grained user approval between ordinary implementation steps.
- The first planning round must define requirements, constraints, acceptance criteria, failure modes, and stop conditions before implementation begins.
- The first planning round must also define the completion proof and identify the external dependencies required to reach it.
- If the user explicitly asks for production verification, the completion proof must define the live rerun or dispatch path, the exact artifact or log evidence to inspect, and the PASS fields required before claiming production success.
- Treat that requirements packet as a hard gate. If it is missing, contradicted by simulation, rejected in critique, or lacks a viable completion proof, do not begin implementation.
- The default baseline model set for `/kernel` planning, critique, and final QA is Codex + Claude + GLM when available; `/kernel` is not a Codex-only design.
- The core `/kernel` development loop should orchestrate across multiple agent families such as Codex, Claude, GLM, Copilot CLI, and Gemini CLI when available; subagents are accelerators, not the core contract.
- Copilot CLI and Gemini CLI are supplemental continuity/specialist lanes, not baseline replacements for Claude or GLM.
- In strict `/vote` and other non-trivial autonomous write gates, missing Claude or GLM must trigger the recovery matrix first: re-probe the direct lane, promote the approved fallback, and backfill replacement sidecars before deciding whether execution can continue.
- Only after those recovery attempts fail with evidence may strict `/vote` or other non-trivial autonomous write gates fail closed.
- Codex should act as the orchestrator and integration layer, not as a Codex-biased majority substitute for the rest of the model set.
- Simulation lanes should prefer `codex-spark`; when it is rate-limited or unavailable, explicitly fall back to Codex multi-agent simulation lanes and record the fallback reason.
- Simulation validation is mandatory before implementation and is the main quality gate for autonomous execution.
- Simulation and critique must be used to break the plan before code changes. They must test whether the completion proof is reachable in the current session, not just whether the proposed code shape is plausible.
- If simulation or critique finds a design flaw, ambiguous requirement, or unresolved external blocker, repair and replan before implementation resumes.
- For unresolved external blockers or dropped providers, run the recovery matrix before returning `BLOCKED`: bridge-authoritative re-probe, approved fallback lane, lane-floor backfill, and exact-error recording.
- `BLOCKED` is valid only when the recovery matrix is exhausted or the remaining blocker is external and not solvable from the current session.
- For production verification tasks, do not stop at a patch, push, dispatch, partial log read, or status memo when concrete execution remains. Continue through live rerun plus artifact or log inspection until PASS or a concrete external blocker is evidenced.
- `codex-multi-agents` is the default Codex fan-out substrate for planning, simulation, repair, and implementation work when available.
- `claude-code-agent-teams` is the default Claude delegation substrate for critique, council, and quality-review work when available.
- Claude and GLM must be treated as real peer lanes in `/kernel`; do not silently collapse the design into Codex-only orchestration.
- Do not treat subagents, `codex-multi-agents`, or `claude-code-agent-teams` alone as sufficient replacement for the multi-model core loop.
- After the 3 redesign rounds, `/kernel` should hand off into `/vote` as fast local implementation continuation rather than treating `/vote` as a user confirmation checkpoint.
- After implementation, `/kernel` must run cross-model quality review, fix the issues found, and only then report completion.
- The first valid acknowledgement must include a `Lane manifest:` section describing currently active lanes, not planned lanes.
- The first valid acknowledgement must also include `Bootstrap target: 6+ lanes (minimum 6).`
- During bootstrap and local analysis, do not request approval for exploratory convenience; exhaust local workspace evidence first.
- Do not request approval for ordinary implementation, analysis, testing, refactoring, or local verification work.
- Only request approval for network, GitHub, or other escalated commands when the user explicitly asked for them or they are strictly required to complete the current task.
- When the user explicitly asks for production verification, live workflow inspection is part of the required completion path and overrides the default no-CI stance for the minimum scope needed to finish the verification.
- Before any approval, escalated network command, or GitHub command that can trigger an approval prompt, quiesce active lanes that can still write to the current TTY.
- Do not surface approval prompts while background Codex activity is still emitting output into the same terminal.
- If lane quiescence cannot be achieved promptly, fail closed with a one-line `quiescence_timeout` status instead of surfacing the approval prompt.
- `/vote` and `/v` are local continuation prompts in this repository. They must not post to GitHub or hand off to issue-comment workflows.
- For non-trivial `/vote` work, the baseline council is `Codex + Claude + GLM`; do not treat 2 lanes as sufficient when the trio is available.
- For non-trivial `/vote` work, if the baseline trio is not available, run the recovery matrix before stopping: re-probe the missing lane, promote the approved fallback provider, and restore the lane floor with sidecars.
- `/vote` must run 3 refinement rounds (`Plan -> Parallel Simulation -> Critical Review -> Problem Fix -> Replan`) before major edits on non-trivial work.
- The same approval-prompt quiescence rule applies to `/vote` and `/v` whenever they would otherwise trigger an approval prompt.
- GitHub `/vote` workflow triggering remains an explicit issue-comment path (`gh issue comment ... --body '/vote'` or `vote-gh ...`), not a Codex slash prompt.
- `/vote`-originated GitHub auto-implement is currently fail-closed: `fugue-codex-implement` is blocked until the reusable workflow can preserve `Codex + Claude + GLM` council continuity through completion.
- Hot reload is not guaranteed for `.codex/prompts/vote.md` and `.codex/prompts/v.md` either. Restart the session after changing them.

## Precision Rule

Use imported Claude-era assets as `knowledge`, not as `authority`.

- Thin adapters and skill triggers may be reused.
- Legacy Claude sovereignty assumptions must not be reused.

## Verification Rule

Before claiming peripheral readiness or migration readiness, use:

- `scripts/sim-kernel-peripherals.sh`
- `scripts/check-sovereign-adapters.sh`

Use this as the default PDCA preflight for Kernel work that touches:

- linked systems
- Discord / LINE
- Cloudflare
- Supabase / Vercel contracts
- Cursorvers business interfaces

For `/kernel` prompt verification:

- static contract check: `bash tests/test-codex-kernel-prompt.sh`
- runtime smoke on a fresh session: `RUN_CODEX_KERNEL_SMOKE=1 bash tests/test-codex-kernel-prompt.sh`
- runtime smoke passes only when the acknowledgement includes `Kernel orchestration is active ...`, `Bootstrap target: 6+ lanes (minimum 6).`, and a lane manifest with at least 6 active lanes
- local smoke or static checks are not sufficient to claim production PASS when the user explicitly requested production verification; inspect the required live evidence before reporting success

For `/vote` prompt verification:

- static contract check: `bash tests/test-codex-vote-prompt.sh`
- runtime smoke on a fresh session: `RUN_CODEX_VOTE_SMOKE=1 bash tests/test-codex-vote-prompt.sh`
- runtime smoke passes only when output includes `Local consensus mode is active.`, `Smoke verification: PASS`, and `Smoke result marker: ...` within `CODEX_VOTE_SMOKE_TIMEOUT_SEC` seconds (default: `90`)
- CI static enforcement: `.github/workflows/fugue-orchestration-gate.yml` runs `bash tests/test-codex-vote-prompt.sh`
- for production verification tasks entered via `/vote`, `BLOCKED` is valid only after the live rerun or verification path has been attempted and failed with a concrete external blocker

## Current Intent

This repository currently contains:

- legacy FUGUE control-plane implementation
- Kernel doctrine and pre-implementation validation

Until Kernel runtime implementation is complete:

- preserve legacy FUGUE behavior unless explicitly migrating a path
- treat Kernel docs and validation harnesses as the source of truth for new control-plane work
- treat `fugue-bridge` as the only acceptable rollback shape for returning control to legacy FUGUE
