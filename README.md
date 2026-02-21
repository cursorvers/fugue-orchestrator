# FUGUE Orchestrator

> **FUGUE** = **F**ederated **U**nified **G**overnance for **U**niversal **E**xecution
>
> 分散自律 x 統合収束

Claude Code 向けのマルチモデル AI オーケストレーションフレームワーク。Claude を純粋なオーケストレーターに徹させ、タスク実行は専門 AI エージェント（Codex/GPT, GLM, Gemini, Grok）に委譲します。

名前は音楽のフーガに由来します。複数の独立した声部が織り合わさり、ひとつの統一された全体を形成する。各 AI モデルが声部であり、オーケストレーターが調和を保証します。

## 課題

Claude Code の Agent Teams 機能はレートリミットが想定より低い閾値で発生します。サブエージェント・計画・実行をすべて Claude で回すと、すぐにリミットに到達します。

## 解決策

**2層オーケストレーション**: Claude Opus はオーケストレーター（ルーティング・統合・報告）に専念。個別タスクの実行は固定費サブスクリプションの外部モデルに委譲。

```
ユーザー
    |  指示
Claude Opus（オーケストレーター専念）
    |  ルーティング
+-----------------------------------+
| 実行層 (Execution Tier)           |
| +-> Codex (コード, 設計, セキュリティ) |
| +-> GLM   (レビュー, 要約, 数学)  |
| +-> Gemini (UI/UX評価)           |
| +-> Grok  (X/Twitter, リアルタイム) |
| +-> Pencil MCP (UI開発)          |
+-----------------------------------+
    |  成果物
+-----------------------------------+
| 評価層 (Evaluation Tier) [自動]   |
| +-> GLM   (コード品質)           |
| +-> Codex (セキュリティ監査)      |
| +-> Gemini (UI/UX監査)           |
+-----------------------------------+
    |  フィードバック
Claude Opus（統合・報告）
```

## 基本原則

- **オーケストレーターは実行しない**: Claude はルーティング・統合・報告のみ。実装は禁止。
- **固定費の最大活用**: Codex ($200/月) と GLM ($15/月) で90%以上のタスクを処理。
- **サブエージェント最小化**: Haiku/Sonnet サブエージェントは Claude レートリミットを消費するため、ファイル探索のみに限定。
- **二重評価**: 成果物はユーザーに報告する前に自動レビューを通過。

## ファイル構成

```
AGENTS.md                              <- SSOT: オーケストレーション契約（共通）
CLAUDE.md                              <- Claude用薄いアダプタ（AGENTS.mdを参照）
rules/
  delegation-matrix.md                 <- SSOT: 誰が何を担当するか
  auto-execution.md                    <- 自動委譲トリガー
  delegation-flow.md                   <- 委譲プロセスの詳細
  codex-usage.md                       <- Codex 使用ガイド
  dangerous-permission-consensus.md    <- 危険操作の3者合議制
  coding-style.md                      <- コーディング規約
  testing.md                           <- TDD ルール
  security.md                          <- セキュリティチェックリスト
  performance.md                       <- モデル選択・最適化
  secrets-management.md                <- API キー管理
examples/
  delegate-stub.js                     <- 最小委譲スクリプト（Codex/GLM/Gemini対応）
  parallel-delegation.sh               <- 並列コードレビュー + セキュリティ監査
  consensus-vote-stub.sh               <- 3者合議制デモ
docs/
  ADR-001-why-fugue.md                 <- アーキテクチャ決定記録: なぜ FUGUE なのか
```

## 前提条件

| サービス | 用途 | コスト |
|---------|------|--------|
| Claude Code (MAX $200) | オーケストレーター | $200/月 |
| OpenAI Codex / GPT Pro | コード実行, 設計, セキュリティ | $200/月 |
| GLM (Z.ai) | 軽量レビュー, 要約, 数学 | $15/月 |
| Gemini (Google AI) | UI/UX 評価, 画像分析 | 従量課金 |
| Grok (xAI) | X/Twitter, リアルタイム情報 | API 課金 |

## クイックスタート

