# Kernel mac mini Warm-Standby Status (2026-03-08)

## Summary

- `mac mini` is now the primary execution lane for local orchestration.
- GitHub Actions can run in `record-only` mode during normal operation.
- `fugue-watchdog` derives failover state from primary heartbeat freshness plus self-hosted runner state.
- safe fallback is available from GitHub when the primary lane is offline.
- heavy fallback remains manual-only.

## What Is Now Possible

### 1. Primary execution on `mac mini`

- local orchestration can run as the main path
- execution start/end can refresh primary heartbeat automatically
- login-time bootstrap can restore the heartbeat agent after re-login

### 2. Warm-standby on GitHub Actions

- normal state:
  - `FUGUE_GHA_EXECUTION_MODE=record-only`
  - GitHub Actions keep audit, routing, and status visibility
- degraded/offline state:
  - safe GitHub-hosted fallback can resume status/routing lanes
  - `backup-safe` is allowed
- heavy state:
  - `backup-heavy` requires explicit human approval
  - implement-style jobs do not auto-fail over

### 3. Heartbeat-backed failover

- primary heartbeat is written to repo variables `FUGUE_PRIMARY_HEARTBEAT_*`
- heartbeat write order is hardened so `FUGUE_PRIMARY_HEARTBEAT_AT` is updated last
- `fugue-watchdog`, `fugue-task-router`, `fugue-tutti-caller`, and `fugue-codex-implement` re-evaluate live failover state instead of trusting stale repo values blindly

### 4. Safer credential handling

- heartbeat auth is no longer injected through `launchctl setenv GH_TOKEN`
- each heartbeat process resolves auth per process
- recommended hardening remains:
  - set repo-scoped fine-grained PAT in `FUGUE_HEARTBEAT_GH_TOKEN`

### 5. Verified `/vote` trigger path

- issue comment `/vote` on `cursorvers/fugue-orchestrator#190` was posted successfully on `2026-03-07T14:32:07Z`
- the following `issue_comment` workflows were confirmed immediately after:
  - `fugue-status`
  - `fugue-task-router`
  - `fugue-caller`

## Operating Model

- primary:
  - `mac mini`
- standby:
  - GitHub-hosted Actions
- automatic standby scope:
  - status
  - routing
  - record keeping
  - safe orchestration support
- manual-only scope:
  - implement
  - large write actions
  - metered heavy fallback

## Current Constraints

- split-brain resistance is improved but not absolute
- a separate lease store is still the next hardening step if strict network-partition safety is required
- heavy fallback is intentionally gated to avoid duplicate execution and surprise spend

## Recommended Defaults

- `FUGUE_GHA_EXECUTION_MODE=record-only`
- `FUGUE_GHA_BACKUP_HEAVY_ENABLED=false`
- keep login bootstrap plist loaded
- keep launchd heartbeat plist loaded
- prefer `FUGUE_HEARTBEAT_GH_TOKEN` over `gh auth token` fallback
