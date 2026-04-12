# Kernel Google Workspace Issue Drafts 2026-03-20

Use these drafts as direct source material for GitHub issues via the
`FUGUE Task (Mobile / Natural Language)` template.

For a copy-paste-ready Phase 1 issue body, see:

- `docs/kernel-googleworkspace-issue-1-ready.md`
- `docs/kernel-googleworkspace-issue-2-ready.md`
- `docs/kernel-googleworkspace-issue-3-ready.md`
- `docs/kernel-googleworkspace-issue-4-ready.md`
- `docs/kernel-googleworkspace-issue-5-ready.md`

Recommended common settings:

- `Mainframe handoff`: `auto`
- `Execution mode`: `implement` for code/docs changes, `review` if only
  confirming scope and behavior first
- `Implementation confirmation`: `confirmed` only when autonomous execution is
  desired
- `Main orchestrator provider`: `codex`
- `Assist orchestrator provider`: `claude`
- `Multi-agent mode`: `auto`
- `Target repo`: `cursorvers/fugue-orchestrator`

Recommended bootstrap command before implementation:

```bash
bash scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh \
  --issue-number <N> \
  --track readonly-evidence
```

## Draft 1

### Suggested title

`task: revalidate kernel google workspace readonly evidence lane`

### Goal

Reconfirm the Phase 1 `Kernel` Google Workspace readonly path against real
operator data and ensure the adapter returns bounded evidence summaries for
`meeting-prep` and `standup-report` during `preflight enrich`.

### Must not

- Must not introduce unattended write behavior
- Must not reinject raw Workspace payloads into `Kernel` prompts
- Must not make mailbox-dependent flows a blocker for this issue
- Must not expand scope into `tasks`, `pubsub`, or `presentations` for this
  issue

### Acceptance criteria

- `meeting-prep` is revalidated end to end
- `standup-report` is revalidated end to end
- returned evidence remains summary-only and bounded
- missing credentials or partial auth degrade safely instead of blocking the
  whole run
- relevant docs or tests are updated if the actual behavior differs from the
  current design docs

### Notes

This is the highest-value and lowest-friction resume point from the recovered
March local OAuth setup.

## Draft 2

### Suggested title

`task: add mailbox readonly evidence to kernel workspace lane`

### Goal

Add mailbox-derived readonly evidence to the `Kernel` Workspace lane only after
the Phase 1 preflight path is stable, using `weekly-digest` and
`gmail-triage`.

### Must not

- Must not redefine the Phase 1 `preflight enrich` contract
- Must not require mailbox access for the core readonly milestone
- Must not reinject raw Gmail payloads into `Kernel` prompts

### Acceptance criteria

- `weekly-digest` is revalidated end to end
- `gmail-triage` is revalidated end to end
- mailbox-derived evidence remains summary-only and bounded
- docs clearly distinguish service-account readonly from user OAuth readonly

### Notes

This issue is Phase 2. It should start only after `meeting-prep` and
`standup-report` are stable as bounded preflight evidence.

## Draft 3

### Suggested title

`task: normalize kernel google workspace bounded write receipts`

### Goal

Reconfirm the bounded write helper path for Google Workspace and define a
consistent receipt shape for operator-approved side effects such as
`gmail-send --dry-run`, `docs-create`, `docs-insert-text`, `sheets-append`,
and `drive-upload`.

### Must not

- Must not enable unattended real side effects in the default loop
- Must not treat Google Workspace as task-state authority
- Must not broaden auth requirements beyond the core write helper set

### Acceptance criteria

- `gmail-send --dry-run` preview path is revalidated
- Docs write helper flow is revalidated
- Sheets append flow is revalidated
- Drive upload flow is revalidated
- a documented Workspace write receipt shape exists for `Kernel` evidence
- docs and/or tests cover the receipt expectations

### Notes

This issue should stay focused on evidence, receipts, and bounded side effects,
not on new Workspace product features.

## Draft 4

### Suggested title

`task: minimize kernel google workspace auth by function`

### Goal

Replace the broad discovery-oriented local OAuth grant with explicit
function-scoped auth profiles for the mature `Kernel` Google Workspace lane.

### Must not

- Must not keep `gws auth login --full` as the documented steady-state path
- Must not break the readonly operator flows while minimizing scopes
- Must not mix extension scopes into the default mature profile unless they are
  strictly required

### Acceptance criteria

- minimum readonly operator auth profile is documented
- minimum bounded-write operator auth profile is documented
- setup guidance clearly distinguishes readonly, bounded-write, and extension
  lanes
- recovered March auth context is documented as discovery history, not policy

### Notes

This issue converts the recovered local setup from tribal knowledge into a
repeatable least-privilege `Kernel` path.

## Draft 5

### Suggested title

`task: triage kernel google workspace extension lanes tasks pubsub slides`

### Goal

Split Google Workspace extension work away from the core `Kernel` lane and
document whether `tasks`, `pubsub`, and `presentations` each have a concrete
product reason, auth requirement, and implementation path.

### Must not

- Must not block the mature readonly lane on extension discovery
- Must not assume that all extension scopes belong in the default operator auth
- Must not conflate FUGUE-era discovery with production `Kernel` requirements

### Acceptance criteria

- `tasks` extension lane has a clear keep / defer / drop decision
- `pubsub` extension lane has a clear keep / defer / drop decision
- `presentations` extension lane has a clear keep / defer / drop decision
- each extension lane has explicit auth and validation requirements if kept
- the core lane docs are not polluted by speculative extension scope

### Notes

This is intentionally the fourth issue, not the first. It should start only
after the core readonly and bounded-write lanes are back in a stable shape.
