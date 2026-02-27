# Local Linked Systems

FUGUEのローカル実行に、以下の外部システムを連結するための実装です。

- auto-video (Remotion)
- note-semi-auto
- obsidian-audio-ai
- discord-notify
- line-notify

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
- `scripts/local/integrations/discord-notify.sh`
- `scripts/local/integrations/line-notify.sh`

各アダプタは共通で `--mode smoke|execute` を受け取り、`smoke` は疎通確認、`execute` は最小実行を行います。

通知アダプタの主な環境変数:

- Discord: `DISCORD_NOTIFY_WEBHOOK_URL`（fallback: `DISCORD_WEBHOOK_URL`, `DISCORD_SYSTEM_WEBHOOK`）
- LINE:
  - Webhookモード: `LINE_WEBHOOK_URL`
  - Pushモード: `LINE_CHANNEL_ACCESS_TOKEN` + `LINE_TO`（optional: `LINE_PUSH_API_URL`）
  - Legacy Notifyモード: `LINE_NOTIFY_TOKEN`（alias: `LINE_NOTIFY_ACCESS_TOKEN`, optional: `LINE_NOTIFY_API_URL`）
  - ガードレール: `LINE_NOTIFY_GUARD_ENABLED=true|false`（default true）
  - ガード状態ファイル: `LINE_NOTIFY_GUARD_FILE`（default: `.fugue/state/line-notify-guard.json`）
  - 重複抑止TTL: `LINE_NOTIFY_DEDUP_TTL_SECONDS`（default 21600）
  - 失敗クールダウン: `LINE_NOTIFY_FAILURE_COOLDOWN_SECONDS`（default 3600）
  - 任意本文: `LINE_NOTIFY_MESSAGE`

`line-notify` は同一メッセージの連打を抑止し、直近失敗の再試行をクールダウンします。  
`line-notify.meta` の `status` には `suppressed-duplicate` / `suppressed-recent-failure` / `error` が記録されます。

## Integration with orchestration

`scripts/local/run-local-orchestration.sh` から以下オプションで接続できます。

- `--with-linked-systems`
- `--linked-mode smoke|execute`
- `--linked-systems all|<id,id,...>`
- `--linked-max-parallel <n>`

`--linked-mode execute` は `ok_to_execute=true` の場合のみ実行され、未承認時は自動でスキップされます。
