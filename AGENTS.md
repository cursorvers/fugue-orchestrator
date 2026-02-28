# AGENTS.md - FUGUE Orchestration SSOT

This file is the single source of truth for orchestration behavior in this repository.
Adapter files such as `CLAUDE.md` must stay thin and reference this file.

## 1. Context Loading Policy

- Default load: this file only.
- Load additional docs on demand only when blocked.
- Avoid loading long historical rationale unless needed for a decision.
- Keep adapter files short to reduce repeated context overhead.

## 2. Control Plane Contract

- Main orchestrator is provider-agnostic by design.
- Operational default is `claude` (main conductor), with `codex` as execution provider.
- **Hybrid Conductor Mode**: When `FUGUE_EXECUTION_PROVIDER` differs from main orchestrator:
  - Main orchestrator (Claude) handles routing, MCP operations, and Tutti signal.
  - Execution provider (Codex) handles all code implementation.
  - Implementation profile follows `execution_provider` (codex-full), not main (claude-light).
  - Multi-agent mode is NOT locked to `standard` in Hybrid — full lane depth applies.
- **Hybrid Handoff Contract** (applies when Hybrid Conductor Mode is active):
  - Claude resolves routing, MCP artifacts, and Tutti voting topology.
  - Codex receives implementation dispatch via `fugue-codex-implement.yml` with `execution_profile=codex-full`.
  - MCP operations (Pencil, Stripe, Supabase, etc.) are Claude-exclusive; never bridged through Codex.
  - Implementation parameters (`preflight_cycles`, `dialogue_rounds`, `multi_agent_mode`) follow `execution_profile`, not `orchestration_profile`.
- **Hybrid Failover** (when `FUGUE_CLAUDE_RATE_LIMIT_STATE` is `degraded` or `exhausted` during Hybrid):
  - Throttle guard demotes main to `codex`, deactivating Hybrid Conductor Mode.
  - All tasks run through codex-only (no MCP access). MCP-dependent tasks will fail and require manual retry after Claude recovery.
  - Partial failover (MCP task queuing) is reserved for future implementation.
- Operational default is `codex` (both main and execution) when `FUGUE_CLAUDE_RATE_LIMIT_STATE` is `degraded` or `exhausted`.
- `codex` serves as assist sidecar when Claude is main (architectural invariant).
- Claude subscription assumption is `FUGUE_CLAUDE_PLAN_TIER=max20` with `FUGUE_CLAUDE_MAX_PLAN=true`.
- State transitions and PR actions are owned by control plane workflows, not by sidecar advice.
- **v8.5 Tuning** (Claude consumption optimization):
  - `FUGUE_CLAUDE_TRANSLATOR_THRESHOLD` raised to `90` (from `75`) to reduce translation gateway triggers.
  - Claude assist lanes reduced to 1 in subscription mode (Opus only).
  - Target: Claude weekly consumption ≤ 30-40% of MAX20 allocation.

## 3. Provider Resolution Contract

Main resolution order:
1. Issue label (`orchestrator:claude` or `orchestrator:codex`)
2. Issue body hint (`## Orchestrator provider` or `orchestrator provider: ...`)
3. Repository variable `FUGUE_MAIN_ORCHESTRATOR_PROVIDER` (legacy fallback `FUGUE_ORCHESTRATOR_PROVIDER`)
4. Fallback default `claude`

Execution provider resolution:
1. Repository variable `FUGUE_EXECUTION_PROVIDER`
2. Fallback: same as resolved main provider
- When `FUGUE_EXECUTION_PROVIDER` differs from resolved main, Hybrid Conductor Mode activates.

Assist resolution order:
1. Issue label (`orchestrator-assist:claude|codex|none`)
2. Issue body hint (`## Assist orchestrator provider` or inline hint)
3. Repository variable `FUGUE_ASSIST_ORCHESTRATOR_PROVIDER`
4. Fallback default `claude`

