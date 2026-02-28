# RFC: Config B+ — Codex Main 固定 + Claude Assist MCP 実行委譲

> **Status**: PROPOSAL (Codex review requested)
> **Author**: Claude Opus (assist) + 大田原正幸
> **Date**: 2026-02-28
> **Supersedes**: config-c-hybrid-mcp-aware-routing.md (Main切替案を却下)
> **Scope**: AGENTS.md §2, §4 + fugue-tutti-caller.yml (§3 Provider Resolution は変更なし)
> **Risk tier**: low (Main orch 切替なし、Assist の役割拡張のみ)

---

## 1. Problem Statement (Config C v1.0 と同一)

全7 MCP サーバーが Claude-only protocol。Codex Main 構成 (Config B) では MCP 操作に構造的断絶がある。

| MCP | Codex 単体 | 影響 |
|-----|-----------|------|
| Pencil | ❌ 不可 | UI設計断絶（CLI代替なし） |
| Stripe | ❌ 不可 | 決済操作不可 |
| Supabase | ❌ 不可 | DB操作不可 |
| Slack | ❌ 不可 | 通知欠損 |
| Excalidraw | ❌ 不可 | 図表生成不可 |
| Grok | ❌ 不可 | リアルタイム検索不可 |
| Hostinger | ❌ 不可 | ホスティング不可 |

## 2. Config C v1.0 (Main切替案) を却下した理由

Main orchestrator の切替は以下の **連鎖的な変更** を引き起こす:

```
Main切替 codex → claude を発動すると:
  ├── profile 切替: codex-full → claude-light
  ├── preflight cycle: 3-5回 → 1-3回 (品質低下)
  ├── dialogue rounds: 2回 → 1回 (検証不足)
  ├── lane 構成: codex-main-orchestrator → claude-main-orchestrator
  ├── throttle guard: Claude main 用の pressure guard 発動
  ├── canary 期待値: 全テストの expected output が変化
  └── workflow 分岐: caller/router 内の全 if 条件が異なるパスへ
```

**結論**: MCP 接合性のために Main を切り替えるのは、コストが利益を大幅に上回る。

---

## 3. Proposed Solution: Config B+ (Main固定 + Assist MCP委譲)

### 3.1 設計原則

```
Codex (Main orchestrator) — 常に固定、一切切り替えない
  │
  ├── 通常タスク: Codex が直接実行
  │   (コードレビュー、CI修正、リファクタ、テスト作成...)
  │
  ├── MCP 必要タスク: Codex が Claude Assist に MCP 実行を委譲
  │   Codex: 「Pencilで画面Xを作れ」→ Claude: MCP実行 → 結果返却 → Codex: 統合判断
  │
  └── 評価・合議: 既存 6 lane consensus (変更なし)
```

### 3.2 核心: Assist の役割拡張

**現行 AGENTS.md §2 の Claude Assist の定義**:
> "claude can run as assist sidecar for **ambiguity resolution** and **integration quality**."

**Config B+ での拡張**:
> "claude can run as assist sidecar for **ambiguity resolution**, **integration quality**, and **MCP-bound execution**."

追加されるのは **3語のみ**。Main orchestrator の契約は一切変更しない。

### 3.3 アーキテクチャ

```
┌──────────────────────────────────────────────────────────────┐
│ Codex (Main Orchestrator) — 常時固定                          │
│                                                              │
│  Task Intake → 分類 → 実行計画                                │
│    │                                                         │
│    ├── [MCP不要] Codex直接実行                                │
│    │    └── code, review, CI, test, refactor...              │
│    │                                                         │
│    ├── [MCP必要] Claude Assist に MCP Execution Request 発行  │
│    │    ┌──────────────────────────────────────┐              │
│    │    │ MCP Execution Request                │              │
│    │    │                                      │              │
│    │    │ target_mcp: "pencil"                 │              │
│    │    │ operation: "batch_design"             │              │
│    │    │ params: { ... }                      │              │
│    │    │ timeout: 120s                        │              │
│    │    │ retry: 2                             │              │
│    │    │ on_failure: "report_to_main"         │              │
│    │    └──────────────────────────────────────┘              │
│    │         │                                               │
│    │         ▼                                               │
│    │    Claude Assist (MCP実行)                               │
│    │         │                                               │
│    │         ▼                                               │
│    │    ┌──────────────────────────────────────┐              │
│    │    │ MCP Execution Result                 │              │
│    │    │                                      │              │
│    │    │ status: "success" | "failed"         │              │
│    │    │ result: { ... }                      │              │
│    │    │ mcp_calls: 3                         │              │
│    │    │ latency_ms: 2400                     │              │
│    │    └──────────────────────────────────────┘              │
│    │         │                                               │
│    │         ▼                                               │
│    │    Codex: 結果を統合して次ステップへ                       │
│    │                                                         │
│    └── [合議] 既存 Tutti 6-lane (変更なし)                    │
└──────────────────────────────────────────────────────────────┘
```

