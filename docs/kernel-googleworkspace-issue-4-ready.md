# Kernel Google Workspace Issue 4 Ready

## Suggested Title

`task: minimize kernel google workspace auth by function`

## Suggested Template Settings

Use this with the `FUGUE Task (Mobile / Natural Language)` issue template.

- `Mainframe handoff`: `auto`
- `Execution mode`: `implement`
- `Implementation confirmation`: `confirmed`
- `Main orchestrator provider`: `codex`
- `Assist orchestrator provider`: `claude`
- `Multi-agent mode`: `auto`
- `Target repo`: `cursorvers/fugue-orchestrator`

## Paste-Ready Body

```md
## Goal
Recovered March local OAuth setup を discovery history として整理し直し、Kernel Google Workspace lane を function-scoped auth に最小化したい。

今回のゴールは、`gws auth login --full` のような broad discovery login を steady-state policy にしないこと。

分けたい auth shape:
- readonly core profile
- mailbox readonly profile
- bounded write profile
- extension-only profile

必要条件:
- mature core lane を最小権限で再現できる
- broad discovery auth は historical context として残すが、推奨運用にしない
- docs / bootstrap / issue flow が新しい auth 方針と整合する

参照:
- `docs/kernel-googleworkspace-integration-design.md`
- `docs/kernel-googleworkspace-resume-plan-2026-03-20.md`
- `docs/kernel-googleworkspace-implementation-todo.md`
- `docs/kernel-googleworkspace-issue-drafts-2026-03-20.md`

## Must not
- `gws auth login --full` を mature path の標準にしない
- core readonly flows を壊さない
- extension scopes を default auth に混ぜない
- repo `.env` を auth truth にしない

## Acceptance criteria
- minimum readonly operator auth profile が documented される
- mailbox readonly auth profile が documented される
- bounded write auth profile が documented される
- extension-only scopes が明確に分離される
- recovered March auth context が discovery history として位置づけ直される

## Notes
この issue は behavior というより auth / docs / operating policy の正規化が中心。
```

## Recommended Bootstrap Command

Issue number allocated after creation:

```bash
bash scripts/local/bootstrap-kernel-googleworkspace-artifacts.sh \
  --issue-number <N> \
  --track scope-minimization
```

## After Issue Creation

1. create the issue with the title above
2. paste the body above
3. use the suggested template settings
4. run the bootstrap command with the created issue number
5. start execution from the generated `.fugue/pre-implement/issue-<N>-todo.md`
