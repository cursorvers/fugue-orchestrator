# Kernel Google Workspace Issue 3 Ready

## Suggested Title

`task: normalize kernel google workspace bounded write receipts`

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
Kernel の Google Workspace bounded write lane を再確認し、operator-approved side effects に対する receipt 形を正規化したい。

今回のゴールは新しい Workspace 機能を増やすことではなく、既存の write helper 候補を `Kernel` の evidence / receipt 契約に落とし込むこと。

対象候補:
- `gmail-send --dry-run`
- `docs-create`
- `docs-insert-text`
- `sheets-append`
- `drive-upload`

必要条件:
- default loop に unattended write を入れない
- approval gate を前提にする
- artifact ids / receipts / preview evidence を一貫した形にする

参照:
- `docs/kernel-googleworkspace-integration-design.md`
- `docs/kernel-googleworkspace-resume-plan-2026-03-20.md`
- `docs/kernel-googleworkspace-implementation-todo.md`
- `docs/kernel-googleworkspace-issue-drafts-2026-03-20.md`

## Must not
- real side effects を default loop に入れない
- Google Workspace を task-state authority にしない
- raw response をそのまま success evidence にしない
- `tasks` / `pubsub` / `presentations` の extension scope を混ぜない

## Acceptance criteria
- `gmail-send --dry-run` preview path が再検証される
- Docs write helper path が再検証される
- Sheets append path が再検証される
- Drive upload path が再検証される
- Workspace write receipt shape が docs か code 上で定義される
- approval / preview / applied artifact の関係が明確になる

## Notes
この issue は readonly lane の後続であり、write の本番運用化ではなく receipt 正規化が主目的。
```

## Recommended Bootstrap Command

Issue number allocated after creation:

```bash
bash scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh \
  --issue-number <N> \
  --track bounded-write
```

## After Issue Creation

1. create the issue with the title above
2. paste the body above
3. use the suggested template settings
4. run the bootstrap command with the created issue number
5. start execution from the generated `.fugue/pre-implement/issue-<N>-todo.md`