```bash
# 1. クローン
git clone https://github.com/cursorvers/fugue-orchestrator.git
cd fugue-orchestrator

# 2. ルールを Claude Code 設定にコピー
cp AGENTS.md ~/.claude/AGENTS.md
cp CLAUDE.md ~/.claude/CLAUDE.md
cp -r rules/ ~/.claude/rules/

# 3. API キーを設定
export OPENAI_API_KEY="your-openai-key"
export GLM_API_KEY="your-glm-key"
export GLM_MODEL="glm-5.0" # optional (default in Tutti lanes is glm-5.0)
export GEMINI_API_KEY="your-gemini-key"
export XAI_API_KEY="your-xai-key" # optional (X/Twitter / realtime specialist)
export ANTHROPIC_API_KEY="your-anthropic-key" # optional (Claude assist lane)

# 3.5 GitHub Actions 用オーケストレータ切替（repo variable 優先）
# gh variable set FUGUE_MAIN_ORCHESTRATOR_PROVIDER   --body codex   -R <owner/repo>
# gh variable set FUGUE_ASSIST_ORCHESTRATOR_PROVIDER --body claude  -R <owner/repo>
# (legacy) gh variable set FUGUE_ORCHESTRATOR_PROVIDER --body codex -R <owner/repo>
# gh variable set FUGUE_CLAUDE_RATE_LIMIT_STATE --body ok        -R <owner/repo>
# gh variable set FUGUE_CLAUDE_RATE_LIMIT_STATE --body degraded  -R <owner/repo>
# gh variable set FUGUE_CLAUDE_RATE_LIMIT_STATE --body exhausted -R <owner/repo>
# issue意図に応じて Gemini/xAI specialist lane が自動追加されます
# NOTE: state が exhausted のとき、mainのclaude指定は codex、assistのclaude指定は none に自動フォールバックします。
# NOTE: state が ok/degraded かつ assist=claude のとき、Sonnet追加レーンが /vote に参加します。
# NOTE: `gha24` が事前フォールバックした場合は、Issueに監査コメントが自動投稿されます。

# 3.6 gha24 でリクエスト単位に上書き（任意）
# gha24 "完遂: API障害対応" --implement --orchestrator claude
# gha24 "完遂: API障害対応" --implement --orchestrator codex --assist-orchestrator claude
# gha24 "完遂: API障害対応" --implement --orchestrator claude --force-claude
# あるいは:
# GHA24_ORCHESTRATOR_PROVIDER=claude gha24 "完遂: API障害対応" --implement

# 3.7 Orchestrator切替シミュレーション（ローカル・非破壊）
# ./scripts/sim-orchestrator-switch.sh | column -t -s $'\t'

# Note:
# `orchestrator provider` は Tutti のレーン選択プロファイルです。
# 実装実行エンジンは `fugue-codex-implement`（Codex CLI）で固定です。

# 4. 委譲テスト（examples/delegate-stub.js を使用）
node examples/delegate-stub.js -a code-reviewer -t "Review this function" -p glm

# 5. 並列評価テスト
chmod +x examples/parallel-delegation.sh
./examples/parallel-delegation.sh "Review auth module" src/auth.ts

# 6. 合議制テスト
chmod +x examples/consensus-vote-stub.sh
./examples/consensus-vote-stub.sh "rm -rf ./build" "Clean build artifacts"
```

## 委譲スクリプト

`examples/` ディレクトリにスタブ実装があります:

| スクリプト | 用途 | プロバイダ |
|-----------|------|-----------|
| `delegate-stub.js` | 単一プロバイダへの委譲 | Codex, GLM, Gemini |
| `parallel-delegation.sh` | 並列コードレビュー + セキュリティ監査 | GLM + Codex |
| `consensus-vote-stub.sh` | 危険操作の3者合議制 | Claude + Codex + GLM |

本番利用時は `~/.claude/skills/orchestra-delegator/scripts/` にコピーしてカスタマイズ:
```
~/.claude/skills/orchestra-delegator/scripts/
  delegate.js        # delegate-stub.js -p codex ベース
  delegate-glm.js    # delegate-stub.js -p glm ベース
  delegate-gemini.js # delegate-stub.js -p gemini ベース
  parallel-codex.js  # parallel-delegation.sh ベース
  consensus-vote.js  # consensus-vote-stub.sh ベース
```

