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
   - in this repository, treat non-trivial requirement definition, planning, implementation, and review as Kernel work by default; do not continue them as plain Codex-only work
   - treat requirement definition as critical work; if the goal, acceptance criteria, or non-goals are not yet sharp, wall-bat with the user first and freeze them before implementation
   - use early clarification to prevent goal drift, not as a substitute for implementation
   - for non-critical work, continue under local `/vote` consensus by default; critical issues are the only exemption to that default
   - do not label a plan as a Kernel plan unless the required diverse voices for that plan are actually active in the current run
   - decompose the work into independent lanes before proceeding
   - launch at least 6 materially distinct subagents immediately before any substantive analysis
   - the bootstrap target is at least 6 concurrent lanes spanning multiple LLM models or model profiles when available
   - required kernel voices for this workspace are `codex`, `glm`, and one specialist from `gemini-cli`, `cursor-cli`, or `copilot-cli`
   - `codex` is the sovereign orchestrator and is not replaceable
   - `Claude` is optional in Kernel and must not be treated as a bootstrap prerequisite
   - treat `gemini-cli`, `cursor-cli`, and `copilot-cli` as specialist lanes with free-tier or quota limits
   - optional specialist selection is dynamic; choose the healthiest available specialist by quota and availability instead of a fixed provider order
   - treat `copilot-cli` free usage as scarce monthly budget and avoid autopilot by default
   - activate optional specialist lanes through `kgemini`, `kcursor`, or `kcopilot`, or manually reserve quota with `codex-kernel-guard budget-consume <provider> 1 <note>`
   - route GLM execution through `kglm` whenever feasible so failures and recoveries are recorded automatically
   - if `glm` fails twice in the same run, mark the run `degraded-allowed` with `codex-kernel-guard glm-fail <note>`, continue with two specialist voices, and keep one parallel lane focused on restoring `glm`
   - if `glm` is unavailable at bootstrap time, do not wait for it indefinitely; activate the degraded shape immediately if two specialist voices are available
   - keep at least one lane focused on execution or exploration, at least one separate lane focused on verification or review, and at least one separate lane focused on monitoring, risk, or context gathering
   - start parallel excitation immediately for independent lanes
   - reserve the main thread for routing, synthesis, conflict resolution, and final integration
3. Complete a pre-implementation cycle before editing or irreversible actions:
   - gather context thoroughly enough to expose likely blockers before implementation
   - if uncertainty remains after context gathering, explicitly say that you do not have enough information instead of guessing
   - produce a concrete plan for the active request
   - planning diversity must explicitly account for `glm` and the specialist pool (`gemini-cli`, `cursor-cli`, `copilot-cli`) before implementation starts
   - for long or source-grounded inputs, extract direct quotes first and analyze only those quotes
   - simulate or verify the plan with tests, dry-runs, static checks, or bounded command-level rehearsal whenever feasible
   - when Codex subagents are available, reserve exactly one dedicated Codex-family simulation lane in parallel on `gpt-5.3-codex-spark`
   - keep other Codex-family subagents role-specific; do not default every Codex subagent to `gpt-5.3-codex-spark`
   - critique the first plan, surface weaknesses, and revise it before implementation
   - only start implementation after the revised plan is coherent, minimal, and defensible
   - do not stop at "one issue remains" if more likely blockers can still be discovered in the pre-implementation cycle
   - define a receipt strategy for unattended visibility before implementation starts
4. Enforce Kernel rules during execution:
   - parallel first: independent tasks must always run in parallel
   - before finalizing a claim-heavy answer, verify each claim against available quotes or sources and remove unsupported claims
   - do not treat a rule as implemented when it exists only in prompt text, comments, or docs
   - a Kernel rule is incomplete until it is enforced by launch/guard or runtime code, reflected in receipt/health evidence, and covered by a regression test
   - treat `/kernel` bootstrap itself as non-trivial work, so the multi-agent minimum applies during startup as well
   - maintain at least 6 materially distinct active lanes for the full duration of non-trivial work, including startup, implementation, verification, and reporting
   - treat 6 or more concurrent lanes across multiple LLM models or model profiles as the minimum operating shape
   - do not collapse, defer, or silently degrade to single-thread execution
   - if a valid three-voice shape cannot be established, fail closed instead of calling the session healthy
   - valid shapes are:
     - normal: `codex + glm + specialist`
     - degraded-allowed: `codex + specialist + specialist` only after `glm` has failed twice in the same run
   - `BLOCKED` is valid only when neither the normal shape nor the degraded-allowed shape can be established
   - if the environment cannot sustain 6 active lanes, fail closed instead of degrading below the Kernel minimum
   - if a primary path is inherently serial, create parallel sidecar lanes for verification, monitoring, context gathering, or review instead of running single-lane
   - treat de-parallelization as a policy violation unless the user explicitly revokes Kernel orchestration
   - do not add helpers, abstractions, or features that the user did not ask for unless they are strictly required to preserve the Kernel minimum contract
   - prefer the smallest concrete change that satisfies the request, preserves diversity, and keeps the system operational
   - reject speculative redesign, side quests, and "nice to have" functionality when a simpler implementation is sufficient
