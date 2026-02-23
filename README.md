# FUGUE Orchestrator

> **FUGUE** = **F**ederated **U**nified **G**overnance for **U**niversal **E**xecution
>
> 分散自律 x 統合収束

Codex/Claude 両対応のマルチモデル AI オーケストレーションフレームワーク。メインオーケストレーターは実行を持たず、タスク実行は専門 AI エージェント（Codex/GPT, GLM, Gemini, Grok）に委譲します。

名前は音楽のフーガに由来します。複数の独立した声部が織り合わさり、ひとつの統一された全体を形成する。各 AI モデルが声部であり、オーケストレーターが調和を保証します。

## 課題

Claude Code の Agent Teams 機能はレートリミットが想定より低い閾値で発生します。サブエージェント・計画・実行をすべて Claude で回すと、すぐにリミットに到達します。

## 解決策

**2層オーケストレーション**: メインオーケストレーター（Codex/Claude）はルーティング・統合・報告に専念。個別タスクの実行は固定費サブスクリプションの外部モデルに委譲。

```
ユーザー
    |  指示
Main Orchestrator（Codex/Claude）
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
Main Orchestrator（統合・報告）
```

## 基本原則

- **オーケストレーターは実行しない**: メインオーケストレーター（Codex/Claude）はルーティング・統合・報告のみ。実装は禁止。
- **固定費の最大活用**: Codex ($200/月) と GLM ($15/月) で90%以上のタスクを処理。
- **サブエージェント最小化**: Haiku/Sonnet サブエージェントは Claude レートリミットを消費するため、ファイル探索のみに限定。
- **二重評価**: 成果物はユーザーに報告する前に自動レビューを通過。

## ファイル構成