### 3.4 MCP Execution Request の仕様

Codex → Claude Assist 間の委譲プロトコル:

```yaml
# GHA workflow step or local orchestration script 内で発行
mcp_execution_request:
  # 必須フィールド
  request_id: "mcp-req-{issue_number}-{timestamp}"
  target_mcp: "pencil" | "stripe-live" | "stripe-test" | "supabase" | "slack" | "excalidraw" | "grok" | "hostinger"
  intent: "自然言語でやりたいことを記述"

  # オプションフィールド
  structured_params: { }          # MCP tool の引数 (わかる場合)
  timeout_sec: 120                # デフォルト 120s
  max_retries: 2                  # デフォルト 2
  on_failure: "report" | "skip"   # デフォルト "report"

  # コンテキスト
  issue_number: 214
  parent_step: "implement-phase-2"
  codex_plan_summary: "..."       # Codex の実行計画要約 (Claude が文脈を理解するため)
```

```yaml
mcp_execution_result:
  request_id: "mcp-req-214-1709142000"
  status: "success" | "failed" | "timeout" | "partial"

  # 成功時
  result_summary: "..."           # Codex が理解できる自然言語要約
  artifacts: [ ]                  # 生成されたファイル/ノードID等
  mcp_calls_count: 3
  latency_ms: 2400

  # 失敗時
  error_type: "timeout" | "mcp_disconnected" | "auth_expired" | "operation_failed"
  error_detail: "..."
  recovery_suggestion: "..."      # Claude からの復旧提案
```

### 3.5 MCP タスク検出 (Codex側)

Codex が MCP 委譲の必要性を判断するための keyword dictionary:

```json
{
  "mcp_delegation_triggers": {
    "pencil": {
      "keywords": ["pencil", "ペンシル", ".pen", "UI設計", "UIデザイン", "画面設計", "モック", "コンポーネント設計", "batch_design", "get_screenshot"],
      "target_mcp": "pencil",
      "typical_timeout_sec": 180
    },
    "stripe": {
      "keywords": ["stripe", "決済", "課金", "subscription", "payment", "invoice", "refund", "顧客管理", "payment_link"],
      "target_mcp": "stripe-live",
      "typical_timeout_sec": 60
    },
    "supabase": {
      "keywords": ["supabase", "migration", "edge function", "RLS", "スキーマ変更", "テーブル操作", "DB操作", "execute_sql", "apply_migration"],
      "target_mcp": "supabase",
      "typical_timeout_sec": 90
    },
    "slack": {
      "keywords": ["slack通知", "チャンネル投稿", "slack連携", "slack_send_message"],
      "target_mcp": "slack",
      "typical_timeout_sec": 30
    },
    "excalidraw": {
      "keywords": ["excalidraw", "図表", "ダイアグラム", "アーキテクチャ図"],
      "target_mcp": "excalidraw",
      "typical_timeout_sec": 60
    },
    "grok": {
      "keywords": ["grok", "X検索", "Twitter", "リアルタイム検索", "トレンド"],
      "target_mcp": "grok",
      "typical_timeout_sec": 45
    },
    "hostinger": {
      "keywords": ["hostinger", "ホスティング", "DNS設定", "SSL"],
      "target_mcp": "hostinger",
      "typical_timeout_sec": 60
    }
  }
}
```

**配置先**: `config/mcp-delegation-triggers.json`

**判定ロジック**: Codex の preflight plan 段階で issue body + plan artifact をスキャンし、
keyword hit があれば当該 step を `mcp_execution_request` として Claude Assist に委譲。

### 3.6 実行フロー例: Pencil UI設計タスク

```
Issue: "Dashboard に新しい Agent Status カードを追加"

Codex (Main):
  1. Research → コードベース調査、既存コンポーネント確認
  2. Plan → 実装計画:
     - Step A: Pencil で UI コンポーネント設計 ← [MCP: pencil]
     - Step B: React コンポーネント実装
     - Step C: テスト作成
  3. Preflight → Step A を MCP delegation と判定

  4. MCP Execution Request 発行:
     → target_mcp: "pencil"
     → intent: "Dashboard の Agent Status 領域に新カード追加。
                既存 MetricCard (EWCQM) のパターンに準拠。
                表示項目: agent名, status, 最終応答時刻, 成功率"
     → codex_plan_summary: "Step B で React 化するため、
                            ノードID と構造を返却してほしい"

  5. Claude Assist (MCP実行):
     → get_editor_state()
     → batch_get(patterns=["MetricCard"])
     → batch_design([Insert operations...])
     → get_screenshot(nodeId)
     → 結果返却: { status: "success", artifacts: ["nodeId: XYZ123"], ... }

  6. Codex (Main): 結果を受け取り Step B (React実装) へ進行
  7. Implementation dialogue → Critic challenge → Verification
```

