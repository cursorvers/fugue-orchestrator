# Hybrid Conductor Mode 移行指示書

> **宛先**: Codex Main Orchestrator (現行FUGUE運用系)
> **発行者**: Claude Opus (assist) + 大田原正幸
> **発行日**: 2026-02-28
> **優先度**: HIGH
> **種別**: アーキテクチャ移行指示

---

## 1. 指示概要

FUGUEのオーケストレーション構成を **Config B (Codex Main / Claude Assist)** から **Hybrid Conductor Mode (Claude Main Orchestrator / Codex Executor)** へ移行する。

**設計思想**: Claude が Main Orchestrator として routing・MCP操作・Tutti signal に専念し、Codex が Execution Provider として全コード実装を担う。

---

## 2. 移行理由

### 2.1 現行 Config B の構造的問題

Claude Code に登録された全7 MCP サーバー (Pencil, Stripe, Supabase, Slack, Excalidraw, Grok, Hostinger) は Claude-only protocol で動作する。Codex Main 構成では:

- MCP bridge 経由の呼び出し: **+45-75秒/回** のレイテンシ増加
- bridge 成功率: 不安定 (Slack はサイレント失敗)
- Claude quota 消費: bridge により想定 30-35% を超過し **実測 40-50%**
- Pencil MCP には CLI 代替が**存在しない**

### 2.2 Hybrid で解決される問題

| 問題 | Config B | Hybrid |
|------|----------|--------|
| MCP 応答速度 | 45-75s (bridge) | <1s (Claude直接) |
| MCP 信頼性 | 不安定 | 100% |
| Claude quota 消費 | 40-50% (bridge込) | 50-60% (routing のみ) |
| Codex 活用率 | 80-100回/週 | 55-70回/週 |
| Preflight 深度 | 3-5 cycle | 1-3 (routing), 3-5 (実装) |

---

## 3. アーキテクチャ変更内容

### 3.1 新概念: Orchestration / Execution 分離

```
従来 (Config B):
  main_provider = codex  →  routing + 実装 両方 Codex
  assist = claude         →  MCP bridge + 補助投票

Hybrid Conductor Mode:
  main_orchestrator = claude  →  routing, MCP, Tutti signal
  execution_provider = codex  →  全コード実装 (codex-full profile)
  assist = codex              →  architectural invariant (自動解決)
```

### 3.2 新規変数

| 変数 | 用途 | 値 |
|------|------|-----|
| `FUGUE_EXECUTION_PROVIDER` | 実装担当プロバイダ (NEW) | `codex` |

### 3.3 変更する既存変数

| 変数 | 現在値 | 変更後 |
|------|--------|--------|
| `FUGUE_MAIN_ORCHESTRATOR_PROVIDER` | `codex` | `claude` |
| `FUGUE_CLAUDE_ROLE_POLICY` | `sub-only` | `flex` |

### 3.4 変更不要な変数

- `FUGUE_ASSIST_ORCHESTRATOR_PROVIDER`: main=claude 時の architectural invariant (orchestrator-policy.sh L199-207) により自動的に `codex` に解決される
- `FUGUE_CI_EXECUTION_ENGINE`: 変更なし
- `FUGUE_MIN_CONSENSUS_LANES`: 変更なし (6 lanes 維持)

---

## 4. 実装済みコード変更 (検証済み)

### 4.1 AGENTS.md (SSOT)

- §2: Operational default を `claude (main conductor) + codex (execution provider)` に変更
- §2: Hybrid Conductor Mode 定義を追加
- §2: Hybrid Handoff Contract を追加 (Claude→Codex 間の責務境界)
- §2: Hybrid Failover を追加 (Claude degraded/exhausted 時の自動解除)
- §3: Fallback default を `codex` → `claude` に変更
- §3: Execution provider resolution を新設
- §4: Hybrid implementation dispatch ルールを追加
- §5: dialogue_rounds の決定基準を `execution_profile` ベースに修正

### 4.2 fugue-tutti-caller.yml

- `EXECUTION_PROVIDER_DEFAULT` 環境変数を追加
- `DEFAULT_MAIN_ORCHESTRATOR_PROVIDER` デフォルトを `codex` → `claude` に変更
- ctx outputs に `execution_provider`, `execution_profile`, `hybrid_conductor_mode` を追加
- execution_provider / hybrid_conductor_mode 解決ロジックを追加
- 逆Hybrid構成 (main=codex + exec=claude) を検知しrejectするガードを追加
- `preflight_cycles`, `dialogue_rounds` の決定を `execution_profile` ベースに変更
- claude-light multi-agent 制限を Hybrid 時に解除
- codex-implement dispatch に `execution_profile` を渡すよう変更

### 4.3 fugue-orchestrator-canary.yml

