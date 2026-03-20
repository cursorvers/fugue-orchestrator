# CODEX.md - Kernel Adapter

Role: Codex is the sovereign orchestrator for `Kernel`.

Primary policy source:

1. `AGENTS.md`
2. `docs/requirements-gpt54-codex-kernel.md`
3. `docs/kernel-preimplementation-readiness.md`
4. `docs/kernel-unattended-runtime-substrate.md`
5. `docs/kernel-codex-import-strategy.md`

`AGENTS.md` is the constitution and always wins over adapter files. For explicit `Kernel` design and implementation work, follow the scope boundary declared in `AGENTS.md`, then use the Kernel docs above as the target-state detail.

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

## Implementation Discipline

- Keep Kernel changes simple and necessary.
- Do not count a rule as implemented when it only exists in prompt text, comments, or docs.
- A Kernel rule is complete only when it has harness/runtime enforcement, receipt or health evidence, and a regression test.
- Do not add features, helpers, abstractions, or convenience layers unless they are indispensable for the active user request or the Kernel safety contract.
- Prefer the smallest concrete change that preserves three-voice diversity, operational continuity, and auditability.
- Reject speculative redesign, side quests, and "nice to have" expansion when a smaller implementation is sufficient.
- If a simpler change can satisfy the request, take it and stop.

## Delivery Discipline