---

## 4. AGENTS.md 改訂案

### 4.1 §2 Control Plane Contract (追記のみ)

```markdown
## 2. Control Plane Contract

(既存条項はすべて維持)

- MCP-bound execution delegation:
  - When a task step requires MCP server interaction (Pencil, Stripe, Supabase, Slack, Excalidraw, Grok, Hostinger), the main orchestrator delegates that step to the Claude assist sidecar via `mcp_execution_request`.
  - The main orchestrator retains control of the overall task flow; Claude assist executes the MCP operation and returns structured results.
  - MCP delegation does not change the main orchestrator profile or lane configuration.
  - MCP delegation trigger keywords are defined in `config/mcp-delegation-triggers.json`.
  - If Claude assist is unavailable (`FUGUE_CLAUDE_RATE_LIMIT_STATE=exhausted`), MCP-dependent steps are marked `BLOCKED` and escalated to human review.
```

### 4.2 §3 Provider Resolution Contract — 変更なし

Main resolution order は一切変更しない。Codex が常に Main。

### 4.3 §4 Execution/Evaluation Lanes (追記のみ)

```markdown
(既存条項の末尾に追加)

- Claude assist MCP execution lane:
  - When main orchestrator identifies an MCP-dependent step, it issues an `mcp_execution_request` to the Claude assist lane.
  - This lane uses Claude's native MCP protocol for direct server interaction.
  - MCP execution results are returned to the main orchestrator for integration.
  - MCP execution lane failures are blocking for the dependent step but non-blocking for overall quorum.
  - Timeout: per-MCP defaults in `config/mcp-delegation-triggers.json`, hard cap `FUGUE_MCP_DELEGATION_TIMEOUT_SEC` (default 180).
  - Audit: MCP delegation requests and results must be logged in issue comments.
```

---

## 5. Implementation Plan

### Phase 1: MCP Delegation Protocol 定義 (2h)

1. `config/mcp-delegation-triggers.json` 作成 (§3.5 の内容)
2. `mcp_execution_request` / `mcp_execution_result` の JSON Schema 定義
3. AGENTS.md §2, §4 に追記 (§4.1, §4.3 の内容)

### Phase 2: Workflow 実装 (3h)

**変更対象**: `fugue-tutti-caller.yml` の implement フロー内

1. Codex implement step の preflight 出力から MCP keyword を検出する step 追加
2. MCP-dependent step を Claude assist lane に routing する step 追加
3. Claude assist の MCP execution result を Codex implement step に返却する step 追加
4. timeout / retry / failure handling

### Phase 3: Local Orchestration 対応 (2h)

**変更対象**: `scripts/local/run-local-orchestration.sh`

1. ローカル実行時の MCP delegation フロー実装
2. Claude assist の直接呼び出し (既存の `claude-opus-assist` gate を拡張)
3. MCP execution result のローカルログ出力

### Phase 4: Canary + Metrics (1h)

1. MCP delegation 付きの canary issue バリアント追加
2. 計測: delegation 回数、成功率、レイテンシ、Claude quota 消費
3. Config B (bridge) vs Config B+ (delegation) の比較

**合計: 8h** (Config C v1.0 と同等だが、破壊的変更ゼロ)

---

## 6. Config B vs Config B+ vs Config C 比較

| 指標 | Config B (現行) | Config C (却下) | Config B+ (本提案) |
|------|----------------|----------------|-------------------|
| Main orchestrator | Codex 固定 | **動的切替** | Codex 固定 |
| Profile | codex-full 固定 | 動的切替 | **codex-full 固定** |
| Preflight cycles | 3-5 固定 | 1-5 変動 | **3-5 固定** |
| Dialogue rounds | 2 固定 | 1-2 変動 | **2 固定** |
| §3 Resolution 変更 | なし | **要改訂** | **なし** |
| Lane 構成変更 | なし | タスク毎に変動 | **なし** |
| MCP 操作 | bridge (不安定) | Claude Main 直接 | **Assist 委譲 (直接)** |
| MCP 応答速度 | 45-75s (bridge) | <1s | **<1s (Assist直接)** |
| MCP 信頼性 | 低い | 高い | **高い** |
| Claude quota 消費 | 40-50% | 50-60% | **35-45%** |
| Codex 活用率 | 80-100回/週 | 55-70回/週 | **80-100回/週** |
| 実装リスク | — | 高 (全系変動) | **低 (Assist拡張のみ)** |
| Workflow 分岐変更 | なし | 全 workflow | **implement内のみ** |
| ロールバック | — | 困難 | **容易 (delegation skip)** |

