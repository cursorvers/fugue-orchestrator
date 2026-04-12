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

## Function-Scoped Auth Profiles

Broad discovery auth such as `gws auth login --full` is acceptable as temporary
operator exploration, but it is not the mature `Kernel` operating baseline.

`Kernel` should use the smallest profile that matches the active lane:

| Profile | Intended lane | Auth mode | Recommended operator command | Notes |
|---|---|---|---|---|
| shared/service-account readonly baseline | `meeting-prep`, `standup-report` | service account | n/a | Preferred CI and shared readonly baseline; keeps Phase 1 useful without mailbox access |
| core readonly operator profile | `meeting-prep`, `standup-report` | user OAuth readonly | `gws auth login --readonly -s calendar,drive` | Mature Phase 1 operator fallback; do not add mailbox scopes by default |
| mailbox readonly operator profile | `weekly-digest`, `gmail-triage` | user OAuth readonly | `gws auth login --readonly -s calendar,gmail,drive` | Phase 2 only; keep separate from the mature core lane |
| bounded write operator profile | `gmail-send`, `docs-create`, `docs-insert-text`, `sheets-append`, `drive-upload`, `calendar-insert` | user OAuth write | `gws auth login -s calendar,gmail,drive,docs,sheets` | Only for previewing or applying approved side effects |
| extension-only profile | `tasks`, `pubsub`, `presentations` | explicit per lane | no default command | Add only while that extension lane is under active validation |

Rules:

- do not treat the recovered March `--full` grant as steady-state policy
- do not mix mailbox scopes into the Phase 1 core profile by default
- do not mix extension scopes into readonly core or bounded-write defaults
- if a narrower profile fails, capture the exact action and missing scope before
  broadening the auth shape

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

## Workspace Write Receipt Contract

Operator-approved or dry-run-validated write helpers must emit a normalized
receipt contract so `Kernel` can persist evidence without treating Workspace as
task-state authority.

Required common metadata fields in `*-meta.json`:

- `side_effect`
- `write_disposition`
- `ok_to_execute`
- `human_approved`
- `receipt`

Machine-readable contract source:

- `config/integrations/googleworkspace-kernel-policy.json`

Required common receipt fields:

- `action`
- `artifact_type`
- `primary_id`

Per-action normalized receipt fields:

| Action | Artifact type | Required receipt fields |
|---|---|---|
| `gmail-send` | `gmail-message` | `primary_id`, `message_id` |
| `drive-upload` | `drive-file` | `primary_id`, `file_id` |
| `calendar-insert` | `calendar-event` | `primary_id`, `event_id` |
| `docs-create` | `google-doc` | `primary_id`, `document_id` |
| `docs-insert-text` | `google-doc` | `primary_id`, `document_id` |
| `sheets-create` | `google-sheet` | `primary_id`, `spreadsheet_id` |
| `sheets-append` | `google-sheet-range` | `primary_id`, `spreadsheet_id`, `updated_range` |

Rules:

- previews and applied writes both use the same normalized receipt shape when
  the underlying helper returns stable ids
- `write_disposition=preview` means a dry-run side-effect preview was recorded
- `write_disposition=applied` means a write ran with both Kernel approval and
  explicit human approval
- `write_disposition=blocked` means a write action was requested without the
  required approval gate
- receipt fields live in run evidence and `*-meta.json`, not in the main prompt
- raw Workspace output may be retained on disk for audit, but success claims use
  the normalized receipt only
- write receipt logging policy must stay explicit in machine-readable policy so
  control-plane checks can validate it without rereading prose docs

## Extension Lane Triage

Extension lanes stay out of the mature core path unless they have an explicit
product reason, a narrow auth story, and a bounded validation path.