```
AGENTS.md                              <- SSOT: オーケストレーション契約（共通）
CLAUDE.md                              <- Claude用薄いアダプタ（AGENTS.mdを参照）
CODEX.md                               <- Codex用薄いアダプタ（AGENTS.mdを参照）
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
  shared-orchestration-playbook.md     <- Codex/Claude共通ワークフロープレイブック
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
cp CODEX.md ~/.claude/CODEX.md
cp -r rules/ ~/.claude/rules/

# 3A. サブスク専用（推奨: 従量APIなし）
# - Codex / Claude CLI に事前ログインして実行
# - GitHub Actions で使う場合は self-hosted runner が必要（`FUGUE_SUBSCRIPTION_RUNNER_LABEL` 既定: `fugue-subscription`）

# 3B. API 実行を使う場合のみキー設定
export OPENAI_API_KEY="your-openai-key"
export GLM_API_KEY="your-glm-key"
export GLM_MODEL="glm-5.0" # optional (default in Tutti lanes is glm-5.0)
export GEMINI_API_KEY="your-gemini-key"
export XAI_API_KEY="your-xai-key" # optional (X/Twitter / realtime specialist)
export ANTHROPIC_API_KEY="your-anthropic-key" # optional (Claude assist lane)

# 3.5 GitHub Actions 用オーケストレータ切替（repo variable 優先）
# gh variable set FUGUE_MAIN_ORCHESTRATOR_PROVIDER   --body codex   -R <owner/repo>
# gh variable set FUGUE_ASSIST_ORCHESTRATOR_PROVIDER --body claude  -R <owner/repo>
# gh variable set FUGUE_CLAUDE_MAX_PLAN              --body true    -R <owner/repo>
# gh variable set FUGUE_CLAUDE_PLAN_TIER             --body max20   -R <owner/repo>
# gh variable set FUGUE_CI_EXECUTION_ENGINE          --body subscription -R <owner/repo> # harness|api|subscription
# gh variable set FUGUE_SUBSCRIPTION_RUNNER_LABEL    --body fugue-subscription -R <owner/repo> # subscription strictで必須とするrunner label
# gh variable set FUGUE_SUBSCRIPTION_CLI_TIMEOUT_SEC --body 180     -R <owner/repo> # per-lane timeout (seconds)
# gh variable set FUGUE_SUBSCRIPTION_OFFLINE_POLICY  --body hold    -R <owner/repo> # hold|continuity (subscriptionでrunner不在時)
# gh variable set FUGUE_CODEX_MAIN_MODEL             --body gpt-5.3-codex -R <owner/repo> # main orchestrator lane model
# gh variable set FUGUE_CODEX_MULTI_AGENT_MODEL      --body gpt-5.3-codex-spark -R <owner/repo> # non-main codex lanes model
# gh variable set FUGUE_STRICT_MAIN_CODEX_MODEL      --body true    -R <owner/repo> # require codex-main-orchestrator=gpt-5.3-codex
# gh variable set FUGUE_STRICT_OPUS_ASSIST_DIRECT    --body true    -R <owner/repo> # require claude-opus-assist=CLAUDE_OPUS_MODEL
# gh variable set FUGUE_API_STRICT_MODE              --body false   -R <owner/repo> # trueでharness/api時もstrict guardを維持
# gh variable set FUGUE_MULTI_AGENT_MODE             --body enhanced -R <owner/repo> # standard|enhanced|max
# gh variable set FUGUE_GLM_SUBAGENT_MODE            --body paired  -R <owner/repo> # off|paired|symphony (api/harness時GLM subagentファンアウト)
# gh variable set FUGUE_EMERGENCY_CONTINUITY_MODE    --body false   -R <owner/repo> # trueでin-flight issueのみ継続処理
# gh variable set FUGUE_EMERGENCY_ASSIST_POLICY      --body none    -R <owner/repo> # none|codex|claude (continuity時assist縮退先)
# gh variable set FUGUE_CLAUDE_MAIN_ASSIST_POLICY    --body codex   -R <owner/repo> # codex|none (main=claude時のassist自動調整)
# gh variable set FUGUE_CLAUDE_ROLE_POLICY           --body flex     -R <owner/repo> # sub-only|flex
# gh variable set FUGUE_CLAUDE_DEGRADED_ASSIST_POLICY --body claude -R <owner/repo> # none|codex|claude
# gh variable set FUGUE_CLAUDE_ASSIST_EXECUTION_POLICY --body hybrid -R <owner/repo> # direct|hybrid|proxy
# gh variable set FUGUE_CLAUDE_OPUS_MODEL            --body claude-opus-4-6 -R <owner/repo>
# gh variable set FUGUE_CLAUDE_SUB_AUTO_ESCALATE     --body high    -R <owner/repo> # off|high|medium-high
# gh variable set FUGUE_CLAUDE_SUB_AMBIGUITY_MIN_SCORE --body 90    -R <owner/repo> # 0-100 (translation gate score threshold)
# gh variable set FUGUE_IMPLEMENT_REFINEMENT_CYCLES  --body 3       -R <owner/repo> # default preflight loops before implement
# gh variable set FUGUE_IMPLEMENT_DIALOGUE_ROUNDS    --body 2       -R <owner/repo> # implementation dialogue rounds (default)
# gh variable set FUGUE_IMPLEMENT_DIALOGUE_ROUNDS_CLAUDE --body 1   -R <owner/repo> # implementation dialogue rounds when main=claude
# (legacy) gh variable set FUGUE_ORCHESTRATOR_PROVIDER --body codex -R <owner/repo>
# gh variable set FUGUE_CLAUDE_RATE_LIMIT_STATE --body ok        -R <owner/repo>
# gh variable set FUGUE_CLAUDE_RATE_LIMIT_STATE --body degraded  -R <owner/repo>
# gh variable set FUGUE_CLAUDE_RATE_LIMIT_STATE --body exhausted -R <owner/repo>
# issue意図に応じて Gemini/xAI specialist lane が自動追加されます
# NOTE: 既定では `FUGUE_CLAUDE_ROLE_POLICY=flex` で codex/claude main 切替を許可します。sub-only にすると mainのclaude指定は codex に自動降格します（force時除く）。
# NOTE: state が degraded のとき、assistのclaude指定は `FUGUE_CLAUDE_DEGRADED_ASSIST_POLICY` に従って縮退します（既定 claude）。
# NOTE: state が exhausted のとき、assistのclaude指定は none に自動フォールバックします。
# NOTE: `orchestrator provider` は役割（control-plane）、`FUGUE_CLAUDE_ASSIST_EXECUTION_POLICY` は Claude assist の実行経路（data-plane）です。
# NOTE: `direct` は Anthropic 直実行のみ、`hybrid` は Anthropic 未設定時に Codex proxy、`proxy` は常に Codex proxy を試行します。
# NOTE: assist既定は claude（co-orchestrator 常時有効）。
# NOTE: 曖昧性シグナルは `FUGUE_CLAUDE_SUB_AMBIGUITY_MIN_SCORE` 以上の高スコア時のみ昇格し、常時コンテキスト圧迫を避けます。
# NOTE: state が ok かつ assist=claude のとき、/vote に Claude assist レーンが参加します（subscription では Opus を常時優先）。
# NOTE: main orchestrator resolved結果に応じて main signal lane（codex/claude）が /vote に追加されます。
# NOTE: 互換既定では `FUGUE_CLAUDE_MAX_PLAN=true` のとき execution policy は `hybrid`、false のとき `direct` として扱います。
# NOTE: `FUGUE_CLAUDE_OPUS_MODEL` は claude-opus-assist/main の既定モデル指定に使われます。
# NOTE: /vote の実行可否は role-weighted 2/3 合議 + HIGH risk veto で判定されます。
# NOTE: implement 時は Plan→Parallel Simulation→Critical Review→Problem Fix→Replan を 3 サイクル完了後に実装します。
# NOTE: preflight通過後の実装フェーズでは Implementer/ Critic/ Integrator の対話ループを必須化しています。
# NOTE: 共有プレイブックに基づき、todo/lessons成果物（.fugue/pre-implement）を必須化しています。
# NOTE: 大規模リファクタ/リライト/移行タスクでは、各サイクルで Candidate A/B + Failure Modes + Rollback Check を必須化します。
# NOTE: `gha24` は大規模リファクタ語を検知すると `large-refactor` ラベルを自動付与し、上記必須セクションを強制します。
# NOTE: main=claude かつ assist=claude の重複は、rate limit 保護のため `FUGUE_CLAUDE_MAIN_ASSIST_POLICY` に従って assist を自動調整します（force時除く）。
# NOTE: modified FUGUE では通常運用時、main=claude は assist=codex へ最終調整されます（co-orchestrator維持 + Claude圧迫回避）。
# NOTE: `FUGUE_CI_EXECUTION_ENGINE=subscription` は pay-as-you-go APIを使わず、`codex` / `claude` CLI で /vote レーンを実行します（self-hosted runner前提）。
# NOTE: `FUGUE_CI_EXECUTION_ENGINE` の既定は `subscription` です。`harness/api` は互換用途です。
# NOTE: `subscription` 要求時は `FUGUE_SUBSCRIPTION_RUNNER_LABEL` が付いた self-hosted runner を必須判定します。
# NOTE: 上記ラベルを持つ runner が online でない場合、`FUGUE_SUBSCRIPTION_OFFLINE_POLICY` に従います。
# NOTE: `FUGUE_SUBSCRIPTION_OFFLINE_POLICY=hold`（既定）では処理を安全停止し、API縮退しません。
# NOTE: `FUGUE_SUBSCRIPTION_OFFLINE_POLICY=continuity` では `api-continuity` (harness) に縮退します。
# NOTE: `api-continuity` では strict guard は既定で無効化されます（`FUGUE_API_STRICT_MODE=true` で明示的に有効化可能）。
# NOTE: `FUGUE_EMERGENCY_CONTINUITY_MODE=true` のとき、新規 issue は処理せず `processing` 付き in-flight issue のみ継続します。
# NOTE: continuity中に assist=claude は `FUGUE_EMERGENCY_ASSIST_POLICY` へ縮退（既定 none）し、Opus direct未構成でのfail連鎖を防ぎます。
# NOTE: `FUGUE_MULTI_AGENT_MODE=enhanced|max` で /vote の合議レーンを段階的に増やせます。
# NOTE: `FUGUE_CODEX_MAIN_MODEL` と `FUGUE_CODEX_MULTI_AGENT_MODEL` を分離すると、mainは `gpt-5.3-codex` 固定のまま multi-agent を `gpt-5.3-codex-spark` に寄せられます。
# NOTE: `FUGUE_GLM_SUBAGENT_MODE=paired|symphony` で GLM subagent レーン（orchestration/architect/plan/reliability）を段階的に増やせます（subscriptionでは自動off）。
# NOTE: 自然文/モバイル経路はデフォルト `review`。`implement` は明示指定時のみ付与されます。
# NOTE: 実装実行には `implement` に加えて `implement-confirmed` ラベルが必須です。
# NOTE: 明示モード指定がない場合、/vote の multi-agent mode はタスク複雑度ヒューリスティックで自動調整されます（軽量=standard寄り）。
# NOTE: `risk-tier (low|medium|high)` を算出し、preflight/dialogue最小値と review fan-out を調整します。
# NOTE: lessons 更新は correction/postmortem シグナル時に必須、それ以外は SHOULD 扱いです。
# NOTE: コンテキスト探索は staged budget（low:4->8, medium:6->12, high:8->16）で段階拡張します。
# NOTE: `gha24` が事前フォールバックした場合は、Issueに監査コメントが自動投稿されます。
# NOTE: `fugue-watchdog` は Claude state を自動復帰（degraded/exhausted -> ok）できますが、cooldown + 安定性条件を満たす場合のみ実行されます。
# NOTE: `fugue-orchestrator-canary` が毎日、実Issueベースで regular/force の切替E2Eを自動検証します。
# NOTE: `fugue-orchestration-weekly-review` が週次で assist昇格率と high-risk時の昇格カバレッジを status issue に投稿します。

# 3.6 gha24 でリクエスト単位に上書き（任意）
# gha24 "完遂: API障害対応" --implement --orchestrator claude
# gha24 "完遂: API障害対応" --implement --orchestrator codex --assist-orchestrator claude
# gha24 "完遂: API障害対応" --implement --orchestrator claude --force-claude
# NOTE: `gha24` はデフォルト implement。レビューのみは `--review` か `レビューのみ` 指示で明示します。
# あるいは:
# GHA24_ORCHESTRATOR_PROVIDER=claude gha24 "完遂: API障害対応" --implement

# 3.7 Orchestrator切替シミュレーション（ローカル・非破壊）
# ./scripts/sim-orchestrator-switch.sh | column -t -s $'\t'

# 3.8 GHAなしローカル直実行（Codex main + Claude assist + GLM並走）
# CODEX_MAIN_MODEL=gpt-5.3-codex CODEX_MULTI_AGENT_MODEL=gpt-5.3-codex-spark \
#   ./scripts/local/run-local-orchestration.sh --issue 176 --repo cursorvers/fugue-orchestrator --mode enhanced --glm-mode paired --max-parallel 4
# NOTE: codex/claude は CLI 実行、glm は API 実行。実行結果は .fugue/local-run 配下に保存されます。
# NOTE: `FUGUE_LOCAL_REQUIRE_CLAUDE_ASSIST=true`（既定）かつ `FUGUE_CLAUDE_RATE_LIMIT_STATE=ok` のとき、
#       `claude-opus-assist` の direct success が無ければ `ok_to_execute=false` になります。
# NOTE: Claude rate limit 時は `FUGUE_CLAUDE_RATE_LIMIT_STATE=degraded|exhausted` を設定すると、
#       上記必須ゲートは `not-required` に切り替わります。

# 3.9 FUGUE有用スキル同期（Codex/Claude 共通）
# required プロファイルのみ同期
# ./scripts/skills/sync-openclaw-skills.sh --target both
# optional まで含める
# ./scripts/skills/sync-openclaw-skills.sh --target both --with-optional
# dry-run（差分確認）
# ./scripts/skills/sync-openclaw-skills.sh --target both --with-optional --dry-run
# NOTE: third-party skills は pin SHA 取得 + ブロックリスト検査 + managed marker で保護

# Note:
# `orchestrator provider` は Tutti のレーン選択プロファイルです（実装エンジン切替ではありません）。
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

## FUGUE Skills Profile

Orchestrator切替（Codex/Claude）時も同一能力を維持するため、FUGUE有用スキルは
共有マニフェストから同期する運用を採用します。

- Profile: `docs/fugue-skills-profile.md`
- Manifest: `config/skills/fugue-openclaw-baseline.tsv`
- Sync script: `scripts/skills/sync-openclaw-skills.sh`

## Shared Workflow Playbook

「CLAUDE.mdベストプラクティス」をCodex/Claude共通で使うため、provider-agnosticな運用基準を定義しています。

- Playbook: `rules/shared-orchestration-playbook.md`
- 実装Workflowで強制する成果物:
  - `.fugue/pre-implement/issue-<N>-todo.md`
  - `.fugue/pre-implement/lessons.md`

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