Throttle guard:
- If resolved **main** provider is `claude` and state is `degraded` or `exhausted`, auto-fallback to `codex`.
- If resolved **assist** provider is `claude` and state is `exhausted`, auto-fallback to `none`.
- If resolved **main** is `claude` and resolved **assist** is also `claude`, apply pressure guard (`FUGUE_CLAUDE_MAIN_ASSIST_POLICY=codex|none`, default `codex`) unless forced.
- Per-issue override: label `orchestrator-force:claude` or CLI `--force-claude`.

Auditability:
- Fallback decisions must be commented on the issue.
- CLI pre-fallback must leave an explicit audit comment.

## 4. Execution/Evaluation Lanes

- Core quorum: 6 lanes minimum (Codex3 + GLM3).
- `FUGUE_MIN_CONSENSUS_LANES` (default `6`) is a hard floor; lane matrix resolution fails fast when the configured floor is not met.
- Add one main-provider signal lane after resolution:
  - `codex-main-orchestrator` when main is `codex`
  - `claude-main-orchestrator` when main is `claude`
- In Hybrid Conductor Mode (main != execution_provider), implementation dispatch always uses `codex-full` profile regardless of main provider.
- `FUGUE_DUAL_MAIN_SIGNAL=true` (default) adds the opposite main signal lane as a secondary vote signal.
- Execution profile is resolved per run:
  - Primary: `subscription-strict` (`FUGUE_CI_EXECUTION_ENGINE=subscription` + online self-hosted runner with required label `FUGUE_SUBSCRIPTION_RUNNER_LABEL`)
  - Offline hold: `subscription-paused` (`FUGUE_SUBSCRIPTION_OFFLINE_POLICY=hold`)
  - Continuity fallback: `api-continuity` (`FUGUE_SUBSCRIPTION_OFFLINE_POLICY=continuity`, default, or emergency continuity mode)
- `FUGUE_EMERGENCY_CONTINUITY_MODE=true` enables inflight-only processing on GitHub-hosted runners.
- Continuity fallback demotes assist `claude` using `FUGUE_EMERGENCY_ASSIST_POLICY` (default `none`) unless forced.
- Strict guards (`FUGUE_STRICT_MAIN_CODEX_MODEL`, `FUGUE_STRICT_OPUS_ASSIST_DIRECT`) are enforced in `subscription-strict` and disabled by default in API continuity mode unless `FUGUE_API_STRICT_MODE=true`.
- `FUGUE_REQUIRE_DIRECT_CLAUDE_ASSIST=true` enables hard gate for `claude-opus-assist` direct success in `/vote` integration (default disabled).
- `FUGUE_REQUIRE_CLAUDE_SUB_ON_COMPLEX=true` enforces Claude sub gate on complex tasks (`risk_tier=high` or ambiguity translation-gate=true) **when assist is `claude`**; missing Claude Opus assist success turns `ok_to_execute=false` (default enabled).
- `FUGUE_REQUIRE_BASELINE_TRIO=true` enforces baseline trio success (`codex` + `claude` + `glm`) before execution approval (default enabled).
- Multi-agent depth baseline is controlled by `FUGUE_MULTI_AGENT_MODE=standard|enhanced|max` (default `enhanced`), with complexity-based downshift/upshift when no explicit override is present.
- Codex lane model split:
  - `FUGUE_CODEX_MAIN_MODEL` for `codex-main-orchestrator` (default `gpt-5.3-codex`)
  - `FUGUE_CODEX_MULTI_AGENT_MODEL` for non-main codex lanes (default `gpt-5.3-codex-spark`)
- GLM baseline model: `glm-5.0`.
- `FUGUE_ALLOW_GLM_IN_SUBSCRIPTION=true` (default) keeps GLM baseline voters active even when `FUGUE_CI_EXECUTION_ENGINE=subscription` (hybrid: codex/claude via CLI, GLM via API).
- Codex recursive delegation (`parent -> child -> grandchild`) can be enabled per-lane:
  - `FUGUE_CODEX_RECURSIVE_DELEGATION` (`true|false`, default `true` since v8.5)
  - `FUGUE_CODEX_RECURSIVE_MAX_DEPTH` (minimum `2`, default `2` since v8.5, previously `3`)
  - `FUGUE_CODEX_RECURSIVE_TARGET_LANES` (CSV lane list or `all`, default `codex-main-orchestrator,codex-orchestration-assist`)
  - `FUGUE_CODEX_RECURSIVE_DRY_RUN` (`true|false`, default `false`, synthetic verification mode)
  - Implementation timeout extended to 90 minutes when recursive delegation is active.
