# Kernel Handover — 2026-03-23 Session 2 (from FUGUE)

## 完了作業 (FUGUE側)

### gws OAuth scope昇格 + 暗号化修復
- 全11スコープをreadonly→full accessに昇格（手動token交換）
- AES-256-GCM再暗号化: ring 0.17.14互換 (nonce(12)+ct+tag(16))
- `gws auth status`: encryption_valid=true, token_valid=true
- Tasks write E2E テスト通過 (insert/delete)

### gws-auth-refresh ヘルパースクリプト
- `~/.local/bin/gws-auth-refresh` (Node.js 752行, npm依存なし)
- localhost コールバック問題の恒久対策
- Codex exec で実装済み、dry-run テスト通過
- デフォルト: 最小権限スコープ (tasks=write, 他=readonly)

### 47ファイル未コミット → 3コミット (auto-push済み)
```
3cd02689 feat(kernel): add auth-evidence and consensus-evidence modules
212079ae fix(kernel): improve phase gate, specialist picker, and test coverage
d0b05ce5 chore: update kernel state, prompts, CI gate, and business-digest v2 spec
```

### business-digest v2 統合確認
- 9/9要件実装済み、compact 1行フォーマット稼働中
- Kernel側の追加作業不要

### Chrome DevTools MCP 1週間運用評価
- Rule A維持（エスカレーション発生0件、サンプル不足）
- 3/30にGo/No-Go再評価

## ユーザー操作待ちタスク (Kernel引き継ぎ不要)
- P0: OAuth consent screen → Published化 (GCP Console, 期限3/30)
- P1: P0完了後 `gws-auth-refresh` でスコープ縮小

## Gotchas
- gws CLIは credentials.enc を credentials.json より優先 (storage: "encrypted")
- ring 0.17.14 AES-256-GCM: nonce(12) + ciphertext + tag(16) バイト配列
- gws auth login は Claude Code 内でプロセスタイムアウト死する → gws-auth-refresh で回避
- Google OAuth installed app は http://localhost でポート自由（Google仕様）
- Codex は formatOutput のような表示ロジックを独自判断で変更する傾向あり → specに「既存ロジック変更禁止」明記必須

## CI BLOCKER (要即時修正)
- `fugue-orchestration-gate` が failure (3件連続)
- 原因: `scripts/lib/kernel-auth-evidence.sh:40` の `tr -c '[:alnum:]._-=' '_'`
- `_-=` が逆順文字範囲 → Linux tr でエラー (macOS では無警告)
- 修正: `tr -c '[:alnum:].=_-' '_'` (ハイフンを末尾に移動)
- GHA run: https://github.com/cursorvers/fugue-orchestrator/actions/runs/23422832386

## Kernel向けネクストステップ候補
- [ ] kernel-auth-evidence / kernel-consensus-evidence の統合テスト実行
- [ ] CI gate (fugue-orchestration-gate.yml) の consensus-evidence ジョブ検証
- [ ] GWS Phase 1/2 GHA promotion (前セッションからの継続)
