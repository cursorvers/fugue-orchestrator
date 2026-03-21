# Kernel Google Workspace Goal 2026-03-20

## Primary Goal

Make Google Workspace useful to `Kernel` as a bounded peripheral adapter
without letting it become orchestration truth.

## Phase 1 Goal

For the first implementation slice, keep the goal narrow:

- make `meeting-prep` and `standup-report` reliable readonly evidence sources
  for `Kernel` `preflight enrich`
- return only bounded summary envelopes to `Kernel`
- degrade safely to `skipped` or `partial` when credentials or APIs are not
  available

## Why This Goal

Recovered March local OAuth state showed that Workspace work had already moved
beyond pure design and into local operator validation, but the granted scope set
was broader than the minimum needed for the highest-value `Kernel` path.

That means the right move is not to preserve the broad login. The right move is
to resume from the smallest production-relevant boundary.

## Done When

Phase 1 is complete when all of the following are true:

1. `meeting-prep` can supply bounded readonly evidence to `Kernel`
2. `standup-report` can supply bounded readonly evidence to `Kernel`
3. missing credentials or API restrictions degrade to `skipped` or `partial`
   without blocking the whole run
4. raw Workspace payloads do not re-enter the main prompt
5. the service-account readonly path is still useful even without mailbox access

## Current Status

Local live verification has now passed for the prepared readonly lanes.

- Phase 1 live: passed
  - `meeting-prep`: `ok`
  - `standup-report`: `ok`
  - report: `.fugue/kernel-googleworkspace-workset/phase1-run/phase1-report.md`
- Phase 2 live: passed
  - `weekly-digest`: `ok`
  - `gmail-triage`: `ok`
  - report: `.fugue/kernel-googleworkspace-workset/phase2-mailbox-run/phase2-mailbox-report.md`

This means the local workset has moved beyond "ready to start live validation"
and into "local live evidence captured" for the prepared readonly tracks.

GitHub Actions workflow changes are still intentionally deferred. Use
`.fugue/kernel-googleworkspace-workset/gha-handoff-2026-03-20.md` as the
handoff note if this work is promoted into a GHA-facing validation path.

## Deferred Until After Phase 1

These are valid follow-up lanes, but they are not part of the first goal:

- `weekly-digest`
- `gmail-triage`
- bounded Workspace write helpers
- auth minimization by function
- extension lanes such as `tasks`, `pubsub`, and `presentations`

## Local Start Point

Without requiring GitHub issue creation or fresh user re-authentication, the
local Phase 1 execution start points are:

- `.fugue/pre-implement/issue-9101-todo.md`
- `scripts/local/run-kernel-googleworkspace-phase1.sh --prepare`
- `scripts/local/simulate-kernel-googleworkspace-phase1.sh`

For the follow-up tracks prepared in the same local workset:

- `.fugue/pre-implement/issue-9102-todo.md`
- `scripts/local/run-kernel-googleworkspace-phase2-mailbox.sh --prepare`
- `scripts/local/simulate-kernel-googleworkspace-phase2-mailbox.sh`
- `bash scripts/check-googleworkspace-kernel-contract.sh`

## Non-Goals

- making Google Workspace the source of task state
- requiring user mailbox access for the first milestone
- introducing unattended write actions in the default loop
- treating the recovered broad local OAuth grant as steady-state policy
