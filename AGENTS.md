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
- Operational default is `codex` when `FUGUE_CLAUDE_RATE_LIMIT_STATE` is `degraded` or `exhausted`.
- `claude` can run as assist sidecar for ambiguity resolution and integration quality.
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
- Per-issue override: label `orchestrator-force:claude` or CLI `--force-claude`.

Auditability:
- Fallback decisions must be commented on the issue.
- CLI pre-fallback must leave an explicit audit comment.

## 4. Execution/Evaluation Lanes

- Core quorum: 6 lanes minimum (Codex3 + GLM3).
- CI lane execution engine defaults to `harness` (`FUGUE_CI_EXECUTION_ENGINE=harness|api`).
- GLM baseline model: `glm-5.0`.
- When assist is `claude` and state is not `exhausted`, add Claude assist lanes (Opus + Sonnet).
- In `FUGUE_CLAUDE_MAX_PLAN=true` mode without `ANTHROPIC_API_KEY`, Claude assist lanes run through Codex proxy and remain vote participants.
- Optional specialist lanes:
  - Gemini for UI/UX and visual intent.
  - xAI for X/Twitter and realtime intent.
- Optional lane failures are non-blocking for quorum totals.

## 5. Safety and Governance

- High-risk finding blocks auto-execution and escalates to human review.
- Review-only intent must clear stale implementation labels.
- Cross-repo implementation requires `TARGET_REPO_PAT`.
- Dangerous operations require explicit human consent paths.

## 6. Workflow Ownership

- Issue intake and natural-language handoff:
  - `.github/workflows/fugue-task-router.yml`
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

Adapter files (`CLAUDE.md`, future `CODEX.md`) must contain only:
- Role-specific deltas that cannot live in SSOT.
- Pointers to this file and a minimal command reference.
- No duplicated long policy text from SSOT.

## 8. Simulation Runbook

Use deterministic simulation before changing orchestration logic:

```bash
scripts/sim-orchestrator-switch.sh
```

Use live rehearsal only when needed and clean up synthetic issues after verification.
