# CODEX.md - Thin Adapter

Role: Codex is an orchestrator adapter for this repository.
Primary policy source is `AGENTS.md`.

## 1. Read Order

1. Read `AGENTS.md` first.
2. Read only the specific workflow/docs sections needed for the current task.
3. Do not load large reference files unless blocked.

## 2. Codex-Specific Deltas

- Codex is the safe default main orchestrator when Claude is throttled.
- Main/assist provider selection and fallback must stay audit-visible on each issue.
- Keep implementation ownership in workflow gates (`vote` + risk), not in ad-hoc bypasses.

## 3. Operational Anchors

- Intake and handoff:
  - `.github/workflows/fugue-task-router.yml`
- Provider resolution and fallback:
  - `.github/workflows/fugue-tutti-caller.yml`
  - `.github/workflows/fugue-tutti-router.yml`
- CLI entry:
  - `scripts/gha24`

## 4. Commands

- Submit a request:
  - `./scripts/gha24 "task" --review`
  - `./scripts/gha24 "task" --implement`
- Provider override:
  - `./scripts/gha24 "task" --orchestrator codex`
  - `./scripts/gha24 "task" --assist-orchestrator codex`
  - `./scripts/gha24 "task" --orchestrator claude --force-claude`
- Deterministic simulation:
  - `scripts/sim-orchestrator-switch.sh`
- Shared skills baseline sync:
  - `scripts/skills/sync-openclaw-skills.sh --target both`

## 5. Rule

If this file conflicts with `AGENTS.md`, `AGENTS.md` wins.
