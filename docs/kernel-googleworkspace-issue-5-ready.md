# Kernel Google Workspace Issue 5 Ready

## Suggested Title

`task: triage kernel google workspace extension lanes tasks pubsub slides`

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
Kernel Google Workspace lane の extension work を core lane から切り離し、`tasks`、`pubsub`、`presentations` の扱いを keep / defer / drop で整理したい。

今回のゴールは extension を全部実装することではなく、各 extension lane に product reason・auth requirement・validation path があるかを判定すること。

対象:
- `tasks`
- `pubsub`
- `presentations`

必要条件:
- core readonly lane を block しない
- broad discovery auth の残骸を default policy にしない
- FUGUE 時代の実験と Kernel の production requirement を分離する

参照:
- `docs/kernel-googleworkspace-integration-design.md`
- `docs/kernel-googleworkspace-resume-plan-2026-03-20.md`
- `docs/kernel-googleworkspace-implementation-todo.md`
- `docs/kernel-googleworkspace-issue-drafts-2026-03-20.md`

## Must not
- core readonly lane を extension discovery に引きずられない
- extension scope を default auth profile に混ぜない
- `tasks` / `pubsub` / `presentations` を product reason なしに keep 扱いしない
- write lane や mailbox readonly lane と論点を混ぜない

## Acceptance criteria
- `tasks` に keep / defer / drop の判断がつく
- `pubsub` に keep / defer / drop の判断がつく
- `presentations` に keep / defer / drop の判断がつく
- keep されるものは auth / validation / product reason が documented される
- core lane docs から speculative extension dependency が外れる

## Notes
この issue は最後に回す。Goal は実装量を増やすことではなく、Kernel scope を守ること。
```

## Recommended Bootstrap Command

Issue number allocated after creation:

```bash
bash scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh \
  --issue-number <N> \
  --track extension-triage
```

## After Issue Creation

1. create the issue with the title above
2. paste the body above
3. use the suggested template settings
4. run the bootstrap command with the created issue number
5. start execution from the generated `.fugue/pre-implement/issue-<N>-todo.md`
