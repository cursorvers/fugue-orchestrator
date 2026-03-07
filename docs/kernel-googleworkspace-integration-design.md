# Kernel Google Workspace Integration Design

## Goal

Integrate `googleworkspace/cli` into `Kernel` as a bounded peripheral adapter
family for operator workflows.

This design keeps Google Workspace outside the control plane while making it
available for:

- context gathering
- operator briefing
- artifact publishing
- stakeholder coordination

## Core Rules

1. Google Workspace is a peripheral service boundary, not orchestration truth.
2. `SKILL.md + gws CLI` is the default route. `gws mcp` is optional only.
3. Read-only actions are the default. Write actions require explicit approval.
4. Output returned to `Kernel` must be summarized and bounded.
5. Authentication must stay outside workspace `.env` files.

## Placement In Kernel

`Kernel` already separates the sovereign core from the execution and adapter
plane. Google Workspace belongs only in the adapter plane.

- `Kernel Sovereign Core`
  - decides whether Workspace is relevant
  - decides whether side effects are allowed
- `Execution + Adapter Plane`
  - runs `googleworkspace-cli-readonly`
  - runs `googleworkspace-cli-write`
- `Verification + Rollback`
  - validates adapter contract and smoke paths
  - does not treat Workspace as rollback authority

## Adapter Family

Current adapters:

- `googleworkspace-cli-readonly`
  - `scope`: `skill`
  - `kind`: `knowledge`
  - `authority`: `service-adapter`
  - `validation_mode`: `smoke`
- `googleworkspace-cli-write`
  - `scope`: `skill`
  - `kind`: `service`
  - `authority`: `service-adapter`
  - `validation_mode`: `smoke`

Current command surface:

- read-only:
  - `meeting-prep`
  - `standup-report`
  - `weekly-digest`
  - `gmail-triage`
- write-capable:
  - `gmail-send`
  - `drive-upload`
  - `calendar-insert`
  - `docs-create`
  - `docs-insert-text`
  - `sheets-create`
  - `sheets-append`

## Authentication Modes

### Service Account Read Only

Use for unattended or scheduled `Kernel` routines.

Allowed baseline:

- `meeting-prep`
- `standup-report`
- `drive files list`

Limit:

- no Gmail mailbox access without domain-wide delegation

### User OAuth Read Only

Use for operator-bound context gathering.

Allowed baseline:

- `meeting-prep`
- `standup-report`
- `weekly-digest`
- `gmail-triage`

### User OAuth Write

Use only after both of these are true:

- `Kernel` has reached `ok_to_execute=true`
- a human has explicitly approved the side effect

Allowed baseline:

- `gmail-send`
- `drive-upload`
- `calendar-insert`
- `docs-create`
- `docs-insert-text`
- `sheets-create`
- `sheets-append`

## Kernel Phase Mapping

| Kernel phase | Trigger | Adapter | Typical actions | Auth mode | Approval gate | Kernel result |
|---|---|---|---|---|---|---|
| Intake classify | issue mentions meeting, inbox, doc, drive, report | readonly | none by default; mark Workspace relevance only | none | none | route hint only |
| Preflight enrich | plan needs human context | readonly | `meeting-prep`, `gmail-triage`, `weekly-digest`, `standup-report` | service account or user read-only | none | summarized evidence block |
| Scheduled operator loop | morning, pre-meeting, weekly cron | readonly | `standup-report`, `meeting-prep`, `weekly-digest` | service account for narrow flows, user read-only for Gmail | scheduler policy | digest artifact |
| Execute dry-run | side effect is proposed | write | `gmail-send`, `drive-upload`, `calendar-insert` with `--dry-run` where supported | user write | no execution yet | side-effect preview |
| Approved execute | publish or notify | write | any validated write action | user write | `ok_to_execute=true` and human approval | side-effect receipt |
| Post-execute sync | task completed and deliverables exist | write | `docs-create`, `docs-insert-text`, `sheets-append`, `drive-upload`, `gmail-send` | user write | already approved | generated artifact ids |
| Recovery rehydrate | stale issue or interrupted run | readonly | `meeting-prep`, `weekly-digest`, `gmail-triage` | user read-only | none | refreshed context summary |

## Evidence Envelope

`Kernel` should never ingest full Workspace payloads into the main prompt by
default. The adapter result should be reduced into an evidence envelope:

```json
{
  "source": "googleworkspace-cli",
  "adapter_id": "googleworkspace-cli-readonly",
  "action": "meeting-prep",
  "side_effect": false,
  "summary": "Next meeting is Project Sync at 10:00 JST with 3 attendees and 2 linked docs.",
  "references": [
    { "kind": "calendar-event", "id": "event-id" },
    { "kind": "drive-file", "id": "file-id-1" },
    { "kind": "drive-file", "id": "file-id-2" }
  ],
  "raw_output_path": ".fugue/run/<run-id>/googleworkspace/meeting-prep.json"
}
```

Rules:

- `summary` is the only field intended for prompt re-entry
- `references` carry stable ids for follow-up actions
- `raw_output_path` points to local evidence, not active prompt context
- write actions must add a receipt field such as `message_id`, `file_id`, or
  `event_id`

## Approval Model

### Read Only

- may run during preflight
- may run during scheduled digests
- may run during recovery
- must remain bounded in size

### Write

- must not run during intake
- should be preceded by `--dry-run` when the underlying `gws` action supports it
- must require `ok_to_execute=true`
- must require explicit operator approval
- must produce a receipt recorded by `Kernel`

## Context Budget Rules

To avoid context pressure:

- prefer `--format table` for direct operator viewing
- prefer narrow `json` for machine summarization
- summarize before reinjecting into the sovereign prompt
- avoid raw schema or tool catalogs in default loops
- avoid `gws mcp` unless a client cannot consume CLI flows

## Validation Policy

Default validation:

- `scripts/check-peripheral-adapters.sh`
- `scripts/check-googleworkspace-live.sh`

Current implemented baseline:

- `scripts/lib/orchestrator-nl-hints.sh`
  - emits Workspace route hints from issue text
- `scripts/harness/resolve-orchestration-context.sh`
  - exports Workspace hints and policy-derived phase hints in CI
- `scripts/local/run-local-orchestration.sh`
  - stores `googleworkspace-context.json` in each local run directory
- `scripts/lib/googleworkspace-cli-adapter.sh`
  - writes raw outputs and `*-meta.json` receipts under `<run-dir>/googleworkspace/`
  - enforces `ok_to_execute` and explicit human approval on write actions
- `scripts/harness/googleworkspace-preflight-enrich.sh`
  - converts readonly Workspace hints into a bounded CI artifact
  - returns `ok`, `partial`, or `skipped`
  - degrades to `skipped` when CI credentials are unavailable
- `.github/workflows/fugue-tutti-caller.yml`
  - forwards `workspace_*` hints into the reusable Codex implementation workflow
- `.github/workflows/fugue-codex-implement.yml`
  - runs readonly Workspace preflight in a dedicated protected-environment job
  - uploads Workspace artifact and raw evidence alongside existing protocol logs
  - keeps Workspace credentials out of the main implementation job

Kernel admission rules:

- `googleworkspace-cli-readonly`
  - cheap smoke is required in the default loop
- `googleworkspace-cli-write`
  - smoke is limited to command resolution or `--dry-run`
  - actual write canaries stay operator-invoked

## Initial Operating Scenarios

### 1. Meeting-Driven Issue

1. Intake detects calendar-related work.
2. Preflight runs `meeting-prep`.
3. Kernel writes a short evidence block into the research artifact.
4. If follow-up material is needed, operator may approve Docs or Gmail writes.

### 2. Morning Operator Brief

1. Scheduler invokes `standup-report`.
2. If user OAuth is available, also run `gmail-triage` or `weekly-digest`.
3. Kernel emits one digest artifact and does not mutate state elsewhere.

### 3. Stakeholder Delivery

1. Task reaches `ok_to_execute=true`.
2. Kernel resolves a dry-run preview for `docs-create`, `drive-upload`, or
   `gmail-send`.
3. Operator approves.
4. Kernel executes and stores artifact ids and receipts in run evidence.

## Non-Goals

- making Google Workspace the source of task state
- replacing GitHub issue state with Calendar or Gmail state
- allowing unattended write actions in the default loop
- forcing session-backed MCP adapters into this same shape

## Next Implementation Steps

1. Add a `Kernel` evidence writer that stores summarized Workspace envelopes
   under a dedicated run directory.
2. Add intent-to-action routing in the intake classifier for meeting, inbox,
   document, and reporting signals.
3. Add optional read helpers for `drive search`, `docs read`, and `sheets read`
   to reduce fallback raw API usage.
4. Add an approval receipt log for Workspace write actions.
5. Keep CI Workspace auth limited to optional readonly service-account secrets;
   do not run unattended write actions in reusable workflows.
6. Require a protected GitHub `Environment` such as `workspace-readonly` before
   CI can access readonly Workspace credentials.
