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
  - Push優先: `LINE_NOTIFY_PREFER_PUSH=true|false`（default false）
  - inbound webhook許可: `LINE_NOTIFY_ALLOW_INBOUND_WEBHOOK=true|false`（default false）
  - 重複抑止TTL: `LINE_NOTIFY_DEDUP_TTL_SECONDS`（default 21600）
  - 失敗クールダウン: `LINE_NOTIFY_FAILURE_COOLDOWN_SECONDS`（default 3600）
  - 再試行回数: `LINE_NOTIFY_RETRY_MAX_ATTEMPTS`（default 3, timeout/5xxのみ）
  - 再試行初期待機: `LINE_NOTIFY_RETRY_BASE_SECONDS`（default 1）
  - 再試行最大待機: `LINE_NOTIFY_RETRY_MAX_BACKOFF_SECONDS`（default 8）
  - 任意本文: `LINE_NOTIFY_MESSAGE`
  - 相関ID上書き: `LINE_NOTIFY_TRACE_ID`（未指定時は自動生成）

`line-notify` は同一メッセージの連打を抑止し、直近失敗の再試行をクールダウンします。  
送信処理は timeout/5xx の一時障害時のみ指数バックオフで再試行します。  
`line-notify.meta` には `status` に加えて `trace_id` / `message_hash` / `run_url` / `transport_selection` / `retry_count` が記録され、webhook中継先ログとの突合せや経路診断に使えます。

## Integration with orchestration

`scripts/local/run-local-orchestration.sh` から以下オプションで接続できます。

- `--with-linked-systems`
- `--linked-mode smoke|execute`
- `--linked-systems all|<id,id,...>`
- `--linked-max-parallel <n>`

`--linked-mode execute` は `ok_to_execute=true` の場合のみ実行され、未承認時は自動でスキップされます。
