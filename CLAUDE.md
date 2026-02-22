# CLAUDE.md - Thin Adapter

Role: Claude is an orchestrator adapter for this repository.
Primary policy source is `AGENTS.md`.

## 1. Read Order

1. Read `AGENTS.md` first.
2. Read only the specific workflow/docs sections needed for the current task.
3. Do not load large reference files unless blocked.

## 2. Claude-Specific Deltas

- When Claude is rate-limited, fallback behavior is controlled by:
  - `FUGUE_CLAUDE_RATE_LIMIT_STATE`
  - `orchestrator-force:claude`
  - `--force-claude` in `scripts/gha24`
- Claude sidecar can be used for ambiguity resolution and synthesis quality,
  but control-plane state transitions remain workflow-owned.

## 3. Operational Anchors

- Intake and handoff:
  - `.github/workflows/fugue-task-router.yml`
- Provider resolution and fallback:
  - `.github/workflows/fugue-tutti-caller.yml`
  - `.github/workflows/fugue-tutti-router.yml`
- CLI entry:
  - `scripts/gha24`
- Shared workflow playbook:
  - `rules/shared-orchestration-playbook.md`

## 4. Commands

- Submit a request:
  - `./scripts/gha24 "task" --review`
  - `./scripts/gha24 "task" --implement`
- Provider override:
  - `./scripts/gha24 "task" --orchestrator codex`
  - `./scripts/gha24 "task" --orchestrator claude`
  - `./scripts/gha24 "task" --orchestrator claude --force-claude`
- Deterministic simulation:
  - `scripts/sim-orchestrator-switch.sh`
- Shared skills baseline sync:
  - `scripts/skills/sync-openclaw-skills.sh --target both`

## 5. Rule

If this file conflicts with `AGENTS.md`, `AGENTS.md` wins.
