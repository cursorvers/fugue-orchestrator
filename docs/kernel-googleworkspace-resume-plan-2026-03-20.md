# Kernel Google Workspace Resume Plan 2026-03-20

## Goal

Turn the recovered local OAuth context into an intentional `Kernel` resume path
instead of leaving it as an undocumented one-off setup.

Phase 1 goal is narrower than the full recovered Workspace surface:

- make `meeting-prep` and `standup-report` reliable readonly evidence sources
  for `Kernel` `preflight enrich`
- return only bounded summary envelopes to `Kernel`
- degrade safely to `skipped` or `partial` when credentials or APIs are not
  available

This document does not replace
`docs/kernel-googleworkspace-integration-design.md`. It explains what the
recovered March local auth state most likely supported, how `Kernel` should use
that information, and what to resume next.

Execution checklist companion:

- `docs/kernel-googleworkspace-implementation-todo.md`

## Recovered Signal

Most likely timeline:

- `2026-03-07`
  - `Kernel` Google Workspace readonly preflight and feed-sync work landed
  - main changes were user OAuth readonly preflight, auth-boundary feed split,
    and feed reinjection into `Kernel` context
- `2026-03-18`
  - local `gws` OAuth artifacts were created under `~/.config/gws/`
  - a broad scope selection matching `gws auth login --full` was used
  - local API enable / project checks happened immediately before and after
    this setup

Recovered local auth artifacts:

- `~/.config/gws/client_secret.json`
- `~/.config/gws/credentials.enc`
- `~/.config/gws/token_cache.json`

Recovered likely command intent:

- `gws auth setup`
- `gws auth login --full`

## What The Broad Scope Set Probably Meant

The recovered scope selection was broader than the minimum currently needed by
the most mature `Kernel` Google Workspace flows.

Most likely interpretation:

1. the local operator wanted one development login that could unlock all nearby
   Google Workspace experiments
2. the practical validation target was narrower than the granted scope set
3. the mature target flows were still the readonly and bounded-write flows
   already documented in the integration design

High-confidence Phase 1 targets:

- `meeting-prep`
- `standup-report`

High-confidence later targets after Phase 1 is stable:

- `weekly-digest`
- `gmail-triage`
- bounded write helpers such as `gmail-send`, `docs-create`,
  `docs-insert-text`, `sheets-append`, and `drive-upload`

Lower-confidence secondary targets enabled by the broad login:

- `tasks`
  - future `email-to-task` style workflow extension
- `pubsub`
  - event / notification / watch-oriented extensions
- `presentations`
  - future Workspace-side slide delivery or digest publishing helpers

## How Kernel Should Use This Recovery

`Kernel` should treat this recovered auth state as a resume hint, not as a
policy to preserve forever.

The value is not the broad scope set itself. The value is that it reveals the
unfinished execution order:

1. design the Workspace adapter boundary
2. implement readonly preflight and feed sync
3. prove the flows on real operator data with local OAuth
4. reduce the auth surface after the real minimum is known

This means the recovery should be used in three ways.

### 1. Resume The Right Work

Resume the work that was closest to production value:

- readonly preflight for issue enrichment
- personal readonly digest generation
- bounded write previews for operator-approved follow-up actions

For Phase 1, treat only `meeting-prep` and `standup-report` as mandatory.
`weekly-digest` and `gmail-triage` should not block the first `Kernel`
Workspace milestone because they depend more heavily on user OAuth and personal
mailbox access.

Do not resume by starting with `Tasks`, `Pub/Sub`, or Slides-specific expansion.
Those are extension lanes, not the shortest path to `Kernel` value.

### 2. Separate Core From Expansion

Use the recovered auth set to split the roadmap into:

- `Kernel core Workspace lane`
  - Phase 1 core:
    - `meeting-prep`
    - `standup-report`
  - later mature readonly / write additions:
    - `weekly-digest`
    - `gmail-triage`
    - `docs-create`
    - `docs-insert-text`
    - `sheets-append`
    - `drive-upload`
- `extension lane`
  - `email-to-task`
  - event/watch flows that need `Pub/Sub`
  - slide publishing / presentation helpers

This reduces the chance that unfinished extension work blocks the core `Kernel`
adapter path.

### 3. Convert Discovery Into Policy

