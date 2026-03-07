# Kernel Recovery Runbook

Use this when the local machine or self-hosted subscription runner is unavailable and recovery must be driven from GitHub Web or GitHub Mobile.

## Entry Point

- Open `cursorvers/fugue-orchestrator`
- Go to `Actions`
- Run `kernel-recovery-console`

This workflow is designed to be operable from a phone. It requires only `workflow_dispatch`.

## Modes

### `status`

Use first. This reports:

- current Claude rate-limit state
- online self-hosted runner count
- pending `fugue-task` issues
- latest runs for:
  - `fugue-orchestrator-canary`
  - `fugue-watchdog`
  - `fugue-task-router`
  - `fugue-tutti-caller`

### `continuity-canary`

Use when the local runner is suspected dead and you want to verify that Kernel can continue from GitHub-hosted execution.

Recommended inputs:

- `mode=continuity-canary`
- `canary_mode=lite`
- `subscription_offline_policy_override=continuity`

This runs the existing canary path with continuity forced from the recovery console.

### `rollback-canary`

Use when you need to verify the `Kernel -> FUGUE` rollback path while the local machine is unavailable.

Recommended inputs:

- `mode=rollback-canary`
- `canary_mode=lite`
- `subscription_offline_policy_override=continuity`

This runs the regular Kernel canary and also verifies the rollback lane.

### `reroute-issue`

Use when an issue is stuck and must be re-driven from GitHub only.

Required input:

- `issue_number`

Behavior:

- if the issue already has `tutti` or `processing`, dispatch `fugue-tutti-caller`
- if the issue has `fugue-task` but not `tutti`, dispatch `fugue-task-router`

Recommended inputs:

- `handoff_target=kernel` for normal recovery
- `handoff_target=fugue-bridge` when forcing legacy rollback
- `subscription_offline_policy_override=continuity`

## Mobile Recovery Sequence

1. Run `status`
2. If local runner is unhealthy, run `continuity-canary`
3. If legacy rollback must remain available, run `rollback-canary`
4. If a real issue is stuck, run `reroute-issue`

## Recovery Guarantees

- does not require local shell access
- does not require repo `.env`
- uses the same GitHub-hosted scripts as normal orchestration
- preserves `Kernel` as the primary path and `fugue-bridge` as rollback

## Notes

- Shared CI secrets remain `org-first`
- Runtime secrets remain `platform-first`
- This workflow is intentionally minimal and reuses:
  - `scripts/harness/run-canary.sh`
  - `fugue-task-router.yml`
  - `fugue-tutti-caller.yml`
