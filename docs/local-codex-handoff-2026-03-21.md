# Local Codex Handoff 2026-03-21

## Goal

`MBP -> mac mini` の遠隔開発を `Tailscale/SSH + tmux` で成立させる。  
Kernel/FUGUE の launcher 短縮は後回しにし、まずは確実に session を分けて並列開発できることを優先する。

日常運用の手順は [mbp-macmini-tmux-operations-manual.md](/Users/masayuki_otawara/fugue-orchestrator/docs/mbp-macmini-tmux-operations-manual.md) を参照。

## Current Best Path

最短導線は wrapper を作ることではなく、まず生の `ssh` と `tmux` で入ること。

```bash
ssh masayuki@mac-mini-m1-for-otawara-m.tail82068c.ts.net
tmux ls
tmux attach -t <session>
tmux new -s <new-session>
```

session の中で必要に応じて:

```bash
kernel
```

または

```bash
fugue
```

## Session Policy

- `1 workstream = 1 tmux session`
- session 名は短い task slug にする
- 同じ session に別案件を混ぜない
- `purpose` が変わったら新しい session を切る

例:

- `api-fix`
- `billing`
- `lp-redesign`
- `ios-login`

## What Was Already Implemented

repo 側の runtime/launcher はここまで入っている。

- `k` / `kn` の remote path
- `k new --runtime kernel|fugue`
- `recover-run` / `session-adopt` の runtime-aware 化
- remote host authenticity check
- `session_fingerprint` による run/session ownership check

関連ファイル:

- [k](/Users/masayuki_otawara/bin/k)
- [kn](/Users/masayuki_otawara/bin/kn)
- [kernel-runtime-launch.sh](/Users/masayuki_otawara/fugue-orchestrator/scripts/lib/kernel-runtime-launch.sh)
- [kernel-run-recovery.sh](/Users/masayuki_otawara/fugue-orchestrator/scripts/lib/kernel-run-recovery.sh)
- [kernel-session-adopt.sh](/Users/masayuki_otawara/fugue-orchestrator/scripts/lib/kernel-session-adopt.sh)
- [kernel-compact-artifact.sh](/Users/masayuki_otawara/fugue-orchestrator/scripts/lib/kernel-compact-artifact.sh)

## What Failed

`MBP` 側ショートカット導入は未完了。

原因:

- こちらで編集した `~/.zshrc` は `/Users/masayuki_otawara/.zshrc` で、実ユーザーの MBP は `/Users/masayuki/.zshrc`
- `mm` は既存 alias `ssh mini` と衝突
- 長い heredoc を端末に貼ったため、FQDN が改行で壊れた
- その結果、MBP の `~/.zshrc` に壊れた追記が一時入ったが、ユーザーが `sed -i '' '860,$d' ~/.zshrc` で cleanup 済み

## Recommendation For Next Codex Session

1. まず MBP 実機で生の接続を通す

```bash
ssh masayuki@mac-mini-m1-for-otawara-m.tail82068c.ts.net 'hostname -s'
ssh masayuki@mac-mini-m1-for-otawara-m.tail82068c.ts.net 'tmux ls'
```

2. 通ったら、shortcuts は `mm` ではなく別名で最小化する  
   例: `mini`, `msh`, `matt`

3. shell function ではなく alias 1 行から始める方が安全

```bash
alias mini='ssh masayuki@mac-mini-m1-for-otawara-m.tail82068c.ts.net'
```

4. その後に必要なら `mk` 相当の wrapper を追加する

## Immediate Operator Guidance

今すぐ開発を続けるだけなら、wrapper は不要。

```bash
ssh masayuki@mac-mini-m1-for-otawara-m.tail82068c.ts.net
tmux ls
tmux attach -t <session>
```

新規並列作業:

```bash
tmux new -s <new-session>
```

その session 内で `kernel` または `fugue` を起動する。