| Lane | Decision | Reason | Auth profile | Validation path |
|---|---|---|---|---|
| `tasks` | `defer` | Future email-to-task or follow-up capture may be useful, but it is not required for the mature readonly or bounded-write lane. | `extension-only` | operator-invoked only; do not add to default loops |
| `pubsub` | `drop` | No current Kernel or FUGUE production need justifies expanding into event-watch infrastructure. | `extension-only` | none until a concrete product reason exists |
| `presentations` | `defer` | Possible future digest publishing helper, but not part of the mature lane. | `extension-only` | operator-invoked only after a concrete publishing scenario is defined |

Rules:

- extension decisions must not block Phase 1 or Phase 2 readonly lanes
- extension scopes must not be mixed into the core readonly or bounded-write
  auth profiles
- a deferred lane stays out of default loops until its own validation path is
  active
- machine-readable policy must keep extension actions out of default core phases
  and out of non-extension auth profiles

## FUGUE Compatibility Boundary

Kernel-side Google Workspace work must not break the cached feed evidence path
that legacy `FUGUE` still relies on.

Compatibility rules:

- keep shared readonly feed profiles and personal readonly feed profiles
  separate
- do not rename or remove the shared readonly feed path used by `FUGUE`
- preserve the `Kernel/FUGUE` cached evidence reflection described in
  `docs/googleworkspace-feed-sync-design.md`
- keep Workspace credentials out of the main implementation job for both Kernel
  and legacy FUGUE-compatible paths

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
- `scripts/harness/googleworkspace-scheduled-extract.sh`
  - turns scheduled readonly profiles into cached Workspace feed manifests
- `scripts/harness/googleworkspace-feed-ingest.sh`
  - rehydrates only fresh feed manifests into a bounded context envelope
- `scripts/harness/googleworkspace-fetch-feed-artifacts.sh`
  - fetches the latest successful shared and personal feed artifacts from GitHub Actions
- `scripts/harness/resolve-googleworkspace-feed-matrix.sh`
  - resolves shared vs personal feed profiles into workflow matrices
- `scripts/harness/resolve-orchestration-context.sh`
  - can rehydrate scheduled feed evidence into `workspace_feed_*` outputs for CI
- `scripts/local/googleworkspace-feed-sync-local.sh`
  - remains an operator fallback when local-only replay is needed
- `scripts/local/run-local-orchestration.sh`
  - stores `googleworkspace-feed-context.json` in each local run directory
- `scripts/harness/codex-execute-validate.sh`
  - injects only scheduled feed summaries into Codex instructions as bounded peripheral evidence
- `.github/workflows/fugue-tutti-caller.yml`
  - forwards `workspace_*` hints into the reusable Codex implementation workflow
- `.github/workflows/fugue-codex-implement.yml`
  - runs readonly Workspace preflight in a dedicated protected-environment job
  - uploads Workspace artifact and raw evidence alongside existing protocol logs
  - keeps Workspace credentials out of the main implementation job
- `.github/workflows/googleworkspace-feed-sync.yml`
  - runs low-frequency shared readonly feed sync profiles on schedule or manual dispatch
- `.github/workflows/googleworkspace-personal-feed-sync.yml`
  - runs always-on personal readonly mailbox feeds in a dedicated environment
- `.github/workflows/fugue-status.yml`
  - reports the latest shared and personal Google Workspace feed runs in status comments

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
2. If protected readonly user OAuth export is available, also run
   `gmail-triage` or `weekly-digest` in the personal readonly environment.
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

## Remaining Follow-Ups

1. Add optional read helpers for `drive search`, `docs read`, and `sheets read`
   to reduce fallback raw API usage.
2. Tune phase-specific reinjection rules so only the minimum fresh feed summary
   returns to each prompt.
3. Expand live smoke coverage when new scheduled feed profiles are introduced.

## Resume Note

For the recovered March local OAuth context and the recommended `Kernel` resume
sequence, see:

- `docs/kernel-googleworkspace-resume-plan-2026-03-20.md`
- `docs/kernel-googleworkspace-implementation-todo.md`