### Config B+ が Config C より優れている理由

1. **安定性**: Main が常に同じ → profile/lane/preflight が一定 → テスト・canary の期待値が不変
2. **最小変更**: AGENTS.md §3 (Resolution) を触らない → 既存の全 workflow 分岐がそのまま動作
3. **Claude quota 節約**: MCP 操作の step だけ Claude を使う → タスク全体を Claude が処理する Config C より低コスト
4. **ロールバック容易**: MCP delegation を skip するだけで Config B に戻せる（`FUGUE_MCP_DELEGATION_ENABLED=false`）
5. **Codex 活用率維持**: Main として 80-100回/週のフル活用を維持

---

## 7. Review Request

### Codex に求める判断

1. **MCP delegation protocol**: §3.4 の request/result フォーマットは Codex implement step と整合するか？
2. **keyword detection 方式**: preflight plan artifact のテキストマッチで十分か？ それとも structured output (JSON plan with step types) が必要か？
3. **timeout 設計**: per-MCP default + hard cap 方式は適切か？ circuit breaker パターンが必要か？
4. **Claude quota 影響**: MCP delegation のみで Claude Assist を使う場合、quota 消費は 35-45% に収まるか？
5. **段階導入**: Phase 1-2 (protocol + workflow) だけで MVP リリースし、Phase 3-4 は後続で良いか？

### 代替案の検討依頼

以下の代替アプローチについても Codex の見解を求める:

| 代替案 | 概要 | 検討ポイント |
|--------|------|-------------|
| A. MCP REST Gateway | MCP を REST API でラップする中間層 | Codex が直接 MCP を呼べるようになるが、gateway のメンテコスト |
| B. Codex Native MCP | Codex CLI の MCP プロトコル対応を待つ | OpenAI のロードマップ次第。時期不明 |
| C. MCP CLI Wrapper | 各 MCP の操作を CLI コマンドとしてラップ | Pencil は CLI 化困難。Stripe/Supabase は既存 CLI あり |
| D. Hybrid (B+ の段階的拡張) | まず Stripe/Supabase を CLI 化、Pencil のみ delegation | MCP 依存を段階的に減らす長期戦略 |

---

## 8. Appendix

### A. Config B+ 導入後の AGENTS.md §2 全文イメージ

```markdown
## 2. Control Plane Contract

- Main orchestrator is provider-agnostic by design.
- Operational default is `codex` (main), with `claude` as assist sidecar.
- Operational default is `codex` when `FUGUE_CLAUDE_RATE_LIMIT_STATE` is `degraded` or `exhausted`.
- `claude` can run as assist sidecar for ambiguity resolution, integration quality, and MCP-bound execution.
- Claude subscription assumption is `FUGUE_CLAUDE_PLAN_TIER=max20` with `FUGUE_CLAUDE_MAX_PLAN=true`.
- State transitions and PR actions are owned by control plane workflows, not by sidecar advice.
- MCP-bound execution delegation:
  - When a task step requires MCP server interaction (Pencil, Stripe, Supabase, Slack, Excalidraw, Grok, Hostinger), the main orchestrator delegates that step to the Claude assist sidecar via `mcp_execution_request`.
  - The main orchestrator retains control of the overall task flow; Claude assist executes the MCP operation and returns structured results.
  - MCP delegation does not change the main orchestrator profile or lane configuration.
  - MCP delegation trigger keywords are defined in `config/mcp-delegation-triggers.json`.
  - If Claude assist is unavailable (`FUGUE_CLAUDE_RATE_LIMIT_STATE=exhausted`), MCP-dependent steps are marked `BLOCKED` and escalated to human review.
```

### B. Kill Switch

```yaml
# Repository variable で即時無効化可能
FUGUE_MCP_DELEGATION_ENABLED: "false"  # delegation 無効、Config B 動作に戻る
FUGUE_MCP_DELEGATION_TIMEOUT_SEC: "180"  # hard cap (default)
FUGUE_MCP_DELEGATION_MAX_PER_TASK: "5"  # 1タスクあたりの最大 delegation 数
```

### C. 関連ファイル

- `AGENTS.md` §2, §4 — 追記対象 (§3 は変更なし)
- `.github/workflows/fugue-tutti-caller.yml` — implement フロー内に delegation step 追加
- `scripts/local/run-local-orchestration.sh` — ローカル delegation 対応
- `config/mcp-delegation-triggers.json` — 新規作成

---

*Generated: 2026-02-28 by Claude Opus (assist) + 大田原正幸 — FUGUE Config B+ RFC v1.0*
*Supersedes: config-c-hybrid-mcp-aware-routing.md*