- In this repository, non-trivial requirement definition, planning, implementation, and review are Kernel work by default; do not run them as plain Codex-only work.
- Requirement definition is the first control point. If the goal, acceptance criteria, or non-goals are unclear, wall-bat with the user first and freeze them before implementation.
- Use that early wall-bat to prevent goal drift; do not defer basic requirement clarification until after code changes begin.
- Do not call a plan a Kernel plan unless the required diverse voices for that plan are actually active in the current run.
- Before implementation, run a pre-implementation cycle: gather context, make a plan, simulate or verify it, critique it, then revise it.
- Planning must explicitly account for `glm` and the specialist pool (`gemini-cli`, `cursor-cli`, `copilot-cli`) before implementation starts.
- When Codex subagents are available, reserve exactly one parallel simulation lane to `gpt-5.3-codex-spark` during that pre-implementation cycle.
- Keep other Codex-family subagents role-scoped; do not default every Codex subagent to `gpt-5.3-codex-spark`.
- Use that cycle to surface likely blockers early instead of discovering them one-by-one during implementation.
- Do not stop at "one issue remains" if more likely failure modes can still be found cheaply.
- Default to one-pass delivery: after the revised plan is coherent, continue through implementation and verification without asking the user for routine confirmation.
- Only pause for the user when the next step is destructive, requires external credentials or approval, or is materially ambiguous.
- Do not emit routine intermediate progress reports or midpoint summaries during execution.
- After requirements are frozen, report only when blocked, when external approval is required, when the user explicitly asks, or when final completion is reached.
- Do not stop to summarize partial milestones, sub-slices, or intermediate checkpoints while the active request is still in progress.
- Do not stop execution merely because one stage, track, or implementation slice finished while the broader frozen request remains incomplete.
- Do not emit a completion-style summary until the active request is actually complete or truly blocked.

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
- Reserve one Codex-family sidecar simulation lane on `gpt-5.3-codex-spark` whenever that model profile is available.
- Use `gpt-5.3-codex-spark` only for that dedicated simulation lane by default so simulation stays fast; keep other Codex-family subagents selected by role.
- The normal minimum healthy Kernel shape for this workspace is `codex` + `glm` + one specialist.
- `codex` is the sovereign orchestrator and is not replaceable.
- `Claude` is not part of the Kernel minimum and must never be treated as a bootstrap prerequisite.
- `gemini-cli`, `cursor-cli`, and `copilot-cli` are specialist voices with free-tier or quota limits.
- Optional specialist selection is dynamic. Choose the healthiest available specialist by quota and availability instead of a fixed provider order.
- `kernel-optional-lane-exec.sh auto ...` uses that dynamic selection instead of hard-coded provider priority.
- `copilot-cli` should be treated as a scarce free-tier monthly budget and must stay one-shot by default.
- Optional specialist usage should normally go through `kgemini`, `kcursor`, or `kcopilot`; manual accounting must use `codex-kernel-guard budget-consume`.
- GLM execution should normally go through `kglm` so failure and recovery are recorded into run state automatically.
- If `glm` fails twice in the same run, Kernel may enter `degraded-allowed` and continue as `codex + specialist + specialist` while one parallel lane works on `glm` recovery.
- If `glm` is unavailable at bootstrap time, Kernel should use the degraded shape immediately when two specialist voices are available instead of blocking on `glm`.
- `degraded-allowed` is run-scoped. Guarded launch mints a fresh `KERNEL_RUN_ID` when none is supplied, so the next launch returns to normal evaluation by default.
- `codex-kernel-guard doctor` is the read-only restart surface for active runs; use `--all-runs` only when stale runs must be inspected.
- `codex-kernel-guard doctor --run <run_id>` is the bounded run-detail surface.
- `codex-kernel-guard recover-run <run_id>` is the handoff path for regenerating a heavy-profile tmux session from compact state.
- `1 tmux session = 1 Kernel run = 1 Codex thread` is the Kernel handoff contract.
- `recover-run` must recreate the heavy tmux session and relaunch the run-dedicated Codex thread in the `main` window.
- `doctor -> doctor --run -> recover-run` is the minimal MBP degraded-continuation path.
- `cc pocket` uses `doctor --all-runs -> doctor --run` as the mobile degraded-continuation path and should stay focused on lightweight work.
- `k` is the human-facing shortcut surface: `k`, `k all`, `k latest`, `k run-id`, `k new <purpose> [focus]`, `k adopt <session:window> [purpose]`, `k <run_id>`, `k show <run_id>`, `k open [run_id]`, `k phase <phase>`, `k done <summary...>`.
- `codex-kernel-guard adopt-run <session:window> [purpose]` is the path for turning a live unmanaged tmux window into a Kernel run and moving it into a dedicated heavy-profile session.
- On `Mac mini`, bare `codex` inside the Kernel repo should ask `Kernelを起動しますか? [Y/n]`; `yes` routes to `kernel`, `no` stays on raw Codex.
- On `Mac mini`, `kernel` with no arguments should reopen the latest active run by default; if no active run exists, it should fall through to guarded launch.
- `purpose` is fixed per run; if it drifts materially, create a new run instead of mutating the existing handoff identity.
- `codex-kernel-guard phase-check <phase>` is the required-model evidence gate before phase completion.
- `codex-kernel-guard phase-complete <phase>` records `phase_completed` only after the evidence gate passes.
- `codex-kernel-guard run-complete --summary <text>` records `run_completed` only after verify evidence passes and the backup path succeeds.
- If no valid three-voice shape can be established, Kernel must fail closed instead of reporting healthy multi-model orchestration.
- Kernel work must stay simple-first: do not broaden scope or attach unrequested functionality while satisfying the diversity contract.
- Kernel work must also stay one-pass: perform investigation, revised planning, implementation, and verification as a single continuous flow unless a hard blocker forces a pause.
- Kernel runs should emit and maintain a bootstrap receipt so unattended health checks can verify lane count and provider diversity.
- That bootstrap receipt must also carry live manifest evidence: `Active models`, manifest lane count, and whether agent/subagent labels were present.
- The first valid acknowledgement must include an `Active models:` line listing only models with live evidence from the current run.
- The first valid acknowledgement must include a `Lane manifest:` section describing currently active lanes, not planned lanes.
- Each manifest lane must name its provider, active agent, and concrete subagent label (`subagent1`, `subagent2`, ...) or `none`.
- Unlabeled, pending, failed, or merely planned lanes do not count toward the Kernel minimum.
- The first valid acknowledgement must also include `Bootstrap target: 6+ lanes (minimum 6).`
- `/vote` and `/v` are local continuation prompts in this repository. They must not post to GitHub or hand off to issue-comment workflows.
- GitHub `/vote` workflow triggering remains an explicit issue-comment path (`gh issue comment ... --body '/vote'` or `vote-gh ...`), not a Codex slash prompt.
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

For `/vote` prompt verification:

- static contract check: `bash tests/test-codex-vote-prompt.sh`
- runtime smoke on a fresh session: `RUN_CODEX_VOTE_SMOKE=1 bash tests/test-codex-vote-prompt.sh`
- runtime smoke passes only when output includes `Local consensus mode is active.`, `Smoke verification: PASS`, and `Smoke result marker: ...` within `CODEX_VOTE_SMOKE_TIMEOUT_SEC` seconds (default: `90`)
- CI static enforcement: the orchestration gate workflow runs `bash tests/test-codex-vote-prompt.sh`

## Current Intent

This repository currently contains:

- legacy Claude-side orchestration implementation
- Kernel doctrine and pre-implementation validation

Until Kernel runtime implementation is complete:

- preserve existing non-Kernel paths unless explicitly migrating them
- treat Kernel docs and validation harnesses as the source of truth for new Kernel control-plane work