## アーキテクチャ決定記録

競合比較（AutoGen, CrewAI, LangGraph, Agent Teams）を含む設計根拠の詳細は [ADR-001: Why FUGUE Exists](docs/ADR-001-why-fugue.md) を参照。

## FUGUE オーケストレーション vs. Claude Code Agent Teams

FUGUE と Agent Teams は補完関係にあり、競合ではありません。核心的な違いは**計算がどこで行われるか**と**何がレートリミットを消費するか**です。

### 根本的な違い

|  | FUGUE オーケストレーション | Agent Teams |
|--|--------------------------|-------------|
| **実行者** | Codex / GLM / Gemini（外部API） | 複数の Claude インスタンス |
| **コストモデル** | 固定費（$200+$15/月） | Claude レートリミット消費 |
| **通信** | Claude → 外部 → Claude | メンバー同士が直接通信 |
| **適用場面** | 日常タスク（95%） | 特殊な並列協調タスク（5%） |

### 判断フロー

```
タスク受領
    |
メンバー間の直接通信が必要？
+- No（95%）→ FUGUE（Codex/GLM に委譲）
+- Yes（5%）→ さらに判断
    |
    Codex/GLM の並列実行で代替可能？
    +- Yes → FUGUE（parallel-codex.js 等）
    +- No  → Agent Teams
```

### FUGUE を使う場面（デフォルト）

- コードレビュー → Codex/GLM
- 設計判断 → Codex architect
- セキュリティ分析 → Codex security-analyst
- 要約・翻訳 → GLM
- UI 開発 → Pencil MCP
- UI 評価 → Gemini

**理由**: 固定費内で収まる。Claude レートリミットを消費しない。

### Agent Teams を使う場面（限定的）

| シナリオ | Agent Teams が有効な理由 |
|---------|------------------------|
| 大規模コードベース探索 | 5人が異なるディレクトリを同時に調査、発見を共有 |
| 競合仮説デバッグ | 「認証が原因？」「DB接続が原因？」を並列検証、リアルタイム情報共有 |
| クロスレイヤー実装 | frontend / backend / tests を別メンバーが同時に書き、整合性を直接確認 |
| Codex + GLM 両方障害時 | フォールバック: Claude インスタンス同士で作業 |

**共通点**: **メンバー間の直接コミュニケーション**が価値を生む場面。

### 具体例

**FUGUE で十分:**
> 「この PR をレビューして」
> → Codex code-reviewer + security-analyst を並列実行
> → 結果を統合して報告

**Agent Teams が有効:**
> 「自動登録システムのバグ。原因不明。
> 認証フロー、DB、Webhook、外部 API の4方面から同時に調査して、
> 発見をリアルタイムで共有しながら原因を特定して」
> → 4人のメンバーが調査しながら情報交換
> → メンバーA「認証は正常」→ メンバーB「DB側でこの値が不正」
> → メンバーC「それなら Webhook のペイロードを確認する」

### レートリミットへの影響

```
FUGUE:  Claude = ルーティングのみ（レートリミット消費: 最小）
Teams:  Claude × メンバー数（レートリミット消費: 大）
```

Agent Teams はメンバー1人につきフルのコンテキストウィンドウを消費します。「サブエージェント原則禁止」と同じ注意が必要。週に1-2回の特殊タスクに限定するのが現実的です。

## レートリミット戦略

| モデル | 目標使用量 | 役割 |
|--------|-----------|------|
| **Codex** | 120-150回/週 | コード全般 + 設計 + 複雑判断 |
| **GLM** | 120-150回/週 | 非コード全般 + 軽量レビュー + 分類 |
| **Subagent (Haiku)** | <=5回/週 | ファイル探索のみ |
| **Subagent (Sonnet)** | 0回/週 | 禁止（Codex に移管） |
| **Agent Teams** | 1-2タスク/週 | 複雑な並列協調のみ |
| **Claude Opus** | 最小限 | オーケストレーション専念 |

## ライセンス

MIT

## クレジット

FUGUE 哲学に基づく: 分散自律 x 統合収束
