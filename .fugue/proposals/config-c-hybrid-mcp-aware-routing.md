# RFC: Config C — MCP依存度ベース動的オーケストレーター切替

> **Status**: PROPOSAL (Codex review requested)
> **Author**: Claude Opus (assist) + 大田原正幸
> **Date**: 2026-02-28
> **Scope**: AGENTS.md §2, §3, §4 + fugue-task-router.yml + fugue-tutti-caller.yml
> **Risk tier**: medium (既存ラベル機構を活用、破壊的変更なし)

---

## 1. Problem Statement

### 1.1 現状の構成 (Config B: Codex Main / Claude Assist)

AGENTS.md §2 が定める operational default:
```
Main = codex ($200/mo fixed)
Assist = claude (MAX sidecar)
```

### 1.2 発見された構造的問題

Claude Code に登録されている **全7 MCP サーバー** は Claude-only protocol で動作する。
Codex が Main の場合、MCP 操作は以下のいずれかになる:

| MCP | Codex 単体 | Claude bridge 経由 | 結果 |
|-----|-----------|-------------------|------|
| Pencil | ❌ | ⚠️ 不安定 (timeout 45-75s) | UI設計ワークフロー断絶 |
| Stripe (Live/Test) | ❌ | ⚠️ 不安定 (timeout 75s) | 決済操作遅延 |
| Supabase | ❌ | ⚠️ 不安定 (timeout 45s) | DB操作不可 |
| Slack | ❌ | ❌ サイレント失敗 | 通知欠損 |
| Excalidraw | ❌ | ⚠️ 不安定 | 図表生成不可 |
| Grok (xAI) | ❌ | ❌ fallback なし | リアルタイム検索不可 |
| Hostinger | ❌ | ❌ fallback なし | ホスティング操作不可 |

### 1.3 定量的影響

- bridge 経由の MCP 呼び出し: **+45-75 秒/回** のレイテンシ増加
- bridge 成功率: 未計測（ログ未整備）
- Claude quota 消費: bridge 呼び出しにより **実質 40-50%** 消費（Config B の想定 30-35% を超過）
- Pencil MCP には CLI 代替が**存在しない**

### 1.4 根本原因

AGENTS.md §3 の Provider Resolution Contract が **タスクの MCP 依存度を考慮していない**。
resolution order は label → body hint → variable → fallback の 4 段階だが、
すべてが「誰が orchestrate するか」のみで、「何に接続する必要があるか」を判定しない。

---

## 2. Proposed Solution: Config C (Hybrid MCP-Aware Routing)

### 2.1 概要

タスク intake 時に **MCP 依存度** を自動判定し、依存度に応じて Main orchestrator を動的に切り替える。

```
Task Intake (fugue-task-router.yml)
    │
    ▼
┌─────────────────────────────┐
│ MCP Dependency Classifier   │
│                             │
│ Input: issue title + body   │
│ Output: mcp_tier (0|1|2)    │
│                             │
│ tier 0: MCP 不要            │
│ tier 1: MCP 軽度 (通知のみ) │
│ tier 2: MCP 重度 (操作必須) │
└──────────┬──────────────────┘
           │
           ▼
┌──────────────────────────────────────────────┐
│ Provider Resolution (AGENTS.md §3 拡張)       │
│                                               │
│ 1. Issue label (既存: 最優先、変更なし)         │
│ 2. Issue body hint (既存: 変更なし)            │
│ 3. ★ NEW: MCP tier routing                    │
│    tier 0 → main=codex, assist=claude         │
│    tier 1 → main=codex, assist=claude         │
│    tier 2 → main=claude, assist=codex         │
│ 4. Repository variable (既存: 変更なし)        │
│ 5. Fallback default codex (既存: 変更なし)     │
└──────────────────────────────────────────────┘
```

### 2.2 MCP Dependency Classifier の判定ロジック

**tier 2 (MCP重度)** のトリガーキーワード:

```json
{
  "mcp_tier_2_keywords": {
    "pencil": ["pencil", "ペンシル", ".pen", "UI設計", "UIデザイン", "画面設計", "モック", "コンポーネント設計"],
    "stripe": ["stripe", "決済", "課金", "subscription", "payment", "invoice", "refund", "顧客管理"],
    "supabase": ["supabase", "migration", "edge function", "RLS", "スキーマ変更", "テーブル操作", "DB操作"],
    "excalidraw": ["excalidraw", "図表", "ダイアグラム", "アーキテクチャ図"],
    "multi_mcp": ["UI + DB", "画面 + API", "フルスタック"]
  },
  "mcp_tier_1_keywords": {
    "slack": ["slack通知", "チャンネル投稿", "slack連携"],
    "hostinger": ["デプロイ", "ホスティング", "DNS"]
  }
}
```