5. Return a short acknowledgement only after the lanes are active.
6. Include a lane manifest in the acknowledgement:
   - first line: `Kernel orchestration is active for this session.`
   - second line: `Bootstrap target: 6+ lanes (minimum 6).`
   - third line: `Active models: <main model>, <diversity model>, <diversity model> ...`
   - fourth line: `Lane manifest:`
   - then at least 6 flat bullets in the form `- <lane name>: <role> - <focus> [provider:<provider>] [agent:<agent>] [subagent:<subagent1|subagent2|...|none>]`
   - the manifest must describe currently active lanes, not planned lanes
7. Continue the task. Do not stop after the acknowledgement.

Constraints:
- Keep output concise and operational.
- Treat Kernel as parallel orchestration, not a single-agent continuation mode.
- Do not substitute intentions, plans, or promises for active multi-agent lanes.
- Prefer multiple LLM models for the 6-lane-or-more baseline whenever the environment supports them.
- Prefer `gpt-5.3-codex-spark` for the dedicated Codex-side simulation lane when that model profile is available.
- Use `gpt-5.3-codex-spark` only for that dedicated simulation lane by default so simulation stays fast; keep other Codex-family subagents selected by role.
- Do not require `Claude` for Kernel bootstrap or adjudication; treat it as an optional extra voice only.
- Do not claim multi-model orchestration if only Codex lanes are active.
- In the lane manifest, name the provider for each lane and indicate whether it is `codex`, `glm`, or `specialist`.
- In the lane manifest, explicitly identify the active agent and the concrete subagent label (`subagent1`, `subagent2`, ...) or `none` for every lane.
- Do not count unlabeled, pending, failed, or merely planned lanes toward the manifest.
- `Active models:` must list only models with live evidence from the current run.
- Treat `gemini-cli`, `cursor-cli`, and `copilot-cli` as quota-aware specialist candidates; skip unavailable candidates, but fail closed if no required specialist voice can be activated.
- Choose the specialist lane dynamically by live health and quota; on MBP prefer `copilot-cli` when `gemini-cli` reviewer lanes are unhealthy, and avoid assuming a fixed specialist order.
- Before the first acknowledgement, write a bootstrap receipt with `bash scripts/lib/kernel-bootstrap-receipt.sh write <lane_count> <providers_csv> <normal|degraded-allowed>`.
- When writing that receipt, also set `KERNEL_BOOTSTRAP_ACTIVE_MODELS_CSV`, `KERNEL_BOOTSTRAP_MANIFEST_LANE_COUNT`, `KERNEL_BOOTSTRAP_AGENT_LABELS=true`, and `KERNEL_BOOTSTRAP_SUBAGENT_LABELS=true` so unattended health can verify live manifest evidence instead of trusting provider counts alone.
- Update that bootstrap receipt again when Kernel mode changes so unattended health checks do not drift from reality.
- If `glm` recovery succeeds after the run has entered `degraded-allowed`, keep the run degraded and return to the normal shape only in the next run.
- Treat "next run" as the next distinct `KERNEL_RUN_ID`; guarded launch will mint one automatically when it is absent.
- Default to one-pass delivery: complete investigation, revised planning, implementation, and verification in one flow unless blocked by destructive risk, missing credentials, or external approval.
- Front-load user interaction into requirement definition: clarify the goal rigorously at the start, then avoid routine confirmation churn after the target is aligned.
- Do not ask the user to confirm routine progress between planning and implementation.
- Once a successful local auth, unlock, or trust proof exists in the run, reuse it across lanes and do not re-request equivalent user auth for non-critical work.
- Do not emit routine intermediate progress reports or midpoint summaries during execution.
- After requirements are frozen, report only when blocked, when external approval is required, when the user explicitly asks, or when final completion is reached.
- Do not pause execution to summarize a partial milestone, sub-slice, or intermediate checkpoint while the active request is still in progress.
- Do not stop execution merely because one stage, track, or implementation slice finished while the broader frozen request remains incomplete.
- Do not emit a completion-style summary until the active request is actually complete or truly blocked.
- Do not broaden scope or add convenience features unless they are indispensable for the active request or Kernel safety contract.
- Do not post to GitHub or any external service.
- Do not summarize repository state, CI state, or production state unless asked.
- Do not ask for confirmation just to start Kernel orchestration.
