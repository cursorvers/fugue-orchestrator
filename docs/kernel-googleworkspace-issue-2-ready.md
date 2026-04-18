# Kernel Google Workspace Issue 2 Ready

## Suggested Title

`task: add mailbox readonly evidence to kernel workspace lane`

## Suggested Template Settings

Use this with the `FUGUE Task (Mobile / Natural Language)` issue template.

- `Mainframe handoff`: `auto`
- `Execution mode`: `implement`
- `Implementation confirmation`: `pending`
- `Main orchestrator provider`: `codex`
- `Assist orchestrator provider`: `claude`
- `Multi-agent mode`: `auto`
- `Target repo`: `cursorvers/fugue-orchestrator`

## Paste-Ready Body

```md
## Goal
Kernel の Google Workspace lane の Phase 2 として、mailbox-derived readonly evidence を追加したい。

今回のゴールは、Phase 1 で安定化した `preflight enrich` 契約を崩さずに、
`weekly-digest` と `gmail-triage` を user OAuth readonly 境界で追加すること。

必要条件:
- Phase 1 の `meeting-prep` / `standup-report` 契約を壊さない
- Gmail の raw payload を prompt に再注入しない
- summary-only の bounded evidence envelope に限定する
- service-account readonly と user OAuth readonly の違いを docs / runtime で明確にする

背景:
- recovered March auth context は broad discovery login だった可能性が高い
- mailbox-derived flows は価値が高いが、Phase 1 の blocker にすると詰まりやすい
- そのため `weekly-digest` / `gmail-triage` は Phase 2 として分離したい

参照:
- `docs/kernel-googleworkspace-integration-design.md`
- `docs/kernel-googleworkspace-resume-plan-2026-03-20.md`
- `docs/kernel-googleworkspace-implementation-todo.md`
- `docs/kernel-googleworkspace-issue-drafts-2026-03-20.md`

## Must not
- Phase 1 の `preflight enrich` contract を作り替えない
- mailbox access を core readonly milestone の必須条件にしない
- Gmail raw payload を main prompt に戻さない
- unattended write をこの issue に混ぜない
- `tasks` / `pubsub` / `presentations` を scope に入れない

## Acceptance criteria
- `weekly-digest` が readonly evidence として再検証される
- `gmail-triage` が readonly evidence として再検証される
- mailbox-derived evidence は summary-only / bounded envelope として扱われる
- docs に service-account readonly と user OAuth readonly の違いが明記される
- Phase 1 path を変えずに Phase 2 を追加できる

## Notes
この issue は Phase 2 専用。

Phase 1 の前提:
- `meeting-prep`
- `standup-report`

この issue の後続:
- bounded write receipts
- auth by function
- extension lane triage
```

## Recommended Bootstrap Command

Issue number allocated after creation:

```bash
bash scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh \
  --issue-number <N> \
  --track mailbox-readonly
```

## After Issue Creation

1. create the issue with the title above
2. paste the body above
3. use the suggested template settings
4. run the bootstrap command with the created issue number
5. start execution from the generated `.fugue/pre-implement/issue-<N>-todo.md`
