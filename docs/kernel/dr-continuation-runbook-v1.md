# Kernel DR Continuation Runbook v1

## Goal

Continue a frozen Kernel run when `Mac mini` is unavailable, without relying on any FUGUE runtime path.

## Roles

- `Mac mini`: primary execution node
- `MBP`: full continuation node
- `cc pocket`: mobile degraded continuation node
- `GHA`: mirror and audit surface only

## Required Surfaces

- shared secret resolver:
  - `process env -> Keychain -> shared SOPS bundle -> explicit external env file`
- `doctor`
- `compact artifact`
- `recover-run`

## MBP Continuation

1. Connect by `Tailscale` and open the repository.
2. Resolve shared secrets through the standard loader.
   - Prefer Keychain for normal local continuation.
   - If Keychain is absent or locked, use the shared SOPS bundle as a DR restore fallback.
   - Treat GitHub org secrets as the CI plane, not as a local read backend.
3. Run `codex-kernel-guard doctor --all-runs`.
4. Identify the target by:
   - `project`
   - `purpose`
   - `tmux_session`
   - `phase`
   - `mode`
   - `next_action`
   - `updated_at`
5. Inspect bounded detail by `codex-kernel-guard doctor --run <run_id>`.
6. If the session exists, attach to the tmux session.
7. If the session is missing, run `codex-kernel-guard recover-run <run_id>`.
8. Resume from the recorded `phase`, `mode`, and single `next_action`.

## cc pocket Continuation

1. Open the repository through the mobile shell.
2. Run `codex-kernel-guard doctor --all-runs`.
3. Use `codex-kernel-guard doctor --run <run_id>` to inspect:
   - `run_id`
   - `active_models`
   - `blocking_reason`
   - `summary`
4. Continue only lightweight work:
   - bounded inspection
   - compact review
   - light editing
   - light execution
   - light tests
5. Heavy build or large refactor ownership should move back to `MBP` or `Mac mini`.

## Recovery Model

- If a tmux session exists, continuation is session attach.
- If a tmux session is missing, continuation is run recovery from compact state.
- Recovery must preserve:
  - `current_phase`
  - `mode`
  - `next_action`
  - `active_models`
  - `updated_at`
- If required evidence for the current phase is missing, resume from the phase entry instead of blindly continuing.

## Success Criteria

- `doctor` lets an operator decide what to resume, where to attach, and what to do next.
- `recover-run` regenerates the heavy tmux profile from compact state.
- `MBP` can continue a stale run from artifacts.
- `cc pocket` can inspect and continue lightweight work from the same artifacts.
- `MBP` and `Mac mini` resolve the same canonical shared-secret names without
  printing values; `doctor` output is limited to present/missing, source, and length.