**判定の優先順位**: 明示ラベル > MCP tier判定 > variable > fallback

### 2.3 ラベル自動付与

Classifier が tier 2 と判定した場合、以下のラベルを自動付与:

```yaml
# fugue-task-router.yml の intake step に追加
- name: Auto-label MCP tier
  if: steps.classify.outputs.mcp_tier == '2'
  run: |
    gh issue edit $ISSUE_NUMBER \
      --add-label "orchestrator:claude" \
      --add-label "mcp:heavy"
```

**重要**: 明示ラベル `orchestrator:codex` が既に付いている場合はオーバーライドしない。
ユーザーの明示的意図が最優先（既存契約の維持）。

### 2.4 既存契約との整合性

| AGENTS.md 条項 | Config C の影響 | 互換性 |
|---------------|----------------|--------|
| §2 Control Plane Contract | "provider-agnostic by design" → **適合** (タスク特性で切替) | ✅ |
| §3 Provider Resolution | resolution order に step 3 を**挿入** | ⚠️ 要改訂 |
| §3 Throttle guard | Claude main 時の guard はそのまま適用 | ✅ |
| §4 Core quorum 6 lanes | 変更なし | ✅ |
| §4 Dual main signal | tier 2 時は Claude main + Codex secondary | ✅ |
| §5 Safety / HIGH-risk veto | 変更なし | ✅ |
| §9 Shared Skills Baseline | 変更なし | ✅ |

---

## 3. Implementation Plan

### Phase 1: Classifier + Auto-Label (推定工数: 3h)

**変更対象**: `fugue-task-router.yml`

1. MCP keyword dictionary を `config/mcp-tier-keywords.json` に定義
2. intake step に keyword matcher を追加 (bash grep/jq, LLM不要)
3. tier 2 判定時に `orchestrator:claude` + `mcp:heavy` ラベルを自動付与
4. tier 0/1 判定時はラベル付与なし（既存 default codex のまま）
5. 判定結果を issue comment に audit log 出力

### Phase 2: AGENTS.md 改訂 (推定工数: 1h)

**変更対象**: `AGENTS.md` §3

