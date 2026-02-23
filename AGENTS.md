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
- Operational default is `codex` (main), with `claude` as assist sidecar.
- Operational default is `codex` when `FUGUE_CLAUDE_RATE_LIMIT_STATE` is `degraded` or `exhausted`.
- `claude` can run as assist sidecar for ambiguity resolution and integration quality.
- Claude subscription assumption is `FUGUE_CLAUDE_PLAN_TIER=max20` with `FUGUE_CLAUDE_MAX_PLAN=true`.
- State transitions and PR actions are owned by control plane workflows, not by sidecar advice.

## 3. Provider Resolution Contract

Main resolution order:
1. Issue label (`orchestrator:claude` or `orchestrator:codex`)
2. Issue body hint (`## Orchestrator provider` or `orchestrator provider: ...`)
3. Repository variable `FUGUE_MAIN_ORCHESTRATOR_PROVIDER` (legacy fallback `FUGUE_ORCHESTRATOR_PROVIDER`)
4. Fallback default `codex`

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
- Add one main-provider signal lane after resolution:
  - `codex-main-orchestrator` when main is `codex`
  - `claude-main-orchestrator` when main is `claude`
- Execution profile is resolved per run:
  - Primary: `subscription-strict` (`FUGUE_CI_EXECUTION_ENGINE=subscription` + online self-hosted runner with required label `FUGUE_SUBSCRIPTION_RUNNER_LABEL`)
  - Offline hold: `subscription-paused` (`FUGUE_SUBSCRIPTION_OFFLINE_POLICY=hold`, default)
  - Continuity fallback: `api-continuity` (`FUGUE_SUBSCRIPTION_OFFLINE_POLICY=continuity` or emergency continuity mode)
- `FUGUE_EMERGENCY_CONTINUITY_MODE=true` enables inflight-only processing on GitHub-hosted runners.
- Continuity fallback demotes assist `claude` using `FUGUE_EMERGENCY_ASSIST_POLICY` (default `none`) unless forced.
- Strict guards (`FUGUE_STRICT_MAIN_CODEX_MODEL`, `FUGUE_STRICT_OPUS_ASSIST_DIRECT`) are enforced in `subscription-strict` and disabled by default in API continuity mode unless `FUGUE_API_STRICT_MODE=true`.
- Multi-agent depth baseline is controlled by `FUGUE_MULTI_AGENT_MODE=standard|enhanced|max` (default `enhanced`), with complexity-based downshift/upshift when no explicit override is present.
- GLM baseline model: `glm-5.0`.
- When assist is `claude` and state is not `exhausted`, add Claude assist lanes (Opus + Sonnet).
- In `FUGUE_CLAUDE_MAX_PLAN=true` mode without `ANTHROPIC_API_KEY`, Claude assist lanes run through Codex proxy and remain vote participants.
- Optional specialist lanes:
  - Gemini for UI/UX and visual intent.
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
  - Default rounds: `FUGUE_IMPLEMENT_DIALOGUE_ROUNDS=2` (or `FUGUE_IMPLEMENT_DIALOGUE_ROUNDS_CLAUDE=1` when main is `claude`).
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
  - Task tracking artifact (`.fugue/pre-implement/issue-<N>-todo.md`)
  - Lessons artifact (`.fugue/pre-implement/lessons.md`)
  - MUST/SHOULD/MAY boundaries with staged context budget (see `rules/shared-orchestration-playbook.md`)
