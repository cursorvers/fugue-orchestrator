# Kernel Mini/MBP Operations Topology

This document fixes the intended long-running host topology for `Kernel`.

Goal:

- `mac mini` becomes the always-on `Kernel primary`
- `MBP` becomes the human-operated high-power workstation
- `GitHub Actions` remains a warm standby continuity plane
- the legacy Claude rollback path remains available

This is the recommended production layout once the new MBP arrives and the current `mac mini` can be dedicated to 24/7 orchestration.

Related front-door design:

- `Happy.app` single-front architecture:
  [kernel-happy-app-single-front-architecture.md](./kernel-happy-app-single-front-architecture.md)
- `Tailscale` / `Railway` edge and admin split:
  [kernel-tailscale-railway-integration-design.md](./kernel-tailscale-railway-integration-design.md)
- `Kernel` unattended runtime substrate:
  [kernel-unattended-runtime-substrate.md](./kernel-unattended-runtime-substrate.md)

## Plasticity Rule

This topology must preserve reversibility back to the legacy Claude rollback path.

That means:

- `Kernel` is the default sovereign path
- the legacy Claude rollback path remains a first-class rollback sovereign adapter
- host placement must not hard-code one irreversible orchestrator choice
- the same mobile and GitHub entry points should continue to work even if the sovereign path changes
- the same secret plane should remain valid for both `Kernel` and the legacy Claude rollback path

## Role Assignment

### 1. `mac mini` = Kernel Primary

`mac mini` is the main always-on host.

Responsibilities:

- run the local `Kernel` daemon
- host the unattended runtime substrate scheduler / reconciler
- host the self-hosted subscription runner
- execute normal local-first development tasks
- keep `Codex CLI`, `Claude CLI`, `Gemini CLI`, and local adapters available
- publish status and evidence back to GitHub / Cloudflare / Discord / LINE

Why `mac mini`:

- stable power
- fewer sleep/close-lid failure modes
- better fit for unattended daemon operation
- better separation from the human interactive workstation

### 2. `MBP` = Operator / Heavy Workstation

`MBP` is not the always-on primary. It is the human-operated control cockpit.

Responsibilities:

- `tmux`-based long-running operator sessions
- high-context manual intervention
- large refactors and complex multi-agent work
- attended `Claude`, `Codex`, and `Gemini` execution
- GUI-dependent checks such as local design/tools review

Why `tmux` on MBP:

- maintain multiple long-running interactive panes
- keep review / implementation / logs separated
- reconnect safely if the terminal UI is interrupted

### 3. `GitHub Actions` = Warm Standby

`GitHub Actions` is not the primary path during normal healthy local operation.

Responsibilities:

- continuity when `mac mini` is unavailable
- canary
- watchdog
- mobile-accessible recovery
- progress snapshots into `fugue-status`

### 4. Legacy Claude Rollback

The legacy Claude path remains the rollback and legacy continuity path.

Use it when:

- `Kernel` must temporarily hand back execution
- a legacy-compatible route is safer
- rollback verification is required

The legacy Claude path should be treated as a live compatibility path, not dead legacy.

It remains:

- a rollback sovereign adapter
- a hedge against `Kernel` regressions
- a temporary continuity option
- a possible future primary if policy ever changes again

## Topology Diagram

```text
                           ┌──────────────────────────────┐
                           │ Smartphone / GitHub Mobile   │
                           │ Happy.app / Cockpit (future) │
                           └──────────────┬───────────────┘
                                          │
                                          v
                     ┌───────────────────────────────────────────┐
                     │ Kernel Intake / GitHub / Cloudflare Edge  │
                     └──────────────┬────────────────────────────┘
                                    │
            ┌───────────────────────┼────────────────────────┐
            │                       │                        │
            v                       v                        v
┌──────────────────────┐  ┌──────────────────────┐  ┌──────────────────────┐
│ mac mini             │  │ GitHub Actions       │  │ Claude rollback      │
│ Kernel primary       │  │ warm standby         │  │ legacy path          │
│ local daemon         │  │ continuity/canary    │  │ fugue-bridge         │
│ runtime substrate    │  │ recovery substrate   │  │                      │
│ self-hosted runner   │  │ mobile recovery      │  │                      │
└──────────┬───────────┘  └──────────┬───────────┘  └──────────────────────┘
           │                         │
           v                         v
┌──────────────────────┐  ┌──────────────────────┐
│ local adapters       │  │ status / recovery    │
│ Codex / Claude /     │  │ issue #55            │
│ Gemini / MCP / bus   │  │ canary / reroute     │
└──────────┬───────────┘  └──────────────────────┘
           │
           v
┌──────────────────────────────────────────────────┐
│ Cursorvers / Cloudflare / Supabase / Discord /  │
│ LINE / linked systems / protected interfaces    │
└──────────────────────────────────────────────────┘


Human operator path:

MBP + tmux
  -> attach to long-running interactive sessions
  -> intervene, review, or run heavy attended work
  -> does not replace mac mini as primary
```

