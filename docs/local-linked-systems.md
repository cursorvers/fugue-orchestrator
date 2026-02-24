# Local Linked Systems

FUGUEのローカル実行に、以下の外部システムを連結するための実装です。

- auto-video (Remotion)
- note-semi-auto
- obsidian-audio-ai

## Source of truth

- `config/integrations/local-systems.json`

## Runner

- `scripts/local/run-linked-systems.sh`

並列実行で各アダプタを起動し、結果を `.fugue/local-run/linked-issue-...` に保存します。

## Integrity Check

- `scripts/check-linked-systems-integrity.sh`

マニフェストの重複ID・形式・有効アダプタ存在/実行権限/bash構文を検証します。

## Adapters

- `scripts/local/integrations/auto-video.sh`
- `scripts/local/integrations/note-semi-auto.sh`
- `scripts/local/integrations/obsidian-audio-ai.sh`

各アダプタは共通で `--mode smoke|execute` を受け取り、`smoke` は疎通確認、`execute` は最小実行を行います。

## Integration with orchestration

`scripts/local/run-local-orchestration.sh` から以下オプションで接続できます。

- `--with-linked-systems`
- `--linked-mode smoke|execute`
- `--linked-systems all|<id,id,...>`
- `--linked-max-parallel <n>`

`--linked-mode execute` は `ok_to_execute=true` の場合のみ実行され、未承認時は自動でスキップされます。