- GLM subagent fan-out is controlled by `FUGUE_GLM_SUBAGENT_MODE=off|paired|symphony` (default `symphony` since v8.5, previously `paired`).
  - `paired`: adds GLM orchestration subagent lane and mirrors architect/plan checks in enhanced/max.
  - `symphony`: adds the above plus GLM reliability subagent in max mode (v8.5 default; adds `glm-reliability-subagent` lane).
  - When `FUGUE_ALLOW_GLM_IN_SUBSCRIPTION=false`, subscription mode forces GLM subagent fan-out to `off`.
  - `*-subagent` lanes are optional/non-blocking on provider-side API failure.
- When assist is `claude` and state is not `exhausted`, add Claude assist lanes (Opus + Sonnet).
- Local direct orchestration (`scripts/local/run-local-orchestration.sh`) enforces `claude-opus-assist` direct success when either:
  - `assist=claude`, `FUGUE_LOCAL_REQUIRE_CLAUDE_ASSIST=true`, and `FUGUE_CLAUDE_RATE_LIMIT_STATE=ok` (legacy direct gate), or
  - `assist=claude`, `FUGUE_LOCAL_REQUIRE_CLAUDE_ASSIST_ON_COMPLEX=true`, and task is complex (`risk_tier=high` or `FUGUE_LOCAL_AMBIGUITY_SIGNAL=true`) (default enabled).
- In `FUGUE_CLAUDE_MAX_PLAN=true` mode without `ANTHROPIC_API_KEY`, Claude assist lanes run through Codex proxy and remain vote participants.
- Optional specialist lanes:
  - Gemini for UI/UX and visual intent (including subscription when `FUGUE_ALLOW_GLM_IN_SUBSCRIPTION=true`).
  - xAI for X/Twitter and realtime intent.
- Optional lane failures are non-blocking for quorum totals.

## 5. Safety and Governance

- High-risk finding blocks auto-execution and escalates to human review.
- Tutti execution decisions use weighted consensus (role-weighted 2/3 threshold) plus HIGH-risk veto.
- Review-only intent must clear stale implementation labels.
- Natural-language/mobile intake defaults to `review`; implement requires explicit signal.
- Implementation execution requires both `implement` and `implement-confirmed`.
- Cross-repo implementation requires `TARGET_REPO_PAT`.
- Dangerous operations require explicit human consent paths.
- Implement mode must complete preflight refinement loops before code changes:
  1) Plan
  2) Parallel Simulation
  3) Critical Review
  4) Problem Fix
  5) Replan
  Repeat default 3 cycles (`FUGUE_IMPLEMENT_REFINEMENT_CYCLES=3`).
- After preflight passes, implement mode must run implementation collaboration dialogue rounds:
  - `Implementer Proposal` -> `Critic Challenge` -> `Integrator Decision` -> `Applied Change` -> `Verification`
  - Default rounds: `FUGUE_IMPLEMENT_DIALOGUE_ROUNDS=2` (or `FUGUE_IMPLEMENT_DIALOGUE_ROUNDS_CLAUDE=1` when `execution_profile` is `claude-light`; in Hybrid Conductor Mode, `execution_profile=codex-full` applies full rounds).
- Parallel Simulation and Critical Review are hard gates and must not be skipped.
- For large refactor/rewrite/migration tasks, each cycle must explicitly compare at least two candidates and include failure-mode/rollback checks (`large-refactor` label or task-text detection).
- Risk-tier policy (`low|medium|high`) adjusts minimum loop depth and default review fan-out; low-risk defaults should stay lightweight.

## 6. Workflow Ownership