## Sovereign Adapter Boundary

The host topology and the active orchestrator must stay decoupled.

```text
smartphone / GitHub / Happy.app / Cockpit
  -> neutral intake packet
  -> handoff selector
       -> kernel
       -> fugue-bridge
  -> shared host plane
       -> mac mini primary host
       -> MBP operator workstation
       -> GHA standby continuity plane
```

This is the main plasticity rule:

- users should not need a different mobile or issue flow just because the sovereign path changes
- only `handoff_target` should change
- host and secret planes should stay reusable

## MBP `tmux` Layout

Recommended default session:

```text
session: kernel-ops

pane 1: Codex main working session
pane 2: Claude executor / reviewer
pane 3: Gemini / specialist lane
pane 4: logs / gh run watch / canary / recovery
```

Recommended usage:

- pane 1: implementation or orchestration task
- pane 2: second-opinion review or large-diff inspection
- pane 3: UI/UX or specialist work when needed
- pane 4: monitoring and recovery commands

MBP should be treated as:

- an operator cockpit
- not the single source of truth for orchestration state

## Failover Model

### Normal

- `mac mini` healthy
- `Kernel primary = local`
- `GitHub Actions = standby`
- legacy Claude rollback path only

### Local degraded

- `mac mini` unhealthy or offline
- use `kernel-recovery-console`
- switch to `continuity-canary` or `reroute-issue`
- `GitHub Actions` becomes temporary continuity path

### Legacy fallback

- if continuity through `Kernel` is not desirable
- use `rollback-canary` or `handoff_target=fugue-bridge`
- the legacy Claude path becomes the temporary execution path

### Re-promotion to Legacy Claude Rollback

If the legacy Claude rollback path ever needs to become more than a temporary rollback path:

- keep the same GitHub / mobile entry points
- keep the same host plane
- keep the same secret plane
- keep the same progress and recovery surfaces
- switch the active sovereign path from `kernel` to `fugue-bridge`

The system should never require a full infrastructure redesign just to re-promote the legacy Claude rollback path.

## State and Progress Rules

To keep failover safe:

- state must not live only inside one local shell
- progress must be reflected to GitHub issue / workflow / status thread
- mobile-visible status must remain available even when local is down

That means:

- `fugue-status` issue stays the mobile-readable status thread
- `kernel-mobile-progress` continues posting snapshots
- `kernel-recovery-console` remains the emergency control surface

These progress surfaces must stay neutral between `Kernel` and the legacy Claude rollback path.

## Service Model on `mac mini`

Preferred long-running services:

- `Kernel local daemon`
- self-hosted GitHub runner
- healthcheck / restart supervisor
- local adapter services that must remain hot

Preferred management style:

- `launchd` or equivalent service supervision
- not an always-open manual terminal

`tmux` is acceptable on `mac mini` for debugging, but not as the primary service supervisor.

Service naming and wiring should prefer neutral execution roles over irreversible orchestrator-specific assumptions.

## Why not make `MBP` the Primary?

`MBP` can temporarily act as primary during setup or migration, but it is not the preferred long-term primary.

Reasons:

- lid/sleep behavior
- battery/power transitions
- more frequent human interruption
- GUI workload colliding with unattended orchestration

The correct long-term split is:

- `mac mini` = primary
- `MBP` = operator

## Smartphone Workflow

### Read-only progress

- open `fugue-status` issue
- read latest `Kernel Mobile Progress Snapshot`

### Manual refresh

- run `kernel-recovery-console`
- set `mode=mobile-progress`

### Recovery

- `mode=status`
- `mode=continuity-canary`
- `mode=rollback-canary`
- `mode=reroute-issue`

If the legacy Claude rollback path must be reactivated from phone:

- keep the same workflow
- change `handoff_target` to `fugue-bridge`
- keep the same progress thread

## Deployment Sequence

Recommended order once the new MBP arrives:

1. stabilize `MBP` as the operator workstation
2. dedicate `mac mini` to always-on `Kernel primary`
3. move long-running local execution to `mac mini`
4. keep `GHA` as warm standby
5. continue validating legacy Claude rollback

## Success Criteria

This topology is considered complete when:

- a task can be submitted from phone
- progress can be read from phone
- normal execution happens on `mac mini`
- operator intervention happens from `MBP`
- `GHA` can continue when `mac mini` fails
- the legacy Claude rollback path remains valid
- the legacy Claude rollback path can be re-promoted without redesigning the host or secret plane