```markdown
## 3. Provider Resolution Contract

Main resolution order:
1. Issue label (`orchestrator:claude` or `orchestrator:codex`)
2. Issue body hint (`## Orchestrator provider` or `orchestrator provider: ...`)
3. MCP dependency tier (`mcp:heavy` label → `claude`, otherwise unchanged)
4. Repository variable `FUGUE_MAIN_ORCHESTRATOR_PROVIDER`
5. Fallback default `codex`
```

### Phase 3: Canary + Metrics (推定工数: 2h)

**変更対象**: `fugue-orchestrator-canary.yml`

1. Canary issue に `mcp:heavy` ラベル付きバリアントを追加
2. 以下の metrics を canary run ごとに計測:
   - `mcp_bridge_call_count`: bridge 経由 MCP 呼び出し回数
   - `mcp_bridge_latency_p50`: bridge レイテンシ中央値
   - `mcp_bridge_success_rate`: bridge 成功率
   - `claude_quota_consumed_pct`: Claude quota 消費率
3. 比較: Config B (全件 Codex main) vs Config C (MCP-aware routing)

### Phase 4: タスク分布分析 + チューニング (推定工数: 2h)

直近 30 日のissue履歴から MCP tier 分布を算出:

```bash
# 想定される分布 (仮説)
tier 0 (MCP不要): 60-70% → Codex main (コスト最適)
tier 1 (MCP軽度): 10-15% → Codex main + 通知のみ Claude
tier 2 (MCP重度): 15-25% → Claude main (MCP直接操作)
```

**目標**: Claude quota 消費を **50-60%** に収める（Config A の 90-98% と Config B 実測の 40-50% の中間）。

---

## 4. Expected Outcomes

### 4.1 比較表

| 指標 | Config A (Claude Main) | Config B (Codex Main) | Config C (Hybrid) |
|------|----------------------|----------------------|-------------------|
| Claude quota 消費 | 90-98% | 40-50% (bridge込) | **50-60%** |
| MCP 応答速度 | <1s (直接) | 45-75s (bridge) | **<1s (tier2), N/A (tier0)** |
| MCP 操作信頼性 | 100% | 不安定 | **100% (tier2)** |
| Codex 活用率 | 15回/週 | 80-100回/週 | **55-70回/週** |
| Preflight 深度 | 1-3 cycle | 3-5 cycle | **1-3 (tier2), 3-5 (tier0)** |
| failover 必要性 | 高 | 低 | **中低** |
| 実装コスト | — | — | **8h (4 phases)** |

### 4.2 リスク

| リスク | 影響 | 緩和策 |
|--------|------|--------|
| Classifier の誤判定 (false negative) | tier 2 タスクが Codex に流れ MCP bridge 発動 | issue comment で audit; 手動ラベルでオーバーライド可能 |
| Classifier の誤判定 (false positive) | tier 0 タスクが Claude に流れ quota 浪費 | keyword dictionary の定期レビュー; false positive 率を canary で計測 |
| 判定ロジックの複雑化 | workflow メンテナンスコスト増 | keyword dictionary を外部 JSON に分離; LLM 判定は使わない |
| Claude quota 消費が想定超過 | tier 2 タスク比率が想定 (15-25%) を超える場合 | `FUGUE_MCP_TIER2_QUOTA_CAP` 変数でClaude main タスク数/日を制限 |

---

## 5. Review Request

### Codex に求める判断

1. **アーキテクチャ妥当性**: MCP tier を Provider Resolution に挿入する位置は §3 の step 3 が適切か？
2. **keyword dictionary の網羅性**: 上記 tier 2 keywords で漏れはないか？
3. **Config B との backward compatibility**: tier 0/1 タスクの動作が完全に Config B と同一であることの確認
4. **コスト見積もりの妥当性**: Phase 1-4 合計 8h は現実的か？
5. **代替案**: Config C 以外に MCP 接合性問題を解決するアプローチはあるか？
   - 例: Codex ネイティブ MCP プロトコル対応の見込み
   - 例: MCP → REST API gateway の中間層
   - 例: Pencil MCP の CLI エクスポート機能

### 合議参加者

| Role | Provider | 期待する視点 |
|------|----------|-------------|
| **architect** | Codex | アーキテクチャ整合性、§3 改訂の影響範囲 |
| **security-analyst** | Codex | ラベル自動付与の悪用リスク、MCP bridge のセキュリティ |
| **scope-analyst** | Codex | 実装スコープの妥当性、Phase 分割の適切性 |
| **general-reviewer** | GLM | keyword dictionary の自然言語カバレッジ |
| **ui-reviewer** | Gemini | Pencil MCP ワークフローへの影響 (該当する場合) |

---

## 6. Appendix

### A. 現在の MCP Server 構成 (settings.json)

```
pencil    → stdio → pencil-mcp-wrapper.sh → Pencil.app (port 55520)
stripe    → stdio → npx @stripe/mcp --tools=all
supabase  → stdio → npx @modelcontextprotocol/server-supabase
slack     → stdio → npx @slack/mcp
excalidraw → stdio → bash wrapper → local Express (port 3001)
grok      → stdio → Node.js xAI wrapper
hostinger → stdio → npx hostinger-api-mcp@latest
```

### B. 関連ファイル

- `AGENTS.md` §2, §3, §4 — 改訂対象
- `.github/workflows/fugue-task-router.yml` — Classifier 追加対象
- `.github/workflows/fugue-tutti-caller.yml` — resolution order 改訂対象
- `~/.claude/fallback/config.json` — closed_services list (参考)
- `~/.claude/fallback/orchestrator.sh` — bridge 実装 (参考)

### C. 先行事例: 既存の動的切替

AGENTS.md §3 Throttle guard は既に「Claude の状態に応じた動的切替」を実装済み:
```
claude degraded/exhausted → auto-fallback to codex
```
Config C はこれと同じパターンを「MCP 依存度に応じた動的切替」に拡張する。
既存の throttle guard と衝突しない（throttle guard は Config C の resolution より優先）。

---

*Generated: 2026-02-28 by Claude Opus (assist) — FUGUE Config C RFC v1.0*
