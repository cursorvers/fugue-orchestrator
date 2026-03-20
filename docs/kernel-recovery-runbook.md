# Kernel Recovery Runbook

Use this when the local machine or self-hosted subscription runner is unavailable and recovery must be driven from GitHub Web or GitHub Mobile.

For routine phone-based progress checks, the `fugue-status` issue is also kept fresh by `kernel-mobile-progress`, which runs automatically after key orchestration workflows complete.

## Entry Point

- Open `cursorvers/fugue-orchestrator`
- Go to `Actions`
- Run `kernel-recovery-console`

For passive mobile monitoring:

- open the `fugue-status` issue thread
- read the latest `Kernel Mobile Progress Snapshot` comment

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

### `mobile-progress`

Use when you want a phone-friendly progress snapshot without digging through multiple workflow pages.

Behavior:

- generates the same recovery status summary
- appends the top open `fugue-task` issues
- posts the snapshot into the open `fugue-status` issue thread

Recommended input:

- `mode=mobile-progress`

This is the best default when you are away from your desk and just want to see what Kernel is doing from GitHub Mobile.

### `continuity-canary`

Use when the local runner is suspected dead and you want to verify that Kernel can continue from GitHub-hosted execution.

Recommended inputs:

- `mode=continuity-canary`
- `canary_mode=lite`
- `subscription_offline_policy_override=continuity`

This runs the existing canary path with continuity forced from the recovery console.

### `rollback-canary`

Use when you need to verify the `Kernel -> legacy Claude rollback` path while the local machine is unavailable.

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
2. Run `mobile-progress` if you want a phone-friendly thread update
3. If local runner is unhealthy, run `continuity-canary`
4. If legacy rollback must remain available, run `rollback-canary`
5. If a real issue is stuck, run `reroute-issue`

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

## Automatic Mobile Progress

`.github/workflows/kernel-mobile-progress.yml` posts a compact mobile snapshot into the `fugue-status` thread after these workflows complete:

- `kernel-recovery-console`
- `fugue-task-router`
- `fugue-tutti-caller`
- `fugue-orchestrator-canary`
- `fugue-watchdog`

This is the default "read-only from phone" path. If intervention is needed, switch to `kernel-recovery-console`.

## Validation

Validated on `2026-03-07` in production GitHub Actions:

- `status`
  - run `22792645301`
  - success
- `mobile-progress`
  - added after initial recovery rollout
  - posts a compact progress snapshot into the `fugue-status` issue for GitHub Mobile
- `continuity-canary`
  - first run `22792661632`
  - failed because recovery console did not pass org-secret presence flags into `run-canary.sh`
  - fixed in commit `c6a91fc`
  - rerun `22792745904`
  - success
- `rollback-canary`
  - run `22792807635`
  - success
- `reroute-issue`
  - recovery-console run `22792929084`
  - success
  - dispatched `fugue-tutti-caller` run `22792931136`
  - downstream workflow success

Additional hardening:

- `run-recovery-console.sh` now retries `gh api`, `gh issue list`, `gh variable get`, and `gh workflow run`
- this reduces flakiness during transient GitHub API connectivity failures
- post-hardening validation:
  - `status` run `22793030500`
  - success
  - `reroute-issue` run `22793030490`
  - success
  - dispatched `fugue-tutti-caller` run `22793032641`
  - downstream workflow success

Validated behaviors:

- GitHub Mobile compatible `workflow_dispatch`
- continuity canary on GitHub-hosted runner
- `Kernel -> legacy Claude rollback` verification without local shell
- live reroute from the same console into `fugue-tutti-caller`