- `DEFAULT_MAIN_ORCHESTRATOR_PROVIDER`, `EXECUTION_PROVIDER_DEFAULT`, `CANARY_ALTERNATE_PROVIDER` を追加
- default_main_provider / canary_alternate_main の動的解決ロジックを追加
- Regular canary: 本番構成テスト (claude-main)
- Alternate canary: 逆構成テスト (codex-main) — 有意な比較を実現
- `create_issue()` を orchestrator provider パラメタライズ化
- `orchestrator:codex` ラベルを追加

### 4.4 sim-orchestrator-switch.sh

- `FUGUE_EXECUTION_PROVIDER`, `FUGUE_MAIN_ORCHESTRATOR_PROVIDER` 対応を追加
- 出力に `execution_provider`, `hybrid_mode` カラムを追加
- `--default-main` をハードコード `codex` から production variable ベースに変更
- `dialogue_rounds` を `execution_profile` ベースに変更
- Hybrid シナリオ S11-S15 を追加 (execution_provider_default=codex)

---

## 5. シミュレーション検証結果

### 5.1 Hybrid 構成 (15 scenario 全 PASS)

```
S11: claude main, exec=codex, hybrid=true,  dialogue=2, codex-implement ✓
S12: claude main, exec=codex, hybrid=true,  continuity mode            ✓
S13: codex main (degraded),   hybrid=false, throttle guard 発動        ✓
S14: codex main (exhausted),  hybrid=false, assist=none, 完全fallback  ✓
S15: claude main, exec=codex, hybrid=true,  review mode                ✓
```

### 5.2 後方互換 (Config B: sub-only, default=codex)

```
S1-S10: 全て hybrid=false, 既存動作完全維持 ✓
```

### 5.3 GLM 独立検証 (2回実施、全 PASS)

| 検証項目 | 結果 |
|----------|------|
| Hybrid 不変条件 (main=claude 時のみ hybrid=true) | PASS |
| Failover (degraded/exhausted → Hybrid 解除) | PASS |
| Dialogue Rounds (Hybrid 時 codex-full=2 適用) | PASS |
| 後方互換 (Config B 動作維持) | PASS |
| 逆 Hybrid ガード (main=codex + exec=claude 拒否) | PASS |
| Implementation Gate (codex-implement 発動) | PASS |

---

## 6. Codex への確認事項

### 6.1 本指示で求める判断

1. **移行承認**: Hybrid Conductor Mode への移行に同意するか
2. **変数変更タイミング**: リポジトリ変数の変更はコードマージ後に一括で行うべきか
3. **canary 先行実行**: 本番変数変更前に canary workflow_dispatch で検証すべきか
4. **rollback 手順**: 問題発生時は変数を元に戻すだけで Config B に即時復帰可能であることの確認

### 6.2 Codex 視点で検証してほしい点

- `codex-implement` job が Hybrid 時に正しく呼び出されるか (tutti-caller.yml L1235-1254)
- `execution_profile=codex-full` が implementation parameters に正しく伝搬するか
- `build-agent-matrix.sh` が main=claude 時の lane topology を正しく生成するか (L230-327)

### 6.3 移行手順 (承認後)

```bash
# Step 1: コード変更をコミット & PR 作成
git checkout -b feat/hybrid-conductor-mode
git add AGENTS.md .github/workflows/ scripts/sim-orchestrator-switch.sh
git commit -m "feat: implement Hybrid Conductor Mode (Claude orchestrator + Codex executor)"
gh pr create --title "feat: Hybrid Conductor Mode" --body "..."

# Step 2: PR マージ後、リポジトリ変数を変更
gh variable set FUGUE_CLAUDE_ROLE_POLICY --body "flex"
gh variable set FUGUE_MAIN_ORCHESTRATOR_PROVIDER --body "claude"
gh variable set FUGUE_EXECUTION_PROVIDER --body "codex"

# Step 3: Canary 検証
gh workflow run fugue-orchestrator-canary.yml

# Step 4: 問題発生時の即時 rollback
gh variable set FUGUE_CLAUDE_ROLE_POLICY --body "sub-only"
gh variable set FUGUE_MAIN_ORCHESTRATOR_PROVIDER --body "codex"
gh variable delete FUGUE_EXECUTION_PROVIDER
```

---

## 7. 不変量 (変更されない事項)

- Core quorum: 6 lanes minimum (Codex3 + GLM3)
- Tutti weighted consensus (2/3 threshold + HIGH-risk veto)
- Safety gates (preflight refinement, implementation dialogue)
- Codex recursive delegation policy
- GLM subagent fan-out policy
- Shared skills baseline
- Shared workflow playbook

---

*Generated: 2026-02-28 by Claude Opus (assist) — Hybrid Conductor Mode Migration Directive v1.0*