The recovered broad login should become explicit policy guidance:

- broad `--full` auth is acceptable for short-lived local discovery
- `Kernel` operating docs should target least-privilege by function
- readonly CI / scheduled paths should stay separate from operator write paths
- `Kernel` should document which flows require user OAuth and which can remain
  on service-account readonly paths

## Recommended Resume Order

### Phase 1: Reconfirm Preflight Readonly Evidence

Primary objective:

- prove that `Kernel` can enrich `preflight` with bounded readonly Workspace
  evidence even when auth is incomplete or partial

Resume targets:

- `gws workflow +meeting-prep`
- `gws workflow +standup-report`

Success condition:

- `Kernel` can inject a bounded evidence summary without depending on raw
  Workspace payloads
- missing credentials or API limits degrade to `skipped` or `partial` without
  blocking the whole run

### Phase 2: Add User OAuth Readonly Mailbox Flows

Primary objective:

- add personal mailbox-derived readonly evidence only after Phase 1 is stable

Resume targets:

- `gws workflow +weekly-digest`
- `gws gmail +triage --max 10`

Success condition:

- user OAuth readonly flows enrich `Kernel` without redefining the core
  preflight contract

### Phase 3: Reconfirm Bounded Write Helpers

Primary objective:

- prove operator-approved side effects are still previewable and reversible

Resume targets:

- `gmail-send --dry-run`
- `docs-create`
- `docs-insert-text`
- `sheets-append`
- `drive-upload`

Success condition:

- `Kernel` can produce previewable write receipts and store stable artifact ids

### Phase 4: Minimize Scopes By Function

Primary objective:

- replace the recovered development auth shape with function-oriented auth

Recommended target profile split:

- shared/service-account readonly baseline
  - `calendar.readonly`
  - `drive.readonly`
- core readonly operator profile
  - `calendar.readonly`
  - `drive.readonly`
- mailbox readonly operator profile
  - `calendar.readonly`
  - `gmail.readonly`
  - `drive.readonly`
- bounded write operator profile
  - `calendar`
  - `gmail.modify`
  - `drive`
  - `documents`
  - `spreadsheets`
- extension profile only when needed
  - `tasks`
  - `pubsub`
  - `presentations`
  - `cloud-platform`

Success condition:

- `Kernel` no longer depends on one catch-all local auth grant to move forward

## Concrete Next Steps For Kernel

1. keep `docs/kernel-googleworkspace-integration-design.md` as the architecture
   source of truth
2. treat this document as the execution resume note for the March local OAuth
   recovery
3. re-verify the Phase 1 readonly path before touching mailbox or extension lanes
4. document minimum-scope login commands for core readonly, mailbox readonly,
   and bounded-write paths
5. isolate extension work behind explicit follow-up tasks instead of bundling it
   into the default operator auth flow

Suggested minimum-scope operator re-login for the mature core readonly path:

```bash
gws auth login --readonly -s calendar,drive
```

Suggested mailbox readonly re-login only when Phase 2 mailbox evidence is
under active validation:

```bash
gws auth login --readonly -s calendar,gmail,drive
```

Suggested bounded-write re-login only when actively validating write helpers:

```bash
gws auth login -s calendar,gmail,drive,docs,sheets
```

Only add extension scopes when that specific extension lane is active.

Migration guidance from the recovered March auth state:

1. treat the previous `gws auth login --full` grant as discovery history, not
   as the mature operating baseline
2. do not delete the recovered credentials before validating a narrower profile
3. validate Phase 1 first with the shared/service-account readonly baseline or
   the core readonly operator profile
4. move to the mailbox readonly profile only when `weekly-digest` or
   `gmail-triage` is the active track
5. move to the bounded-write profile only when previewing or applying approved
   side effects
6. add `tasks`, `pubsub`, `presentations`, or `cloud-platform` scopes one lane
   at a time instead of folding them into the default profile
7. if a narrower profile fails, record the exact action and missing scope before
   broadening the auth shape

## Decision

Use the recovered March auth state as evidence that the `Kernel` Google
Workspace lane was already past pure design and had entered local operator
validation.

Resume from that point.

That means:

- do not restart discovery from zero
- do not preserve `--full` as the steady-state policy
- do resume readonly evidence enrichment first
- do move extension scopes behind explicit follow-up lanes
