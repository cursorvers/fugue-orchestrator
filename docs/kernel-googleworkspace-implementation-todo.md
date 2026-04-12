# Kernel Google Workspace Implementation TODO

## Goal

Resume the `Kernel` Google Workspace lane from the recovered March local OAuth
state, but narrow Phase 1 to one concrete objective:

- make `meeting-prep` and `standup-report` reliable readonly evidence sources
  for `Kernel` `preflight enrich`

Primary source documents:

- `docs/kernel-googleworkspace-integration-design.md`
- `docs/kernel-googleworkspace-resume-plan-2026-03-20.md`
- `docs/kernel-googleworkspace-issue-drafts-2026-03-20.md`

Bootstrap helper:

- `scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh`
- `scripts/local/bootstrap-kernel-googleworkspace-workset.sh`

## Plan

1. re-verify `meeting-prep` and `standup-report` as bounded preflight evidence
2. add mailbox-derived readonly flows only after Phase 1 is stable
3. re-verify bounded write previews and receipts after readonly stabilization
4. replace broad discovery auth with function-scoped auth profiles
5. keep extension lanes separate from the default `Kernel` Workspace path

## Checklist

- [x] Reconfirm readonly command surface still matches the design doc
- [x] Run local validation for `meeting-prep`
- [x] Run local validation for `standup-report`
- [x] Confirm preflight reinjection stays summary-only and bounded
- [x] Confirm missing-credentials behavior degrades to `skipped` or `partial`
- [x] Confirm service-account readonly path still provides useful Phase 1 value
- [x] Defer `weekly-digest` and `gmail-triage` until Phase 1 readonly evidence is stable
- [x] Confirm scheduled feed sync still maps cleanly into `Kernel` context
- [x] Reconfirm `gmail-send --dry-run` preview path
- [x] Reconfirm `docs-create` and `docs-insert-text` bounded write path
- [x] Reconfirm `sheets-append` bounded write path
- [x] Reconfirm `drive-upload` bounded write path
- [x] Define receipt fields required for Workspace write evidence
- [x] Document minimum readonly operator auth profile
- [x] Document mailbox readonly operator auth profile
- [x] Document minimum bounded-write operator auth profile
- [x] Remove dependence on `gws auth login --full` for the core lane
- [x] Split extension work into separate follow-up tracks for `tasks`, `pubsub`, and `presentations`

## Progress

Current recovered state:

- design and adapter placement already exist
- readonly preflight and feed sync work landed on `2026-03-07`
- local `gws` OAuth setup was performed on `2026-03-18`
- the recovered local auth appears to have used a broad `--full` scope set
- the first practical `Kernel` milestone should be narrower than that recovered
  scope set:
  - `meeting-prep`
  - `standup-report`
- Phase 1 readonly path has now been revalidated through local-safe prepare,
  offline simulation, bounded preflight tests, and feed-sync tests
- Phase 2 mailbox readonly path has been revalidated separately so it no longer
  obscures the Phase 1 core milestone
- Live operator validation now also reports `status: ok` for both
  `.fugue/kernel-googleworkspace-workset/phase1-run/phase1-report.md` and
  `.fugue/kernel-googleworkspace-workset/phase2-mailbox-run/phase2-mailbox-report.md`
- bounded write receipt metadata and extension-lane policy are now covered by
  machine-readable policy checks

No material unstarted task remains inside the current five-issue local
validation split.

Future work only if scope expands:

- live operator reruns against real Google Workspace credentials
- new extension implementation after a concrete product reason is approved

Recently normalized:

- function-scoped auth minimization for the mature lane is now documented as a
  four-way split:
  - shared/service-account readonly baseline
  - core readonly operator profile
  - mailbox readonly operator profile
  - bounded-write operator profile
- write receipt fields are now normalized in both the adapter output contract
  and the machine-readable Kernel policy
- extension lane decisions for `tasks`, `pubsub`, and `presentations` are now
  explicit so they cannot silently leak into the mature core lane
- Phase 2 mailbox readonly behavior has been revalidated in focused tests for
  `weekly-digest`, `gmail-triage`, and bounded feed reinjection
- bounded write helpers now emit an explicit `write_disposition` in
  `*-meta.json` so preview / applied / blocked state is machine-readable
- default core phases are now machine-checked to exclude extension actions and
  the `extension-only` auth profile

## Review

Key risks:

1. broad local auth may hide the true minimum scope requirements
2. mailbox-dependent readonly flows may block the first milestone unnecessarily
3. extension capabilities may distract from the production-value readonly path
4. write helpers may exist without a fully normalized `Kernel` evidence receipt
5. local operator success may drift from CI readonly behavior if auth boundaries
   are not documented tightly

Key rules:

- keep Workspace in the adapter plane only
- treat readonly evidence as the first production target
- require bounded summaries, not raw payload reinjection
- require explicit approval for real side effects
- add extension scopes only when their lane is actively under validation

## Suggested Issue Split

### Issue 1: Readonly Evidence Revalidation

Scope:

- `meeting-prep`
- `standup-report`
- bounded reinjection review
- degraded `skipped` / `partial` behavior review

Done when:

- `Kernel` can consume readonly Workspace evidence through summaries only

Out of scope for this issue:

- `weekly-digest`
- `gmail-triage`

### Issue 2: Mailbox Readonly Extension

Scope:

- `weekly-digest`
- `gmail-triage`
- user OAuth readonly behavior

Done when:

- mailbox-derived readonly evidence can enrich `Kernel` without changing the
  Phase 1 preflight contract

### Issue 3: Bounded Write Receipt Path

Scope:

- `gmail-send --dry-run`
- `docs-create`
- `docs-insert-text`
- `sheets-append`
- `drive-upload`
- Workspace write receipt schema

Done when:

- all approved write helpers can emit consistent artifact ids and receipts

### Issue 4: Scope Minimization

Scope:

- minimum readonly auth profile
- mailbox readonly auth profile
- minimum bounded-write auth profile
- operator setup documentation

Done when:

- core `Kernel` Workspace validation no longer depends on broad `--full` auth

### Issue 5: Extension Lane Triage

Scope:

- `tasks`
- `pubsub`
- `presentations`

Done when:

- each extension has an explicit product reason, auth requirement, and no
  coupling to the core readonly path

## Next Command Targets

Core readonly lane:

```bash
gws workflow +meeting-prep
gws workflow +standup-report
```

Mailbox readonly lane:

```bash
gws workflow +weekly-digest
gws gmail +triage --max 10
```

Bounded write lane:

```bash
gws gmail +send --dry-run --to you@example.com --subject test --body test
```

Recommended mature core readonly auth shape:

```bash
gws auth login --readonly -s calendar,drive
```

Recommended mailbox readonly auth shape:

```bash
gws auth login --readonly -s calendar,gmail,drive
```

Recommended mature bounded-write auth shape:

```bash
gws auth login -s calendar,gmail,drive,docs,sheets
```
