# MBP to Mac mini tmux Operations Manual

## Goal

`MBP` から `mac mini` に入り、`tmux` session を分けて並列開発するための実運用マニュアル。  
この文書は日常運用向けで、まず `ssh mini` と `tmux` の最短導線を確実に回すことを目的にする。

## Preconditions

- `MBP` の `~/.ssh/config` に `Host mini` が設定されている
- `ssh mini` が成功する
- `mac mini` 側の shell で `ts` と `tn` が使える

前提コマンド:

```bash
ssh mini
type ts
type tn
```

## Core Commands

`MBP` から使う最小コマンドはこれだけ。

```bash
ssh mini
```

`mac mini` に入った後はこれだけ覚えればよい。

```bash
ts
tn <purpose>
tmux ls
```

意味:

- `ts`
  - 既存 session の chooser を開いて attach する
- `tn <purpose>`
  - `fugue-<purpose>` という名前で新しい session を作り、そこへ移る
- `tmux ls`
  - session 一覧を確認する

## Daily Workflow

### 1. 既存作業を再開する

```bash
ssh mini
ts
```

chooser から入りたい session を選ぶ。  
session 名が分かっているなら直接でもよい。

```bash
tmux attach -t fugue-api-fix
```

### 2. 新しい並列作業を始める

```bash
ssh mini
tn api-fix
```

すると `fugue-api-fix` が作られ、その session に移る。

session 内で必要に応じて起動する:

```bash
kernel
```

または

```bash
fugue
```

### 3. session から抜ける

`Ctrl+b` の後に `d` を押して detach する。

## Session Naming Rule

- `1 workstream = 1 tmux session`
- session 名は `fugue-<purpose>`
- read-only sidecar が必要なら `fugue-<purpose>-view`
- 同じ session に別案件を混ぜない
- `purpose` が変わったら新しい session を切る

例:

- `fugue-api-fix`
- `fugue-billing`
- `fugue-lp-redesign`
- `fugue-ios-login`
- `fugue-api-fix-view`

## Recommended Patterns

### 開発者が 1 本の作業を進める

```bash
ssh mini
tn billing
```

### 既存作業を見直して再開する

```bash
ssh mini
ts
```

### 進行中 session をざっと見る

```bash
ssh mini
tmux ls
```

## When To Use Kernel or FUGUE

- `Kernel`
  - run continuation
  - tmux/session-centric な開発継続
  - compact / recover / doctor を使う流れ
- `FUGUE`
  - legacy orchestration
  - session 内で直接使いたい既存運用

重要なのは、どちらを使うかより先に `session を分ける` こと。

## Recovery

### session がまだある

```bash
ssh mini
ts
```

または:

```bash
ssh mini
tmux attach -t <session>
```

### session が消えているが Kernel run を戻したい

repo root に移動して:

```bash
codex-kernel-guard doctor --all-runs
codex-kernel-guard doctor --run <run_id>
codex-kernel-guard recover-run <run_id>
```

その後に attach:

```bash
tmux attach -t <session>
```

## Troubleshooting

### `ssh mini` が通らない

まず確認:

```bash
ssh mini 'hostname -s'
```

### `ts` / `tn` が無い

```bash
type ts
type tn
source ~/.zshrc
```

### tmux 一覧だけ見たい

```bash
tmux ls
```

### chooser を使わず直接入りたい

```bash
tmux attach -t fugue-api-fix
```

## Do Not

- `mm` を使わない
- `MBP` 側の `~/.zshrc` に長い wrapper を増やさない
- 1 session に複数案件を混ぜない
- wrapper から作り始めない

## References

- [local-codex-handoff-2026-03-21.md](/Users/masayuki_otawara/fugue-orchestrator/docs/local-codex-handoff-2026-03-21.md)
- [dr-continuation-runbook-v1.md](/Users/masayuki_otawara/fugue-orchestrator/docs/kernel/dr-continuation-runbook-v1.md)