- Issue intake and natural-language handoff:
  - `.github/workflows/fugue-task-router.yml`
  - Default behavior: `fugue-task` issues auto-handoff to mainframe unless manual opt-out markers are present.
  - Natural-language default mode is review-first; implement must be explicit and confirmed.
- Mainframe orchestration gate:
  - `.github/workflows/fugue-tutti-caller.yml`
- Tutti quorum integration:
  - `.github/workflows/fugue-tutti-router.yml`
- Implementation engine:
  - `.github/workflows/fugue-codex-implement.yml`
- Operational health:
  - `.github/workflows/fugue-watchdog.yml`
  - `.github/workflows/fugue-status.yml`

## 7. Adapter Contract

Adapter files (`CLAUDE.md`, `CODEX.md`) must contain only:
- Role-specific deltas that cannot live in SSOT.
- Pointers to this file and a minimal command reference.
- No duplicated long policy text from SSOT.

## 8. Simulation Runbook

Use deterministic simulation before changing orchestration logic:

```bash
scripts/sim-orchestrator-switch.sh
```

Simulation common rule:
- `FUGUE_SIM_CODEX_SPARK_ONLY=true` (default) forces simulation to run `codex-main` and codex multi-agent lanes on `gpt-5.3-codex-spark` for faster turnaround.
- Set `FUGUE_SIM_CODEX_SPARK_ONLY=false` only when main-model parity testing against `gpt-5-codex` is explicitly required.

Use live rehearsal only when needed and clean up synthetic issues after verification.

## 9. Shared Skills Baseline (Codex/Claude)

- FUGUE useful third-party skills must be curated and pinned.
- Baseline manifest:
  - `config/skills/fugue-openclaw-baseline.tsv`
- Shared sync script (provider-agnostic):
  - `scripts/skills/sync-openclaw-skills.sh`
- Profile details:
  - `docs/fugue-skills-profile.md`

Security guardrails:
- Do not install unpinned third-party skills directly from `main`.
- Reject skills with unsafe auto-execution guidance (`--yolo`, `--full-auto`) in default profile.
- Keep Codex and Claude skill sets synchronized from the same manifest so orchestrator switching does not change capabilities.

## 10. Shared Workflow Playbook (Codex/Claude)

- Provider-agnostic playbook source:
  - `rules/shared-orchestration-playbook.md`
- The playbook applies to both orchestrator profiles:
  - `codex-full`
  - `claude-light`
- Control-plane enforcement in implement mode must keep:
  - Preflight refinement loop gates
  - Implementation collaboration dialogue gates
  - Research artifact (`.fugue/pre-implement/issue-<N>-research.md`)
  - Plan artifact (`.fugue/pre-implement/issue-<N>-plan.md`)
  - Critic artifact (`.fugue/pre-implement/issue-<N>-critic.md`)
  - Task tracking artifact (`.fugue/pre-implement/issue-<N>-todo.md`)
  - Lessons artifact (`.fugue/pre-implement/lessons.md`)
  - MUST/SHOULD/MAY boundaries with staged context budget (see `rules/shared-orchestration-playbook.md`)
  - Always-on over-compression guard via `FUGUE_CONTEXT_BUDGET_MIN_INITIAL`, `FUGUE_CONTEXT_BUDGET_MIN_MAX`, `FUGUE_CONTEXT_BUDGET_MIN_SPAN`
  - Parallel preflight nodes for research/plan/critic (`FUGUE_PREFLIGHT_PARALLEL_ENABLED`, timeout: `FUGUE_PREFLIGHT_PARALLEL_TIMEOUT_SEC`)

## 11. Local Linked Systems (Video/Note/Obsidian)

- Local direct mode can chain external systems in parallel after Tutti integration.
- Source of truth:
  - `config/integrations/local-systems.json`
- Linked runner:
  - `scripts/local/run-linked-systems.sh`
- Adapter scripts:
  - `scripts/local/integrations/*.sh`
- Safety gate:
  - `run-local-orchestration.sh --linked-mode execute` must only run when `ok_to_execute=true`; otherwise skip.
