# Kernel Mobile Content Workflow

This runbook defines how to submit and monitor content-oriented tasks from a
smartphone while keeping `Kernel` as the default sovereign path and the legacy
Claude-side path available as the rollback path.

## Goal

Support mobile-first requests such as:

- create a company deck
- create an academic slide deck
- draft a note.com manuscript

without requiring a laptop in the moment the idea appears.

## Entry Surface

The current production-safe mobile entry surface is:

- GitHub Mobile issue creation
- GitHub Mobile issue comments

Repository:

- `cursorvers/fugue-orchestrator`

## Recommended Issue Pattern

Title examples:

- `会社紹介スライドを作って`
- `学会発表スライドの草案を作って`
- `このテーマで note 記事の原稿を書いて`

Body template:

```md
## Goal
営業向けの会社紹介スライドを作りたい

## Deliverable
- 10-15 pages
- share none
- Japanese

## Constraints
- mobile-first input
- first draft is enough
- later review on MBP
```

## Automatic Intent Detection

`Kernel` extracts content intent from natural language and adds routing labels.

Detected labels:

- `content-task`
- `content:slide`
- `content:academic-slide`
- `content:note`
- `content-action:slide-deck`
- `content-action:academic-slide`
- `content-action:note-manuscript`

These labels are informative and mobile-friendly. They do not replace the
shared `fugue-task` / `tutti` routing labels.

## Skill Mapping

Natural-language intent maps to the following skills:

- `slide-deck` -> `slide`
- `academic-slide` -> `academic-two-stage-slide`
- `note-manuscript` -> `note-manuscript`

This does not force immediate automatic execution of specialist workflows.
Instead, it preserves intent through the orchestration path so the local
primary host or operator workstation can pick the correct specialist path.

## Progress Monitoring

Use these mobile surfaces:

- `fugue-status` issue thread (`#55`) for periodic snapshots
- issue labels for immediate task-type visibility
- workflow runs:
  - `fugue-task-router`
  - `fugue-tutti-caller`
  - `kernel-recovery-console`
  - `kernel-mobile-progress`

## Recovery

If the local primary is unavailable:

1. Open `Actions`
2. Run `kernel-recovery-console`
3. Choose one of:
   - `mobile-progress`
   - `continuity-canary`
   - `rollback-canary`
   - `reroute-issue`

This preserves the same mobile entry flow even when the sovereign execution
path changes from `Kernel` to `fugue-bridge`.
