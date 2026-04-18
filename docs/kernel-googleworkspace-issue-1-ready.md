# Kernel Google Workspace Issue 1 Ready

## Suggested Title

`task: revalidate kernel google workspace readonly evidence lane`

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
Kernel の Google Workspace lane を Phase 1 として再開したい。

今回のゴールは広い Workspace 連携全体ではなく、`preflight enrich` で
`meeting-prep` と `standup-report` を readonly の bounded evidence として
安定供給できるようにすること。

必要条件:
- Google Workspace は control-plane truth にしない
- raw payload は prompt に再注入しない
- summary-only の evidence envelope に限定する
- credentials や API 制限が足りない場合でも `skipped` / `partial` で安全に継続する

背景:
- `2026-03-07` に Google Workspace preflight / feed sync 系の実装が入っている
- `2026-03-18` に `~/.config/gws/` のローカル OAuth が作られていて、当時の broad auth は開発用 discovery login だった可能性が高い
- まずは最小価値の高い Phase 1 として `meeting-prep` / `standup-report` に絞りたい

参照:
- `docs/kernel-googleworkspace-integration-design.md`
- `docs/kernel-googleworkspace-resume-plan-2026-03-20.md`
- `docs/kernel-googleworkspace-implementation-todo.md`
- `docs/kernel-googleworkspace-issue-drafts-2026-03-20.md`

## Must not
- unattended write を default loop に入れない
- Gmail mailbox 依存の `weekly-digest` / `gmail-triage` を今回の blocker にしない
- `tasks` / `pubsub` / `presentations` の extension lane を今回の scope に入れない
- Google Workspace を task state や orchestration truth にしない
- raw Workspace payload を main prompt に戻さない

## Acceptance criteria
- `meeting-prep` が readonly evidence として再検証される
- `standup-report` が readonly evidence として再検証される
- evidence は summary-only / bounded envelope として扱われる
- credentials 不足や API 制限時に `skipped` / `partial` で安全に degrade する
- relevant docs / tests / scripts が実際の挙動に合わせて更新される
- mailbox readonly flow は out-of-scope と明記される

## Notes
この issue は Phase 1 専用。

Phase 2 以降で扱うもの:
- `weekly-digest`
- `gmail-triage`
- bounded write receipts
- auth by function
- extension lane triage
```

## Recommended Bootstrap Command

Issue number allocated after creation:

```bash
bash scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh \
  --issue-number <N> \
  --track readonly-evidence
```

## After Issue Creation

1. create the issue with the title above
2. paste the body above
3. use the suggested template settings
4. run the bootstrap command with the created issue number
5. start execution from the generated `.fugue/pre-implement/issue-<N>-todo.md`
