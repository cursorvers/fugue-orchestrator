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
# gh variable set FUGUE_ALLOW_GLM_IN_SUBSCRIPTION    --body true    -R <owner/repo> # trueでsubscriptionでもGLM baseline voter(+design時Gemini)を許可
# gh variable set FUGUE_SUBSCRIPTION_RUNNER_LABEL    --body fugue-subscription -R <owner/repo> # subscription strictで必須とするrunner label
# gh variable set FUGUE_SUBSCRIPTION_CLI_TIMEOUT_SEC --body 180     -R <owner/repo> # per-lane timeout (seconds)
# gh variable set FUGUE_SUBSCRIPTION_OFFLINE_POLICY  --body continuity -R <owner/repo> # hold|continuity (subscriptionでrunner不在時)
# gh variable set FUGUE_CANARY_OFFLINE_POLICY_OVERRIDE --body continuity -R <owner/repo> # inherit|hold|continuity (canary専用: runner不在時の扱い)
# gh variable set FUGUE_CANARY_LABEL_WAIT_ATTEMPTS   --body 10      -R <owner/repo> # canary issue label反映待機リトライ回数
# gh variable set FUGUE_CANARY_LABEL_WAIT_SLEEP_SEC  --body 2       -R <owner/repo> # canary issue label反映待機秒
# gh variable set FUGUE_CANARY_WAIT_FAST_ATTEMPTS    --body 12      -R <owner/repo> # canary統合コメント待機(高速フェーズ)試行回数
# gh variable set FUGUE_CANARY_WAIT_FAST_SLEEP_SEC   --body 10      -R <owner/repo> # canary統合コメント待機(高速フェーズ)秒
# gh variable set FUGUE_CANARY_WAIT_SLOW_ATTEMPTS    --body 9       -R <owner/repo> # canary統合コメント待機(保守フェーズ)試行回数
# gh variable set FUGUE_CANARY_WAIT_SLOW_SLEEP_SEC   --body 20      -R <owner/repo> # canary統合コメント待機(保守フェーズ)秒
# gh variable set FUGUE_DUAL_MAIN_SIGNAL             --body true    -R <owner/repo> # trueで codex-main / claude-main signal lane を両建て
# gh variable set FUGUE_CODEX_MAIN_MODEL             --body gpt-5-codex -R <owner/repo> # main orchestrator lane model
# gh variable set FUGUE_CODEX_MULTI_AGENT_MODEL      --body gpt-5.3-codex-spark -R <owner/repo> # non-main codex lanes model
# gh variable set FUGUE_STRICT_MAIN_CODEX_MODEL      --body false   -R <owner/repo> # trueで codex-main-orchestrator=gpt-5-codex を厳格要求
# gh variable set FUGUE_STRICT_OPUS_ASSIST_DIRECT    --body false   -R <owner/repo> # trueで claude-opus-assist=CLAUDE_OPUS_MODEL を厳格要求
# gh variable set FUGUE_REQUIRE_DIRECT_CLAUDE_ASSIST --body false   -R <owner/repo> # trueで /vote 時に claude-opus-assist direct success を必須化
# gh variable set FUGUE_REQUIRE_CLAUDE_SUB_ON_COMPLEX --body true   -R <owner/repo> # trueで assist=claude かつ high-risk/ambiguity タスク時に claude sub gate を必須化
# gh variable set FUGUE_REQUIRE_BASELINE_TRIO       --body true    -R <owner/repo> # trueで codex+claude+glm の成功参加を必須化
# gh variable set FUGUE_MIN_CONSENSUS_LANES          --body 6       -R <owner/repo> # integer >=6 (resolved lane count floor; underflow is fail-fast)
# gh variable set FUGUE_API_STRICT_MODE              --body false   -R <owner/repo> # trueでharness/api時もstrict guardを維持
# gh variable set FUGUE_MULTI_AGENT_MODE             --body enhanced -R <owner/repo> # standard|enhanced|max
# gh variable set FUGUE_GLM_SUBAGENT_MODE            --body paired  -R <owner/repo> # off|paired|symphony (api/harness時GLM subagentファンアウト)
# gh variable set FUGUE_CODEX_RECURSIVE_DELEGATION   --body false   -R <owner/repo> # trueで codex laneに再帰委譲(parent->child->grandchild)を有効化
# gh variable set FUGUE_CODEX_RECURSIVE_MAX_DEPTH    --body 3       -R <owner/repo> # >=2, 推奨3
# gh variable set FUGUE_CODEX_RECURSIVE_TARGET_LANES --body "codex-main-orchestrator,codex-orchestration-assist" -R <owner/repo> # CSV or all
# gh variable set FUGUE_CODEX_RECURSIVE_DRY_RUN      --body false   -R <owner/repo> # trueで再帰委譲を合成結果で検証
# gh variable set FUGUE_EMERGENCY_CONTINUITY_MODE    --body false   -R <owner/repo> # trueでin-flight issueのみ継続処理
# gh variable set FUGUE_EMERGENCY_ASSIST_POLICY      --body none    -R <owner/repo> # none|codex|claude (continuity時assist縮退先)
# gh variable set FUGUE_CLAUDE_MAIN_ASSIST_POLICY    --body codex   -R <owner/repo> # codex|none (main=claude時のassist自動調整)
# gh variable set FUGUE_CLAUDE_ROLE_POLICY           --body flex     -R <owner/repo> # sub-only|flex
# gh variable set FUGUE_CLAUDE_DEGRADED_ASSIST_POLICY --body claude -R <owner/repo> # none|codex|claude
# gh variable set FUGUE_CLAUDE_ASSIST_EXECUTION_POLICY --body hybrid -R <owner/repo> # direct|hybrid|proxy
# gh variable set FUGUE_CLAUDE_OPUS_MODEL            --body claude-sonnet-4-6 -R <owner/repo> # default assist model (compat var name)
# gh variable set FUGUE_CLAUDE_SONNET4_MODEL         --body claude-sonnet-4-6 -R <owner/repo> # keep non-subscription assist lanes on Sonnet 4.6 only
# gh variable set FUGUE_CLAUDE_SONNET6_MODEL         --body claude-sonnet-4-6 -R <owner/repo> # keep non-subscription assist lanes on Sonnet 4.6 only
# gh variable set FUGUE_GEMINI_MODEL                 --body gemini-3.1-pro -R <owner/repo> # Gemini primary latest lane
# gh variable set FUGUE_GEMINI_FALLBACK_MODEL        --body gemini-3-flash -R <owner/repo> # Gemini fallback lane
# gh variable set FUGUE_XAI_MODEL                    --body grok-4 -R <owner/repo> # xAI latest lane
# gh variable set FUGUE_CLAUDE_SUB_AUTO_ESCALATE     --body high    -R <owner/repo> # off|high|medium-high
# gh variable set FUGUE_CLAUDE_SUB_AMBIGUITY_MIN_SCORE --body 90    -R <owner/repo> # 0-100 (translation gate score threshold)
# gh variable set FUGUE_IMPLEMENT_REFINEMENT_CYCLES  --body 3       -R <owner/repo> # default preflight loops before implement
# gh variable set FUGUE_IMPLEMENT_DIALOGUE_ROUNDS    --body 2       -R <owner/repo> # implementation dialogue rounds (default)
# gh variable set FUGUE_IMPLEMENT_DIALOGUE_ROUNDS_CLAUDE --body 1   -R <owner/repo> # implementation dialogue rounds when main=claude
# gh variable set FUGUE_PREFLIGHT_PARALLEL_ENABLED   --body true    -R <owner/repo> # research/plan/critic preflight nodes in parallel
# gh variable set FUGUE_PREFLIGHT_PARALLEL_TIMEOUT_SEC --body 240   -R <owner/repo> # timeout per preflight node (seconds)
# gh variable set FUGUE_CONTEXT_BUDGET_MIN_INITIAL   --body 6       -R <owner/repo> # over-compression guard initial floor (hard floor >=6)
# gh variable set FUGUE_CONTEXT_BUDGET_MIN_MAX       --body 12      -R <owner/repo> # over-compression guard max floor (hard floor >=12)
# gh variable set FUGUE_CONTEXT_BUDGET_MIN_SPAN      --body 6       -R <owner/repo> # over-compression guard expansion floor (hard floor >=4)
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
# NOTE: state が ok かつ assist=claude のとき、/vote に Claude assist レーンが参加します（subscription では `FUGUE_CLAUDE_OPUS_MODEL` 既定: Sonnet 4.6）。
# NOTE: main orchestrator resolved結果に応じて main signal lane（codex/claude）が /vote に追加されます。
# NOTE: `FUGUE_DUAL_MAIN_SIGNAL=true`（既定）では、resolved main に加えて反対側の main signal lane も同時投入します（例: main=codex でも claude-main-orchestrator を追加）。
# NOTE: 互換既定では `FUGUE_CLAUDE_MAX_PLAN=true` のとき execution policy は `hybrid`、false のとき `direct` として扱います。
# NOTE: `FUGUE_CLAUDE_OPUS_MODEL` は claude-opus-assist/main の既定モデル指定に使われます。
# NOTE: /vote の実行可否は role-weighted 2/3 合議 + HIGH risk veto で判定されます。
# NOTE: `FUGUE_MIN_CONSENSUS_LANES`（既定6）は lane数の下限ガードです。解決された lane 数が下回る場合は fail-fast で停止します。
# NOTE: implement 時は Plan→Parallel Simulation→Critical Review→Problem Fix→Replan を 3 サイクル完了後に実装します。
# NOTE: preflight通過後の実装フェーズでは Implementer/ Critic/ Integrator の対話ループを必須化しています。
# NOTE: `fugue-codex-implement` は実装前に research/plan/critic ノードを並列起動し、`.fugue/pre-implement` の seed artifact を先に生成します。
# NOTE: 共有プレイブックに基づき、todo/lessons成果物（.fugue/pre-implement）を必須化しています。
# NOTE: 大規模リファクタ/リライト/移行タスクでは、各サイクルで Candidate A/B + Failure Modes + Rollback Check を必須化します。
# NOTE: `gha24` は大規模リファクタ語を検知すると `large-refactor` ラベルを自動付与し、上記必須セクションを強制します。
# NOTE: main=claude かつ assist=claude の重複は、rate limit 保護のため `FUGUE_CLAUDE_MAIN_ASSIST_POLICY` に従って assist を自動調整します（force時除く）。
# NOTE: modified FUGUE では通常運用時、main=claude は assist=codex へ最終調整されます（co-orchestrator維持 + Claude圧迫回避）。
# NOTE: `FUGUE_CI_EXECUTION_ENGINE=subscription` は `codex` / `claude` をCLIで実行します（self-hosted runner前提）。
# NOTE: `FUGUE_ALLOW_GLM_IN_SUBSCRIPTION=true`（既定）では、subscriptionでも GLM baseline voter をAPI実行し、デザイン系タスクではGemini specialist laneを追加できます。
# NOTE: `FUGUE_CI_EXECUTION_ENGINE` の既定は `subscription` です。`harness/api` は互換用途です。
# NOTE: `subscription` 要求時は `FUGUE_SUBSCRIPTION_RUNNER_LABEL` が付いた self-hosted runner を必須判定します。
# NOTE: 上記ラベルを持つ runner が online でない場合、`FUGUE_SUBSCRIPTION_OFFLINE_POLICY` に従います。
# NOTE: 既定は `FUGUE_SUBSCRIPTION_OFFLINE_POLICY=continuity` で、runner不在時は `api-continuity` (harness) に縮退します。
# NOTE: `FUGUE_SUBSCRIPTION_OFFLINE_POLICY=hold` を指定すると処理を安全停止し、API縮退しません。
# NOTE: `api-continuity` では strict guard は既定で無効化されます（`FUGUE_API_STRICT_MODE=true` で明示的に有効化可能）。
# NOTE: `FUGUE_REQUIRE_DIRECT_CLAUDE_ASSIST=true` のときのみ、/vote で `claude-opus-assist` の direct success を必須化します（既定は非必須）。
# NOTE: `FUGUE_REQUIRE_CLAUDE_SUB_ON_COMPLEX=true`（既定）では、assist=claude かつ `risk_tier=high` または ambiguity translation-gate=true のタスクで claude-opus-assist 成功を必須化します。未達時は `ok_to_execute=false` になります。
# NOTE: `FUGUE_REQUIRE_BASELINE_TRIO=true`（既定）では、codex+claude+glm の成功参加が揃わない限り `ok_to_execute=false` になります。
# NOTE: `FUGUE_EMERGENCY_CONTINUITY_MODE=true` のとき、新規 issue は処理せず `processing` 付き in-flight issue のみ継続します。
# NOTE: continuity中に assist=claude は `FUGUE_EMERGENCY_ASSIST_POLICY` へ縮退（既定 none）し、Opus direct未構成でのfail連鎖を防ぎます。
# NOTE: `FUGUE_MULTI_AGENT_MODE=enhanced|max` で /vote の合議レーンを段階的に増やせます。
# NOTE: `FUGUE_CODEX_MAIN_MODEL` と `FUGUE_CODEX_MULTI_AGENT_MODEL` を分離すると、mainは `gpt-5-codex` 固定のまま multi-agent を `gpt-5.3-codex-spark` に寄せられます。
# NOTE: `FUGUE_GLM_SUBAGENT_MODE=paired|symphony` で GLM subagent レーン（orchestration/architect/plan/reliability）を段階的に増やせます（`FUGUE_ALLOW_GLM_IN_SUBSCRIPTION=false` の場合のみ subscription で自動off）。
# NOTE: `FUGUE_CODEX_RECURSIVE_DELEGATION=true` のとき、target lane で codex recursive delegation（parent->child->grandchild）を有効化します。
# NOTE: main=claude でも assist=codex かつ `FUGUE_CODEX_RECURSIVE_TARGET_LANES` に `codex-orchestration-assist` を含めれば同モードが発動します。
# NOTE: 自然文/モバイル経路はデフォルト `review`。`implement` は明示指定時のみ付与されます。
# NOTE: plain issue の `opened` は intake-only です。mainframe 実行開始点は `/vote`、明示的な `tutti` label、または `workflow_dispatch` に限定します。`issues:labeled` では `tutti` 以外の label churn は caller 入口で無視します。
# NOTE: 通常経路では実装実行に `implement` + `implement-confirmed` が必要です。`/vote` 経由は review-only 明示がない限り `implement-confirmed` を自動付与します。
# NOTE: `/vote` は `fugue-task` ラベル未付与 issue でも mainframe handoff を強制し、合議実行を開始します。ただし trust bypass は使わず、router 側の trusted 判定を通る経路だけが実行を継続します。
# NOTE: `FUGUE_GHA_EXECUTION_MODE=record-only` のとき、GitHub mainframe は handoff/audit 記録のみ行い、Tutti / implementation lane は走りません。強制的に GitHub-hosted 実行へ切り替える場合は `fugue-tutti-caller.yml` を `execution_mode_override=primary` または `backup-heavy` 付きで直接 dispatch します。
# NOTE: 明示モード指定がない場合、/vote の multi-agent mode はタスク複雑度ヒューリスティックで自動調整されます（軽量=standard寄り）。
# NOTE: `risk-tier (low|medium|high)` を算出し、preflight/dialogue最小値と review fan-out を調整します。
# NOTE: local 実行でも `FUGUE_LOCAL_REQUIRE_CLAUDE_ASSIST_ON_COMPLEX=true`（既定）により assist=claude かつ high-risk（または `FUGUE_LOCAL_AMBIGUITY_SIGNAL=true`）時に claude-opus-assist 成功が必須になります。
# NOTE: lessons 更新は correction/postmortem シグナル時に必須、それ以外は SHOULD 扱いです。
# NOTE: コンテキスト探索は staged budget（low:6->12, medium:8->16, high:10->20）で段階拡張します。
# NOTE: `workflow-risk-policy.sh` が over-compression guard を常時適用し、floor/span 未満なら自動補正します。
# NOTE: `gha24` が事前フォールバックした場合は、Issueに監査コメントが自動投稿されます。
# NOTE: `fugue-watchdog` は Claude state を自動復帰（degraded/exhausted -> ok）できますが、cooldown + 安定性条件を満たす場合のみ実行されます。
# NOTE: `fugue-orchestration-gate` が PR で Fast Gate（syntax/yaml/parity/sim）を同期実行し、main push で canary-lite（regularのみ）を同期実行します。
# NOTE: `fugue-orchestrator-canary` は full canary（regular+force）の定期検証です。`workflow_dispatch` では `canary_mode=full|lite` を選択できます。
# NOTE: canaryは既定で `FUGUE_CANARY_OFFLINE_POLICY_OVERRIDE=continuity` として、subscription runner 不在でも検証継続します（`hold` または `inherit` で従来どおりスキップ可能）。
# NOTE: canaryは regular/force ケースの統合コメント待機を並列化し、待機上限は fast/slow 2段（上記 `FUGUE_CANARY_WAIT_*`）で調整できます。
# NOTE: `fugue-orchestration-weekly-review` が週次で assist昇格率と high-risk時の昇格カバレッジを status issue に投稿します。

# 3.6 gha24 でリクエスト単位に上書き（任意）
# gha24 "完遂: API障害対応" --implement --orchestrator claude
# gha24 "完遂: API障害対応" --implement --orchestrator codex --assist-orchestrator claude
# gha24 "完遂: API障害対応" --implement --orchestrator claude --force-claude
# gha24 "完遂: API障害対応" --local-run   # issue作成直後にローカル本実行を強制
# NOTE: `gha24` はデフォルト implement。レビューのみは `--review` か `レビューのみ` 指示で明示します。
# NOTE: `gha24` は `GHA24_LOCAL_RUN_MODE=force`（既定）で、issue作成後に
#       `scripts/local/run-local-orchestration.sh` を自動起動します（ローカル主運用）。
# NOTE: GHAのみで動かしたいときは `--gha-only` か `GHA24_LOCAL_RUN_MODE=off` を指定します（例: 就寝時）。
# NOTE: フラグなしでも、タスク文に「ローカルで実行」「ローカル優先」「GHA使わない」を含めると local-run 強制、
#       「GHAのみ」「ローカル実行しない」を含めると GHA-only に自動解釈します。
# NOTE: フラグなしでも、タスク文に「メインはclaude」「assistはcodex/claude/none」を含めると
#       orchestrator/assist override に自動解釈します。
# 例:
#   gha24 "この修正、メインはcodex、assistはclaudeでローカル実行"
#   gha24 "寝るのでGHAのみで回して。assistはnone"
# あるいは:
# GHA24_ORCHESTRATOR_PROVIDER=claude gha24 "完遂: API障害対応" --implement

# 3.7 Orchestrator切替シミュレーション（ローカル・非破壊）
# ./scripts/sim-orchestrator-switch.sh | column -t -s $'\t'
# NOTE: シミュレーションは `FUGUE_SIM_CODEX_SPARK_ONLY=true`（既定）で codex-main/codex multi-agent を `gpt-5.3-codex-spark` に統一し高速化します。
# NOTE: `gpt-5-codex` との厳密差分検証が必要な場合のみ `FUGUE_SIM_CODEX_SPARK_ONLY=false` を指定してください。
# NOTE: lane構成のSSOTは `scripts/lib/build-agent-matrix.sh` です。
# NOTE: ドリフト検知は `./scripts/check-agent-matrix-parity.sh` で実行できます。

# 3.8 GHAなしローカル直実行（Codex main + Claude assist + GLM並走）
# CODEX_MAIN_MODEL=gpt-5-codex CODEX_MULTI_AGENT_MODEL=gpt-5.3-codex-spark \
#   ./scripts/local/run-local-orchestration.sh --issue 176 --repo cursorvers/fugue-orchestrator --mode enhanced --glm-mode paired --max-parallel 4
# NOTE: codex/claude は CLI 実行、glm は API 実行。実行結果は .fugue/local-run 配下に保存されます。
# NOTE: `FUGUE_PRIMARY_HEARTBEAT_MODE=auto`（既定）では、gh が使えると実行開始/終了時に primary heartbeat を更新します。
# NOTE: mac mini 24h 運用では `~/Library/LaunchAgents/com.cursorvers.fugue-primary-heartbeat.plist`
#       を常駐させるのが正式手順です。下記 loop は ad-hoc な shell 実行や cron 用の補助経路です。
#   ./scripts/local/run-primary-heartbeat-loop.sh --repo cursorvers/fugue-orchestrator --interval 60
# NOTE: launchd heartbeat を再初期化する場合は bootstrap helper を実行してください。
#   ./scripts/local/bootstrap-primary-heartbeat-agent.sh --repo cursorvers/fugue-orchestrator
# NOTE: ログイン時の自動復旧が必要なら `~/Library/LaunchAgents/com.cursorvers.fugue-primary-heartbeat-bootstrap.plist`
#       を load しておくと、上記 helper が login 時に自動実行されます。
# NOTE: 可能なら repo-scoped の fine-grained PAT を `FUGUE_HEARTBEAT_GH_TOKEN` に入れてから上記 helper を実行してください。
#       未指定時は各 heartbeat process が `gh auth token` を使って個別に認証します。
# NOTE: login bootstrap plist を使わない場合は、再ログイン/再起動後に上記 helper を再実行してください。
# NOTE: heartbeat は repo variables `FUGUE_PRIMARY_HEARTBEAT_*` に記録され、`fugue-watchdog` は fresh heartbeat を primary 判定の主信号として使います。
# NOTE: 現在の warm-standby 到達点と `/vote` 検証結果は
#       `docs/kernel-macmini-warm-standby-status-2026-03-08.md` を参照してください。
# NOTE: `FUGUE_LOCAL_REQUIRE_CLAUDE_ASSIST=true` のときのみ、`FUGUE_CLAUDE_RATE_LIMIT_STATE=ok` で
#       `claude-opus-assist` の direct success が無ければ `ok_to_execute=false` になります。
# NOTE: Claude rate limit 時は `FUGUE_CLAUDE_RATE_LIMIT_STATE=degraded|exhausted` を設定すると、
#       上記必須ゲートは `not-required` に切り替わります。
# NOTE: `FUGUE_CLAUDE_SESSION_HANDOFF=true`（既定）で Claude lane の `session_id` を保存します。
#       直近 run の引き継ぎ確認は `./scripts/local/claude-handoff-summary.sh`。
# NOTE: assistモデルは Sonnet 4.6固定（`FUGUE_CLAUDE_OPUS_MODEL=claude-sonnet-4-6`）。
# NOTE: model policy (latest track): Claude=Sonnet 4.6 only / GLM=5.0 only / Gemini=3.1-pro(primary)+3-flash(fallback) / xAI=Grok 4 family.
# NOTE: `scripts/lib/model-policy.sh` が実行時に上記トラックへ自動正規化します（古い指定値は補正）。

# 3.8b 外部システム連結（自動動画 / note半自動 / Obsidian音声AI）
# 連結システムのみを並列スモーク実行:
#   ./scripts/local/run-linked-systems.sh --issue 176 --mode smoke --systems all --max-parallel 3
# 本体オーケストレーション完了後に連結システムを自動実行:
#   ./scripts/local/run-local-orchestration.sh --issue 176 --mode enhanced --glm-mode paired \
#     --with-linked-systems --linked-mode smoke --linked-systems all --linked-max-parallel 3
# NOTE: 連結定義は `config/integrations/local-systems.json`。
# NOTE: 既定の連結には `discord-notify` / `line-notify` も含まれます（通知設定未投入時は `execute` で失敗）。
# NOTE: Discord: `DISCORD_NOTIFY_WEBHOOK_URL`（fallback: `DISCORD_WEBHOOK_URL` / `DISCORD_SYSTEM_WEBHOOK`）
# NOTE: LINE: `LINE_WEBHOOK_URL` または `LINE_CHANNEL_ACCESS_TOKEN` + `LINE_TO`（legacy fallback: `LINE_NOTIFY_TOKEN` / `LINE_NOTIFY_ACCESS_TOKEN`）
# NOTE: line-notify は重複送信抑止と失敗クールダウンを標準有効化しています（`LINE_NOTIFY_GUARD_ENABLED=true`）。
# NOTE: ガード状態は `LINE_NOTIFY_GUARD_FILE`（既定: `.fugue/state/line-notify-guard.json`）に永続化されます。
# NOTE: 抑止窓は `LINE_NOTIFY_DEDUP_TTL_SECONDS` / `LINE_NOTIFY_FAILURE_COOLDOWN_SECONDS` で調整できます。
# NOTE: `LINE_NOTIFY_PREFER_PUSH=true` で、Push API資格情報がある場合は webhook より push を優先します。
# NOTE: timeout/5xx の一時障害は `LINE_NOTIFY_RETRY_MAX_ATTEMPTS` / `LINE_NOTIFY_RETRY_BASE_SECONDS` / `LINE_NOTIFY_RETRY_MAX_BACKOFF_SECONDS` で再試行できます。
# NOTE: `LINE_NOTIFY_TRACE_ID` で通知相関IDを固定できます（未指定時は自動生成）。
# NOTE: `--linked-mode execute` は本体の `ok_to_execute=true` のときのみ起動します。
# NOTE: Obsidian音声AIのdry-run文字起こしは `OBSIDIAN_AUDIO_ENABLE_TRANSCRIBE=true` で有効化します。
# NOTE: 連結定義の整合検証は `./scripts/check-linked-systems-integrity.sh`。

# 3.9 FUGUE有用スキル同期（Codex/Claude 共通）
# required プロファイルのみ同期
# ./scripts/skills/sync-openclaw-skills.sh --target both
# optional まで含める
# ./scripts/skills/sync-openclaw-skills.sh --target both --with-optional
# dry-run（差分確認）
# ./scripts/skills/sync-openclaw-skills.sh --target both --with-optional --dry-run
# NOTE: third-party skills は pin SHA 取得 + ブロックリスト検査 + managed marker で保護

# 3.10 Google Workspace skills + CLI 同期（Codex/Claude 共通）
# npm install -g @googleworkspace/cli
# ./scripts/skills/sync-googleworkspace-skills.sh --target both
# ./scripts/skills/sync-googleworkspace-skills.sh --target both --with-optional
# NOTE: Google Workspace は MCP 常用ではなく skills + CLI を第一選択にする

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
- Google Workspace profile: `docs/googleworkspace-skills-profile.md`
- Google Workspace Kernel design: `docs/kernel-googleworkspace-integration-design.md`
- Google Workspace manifest: `config/skills/googleworkspace-cli-baseline.tsv`
- Google Workspace Kernel policy: `config/integrations/googleworkspace-kernel-policy.json`
- Google Workspace sync: `scripts/skills/sync-googleworkspace-skills.sh`

## Shared Workflow Playbook

「CLAUDE.mdベストプラクティス」をCodex/Claude共通で使うため、provider-agnosticな運用基準を定義しています。

- Playbook: `rules/shared-orchestration-playbook.md`
- 実装Workflowで強制する成果物:
  - `.fugue/pre-implement/issue-<N>-research.md`
  - `.fugue/pre-implement/issue-<N>-plan.md`
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

## v3.0 新機能 (2026-03)

### Lane Bridge (`fugue-lane-bridge.mjs`)

統一ディスパッチ層。Provider state tracking, failover chain, diversity enforcement を提供。

```bash
# 単一レーン実行
node fugue-lane-bridge.mjs --lane codex:architect --task "..." --project /path

# マトリクス並列実行
node fugue-lane-bridge.mjs --matrix matrix.json

# 事前検証 (diversity violation → exit 2)
node fugue-lane-bridge.mjs --validate matrix.json

# 運用ダッシュボード (provider/agent 統計, p95 レイテンシ)
node fugue-lane-bridge.mjs --dashboard --days 7
```

### Structured Execution (`fugue-execute.mjs`)

9ステップの自律実行フロー: 分類 → Tier判定 → 要件定義 → 計画 → シミュレーション → 実装 → レビュー → 統合 → 記録。

```bash
node fugue-execute.mjs --task "description" --project /path --tier auto
node fugue-execute.mjs --dry-run --task "fix typo" --tier 0  # テスト用
node fugue-execute.mjs --resume <run-id>
node fugue-execute.mjs --dashboard  # via bridge
```

| Tier | 内容 | Review |
|------|------|--------|
| 0-2 | 自動実行、review skip | なし |
| 3+ | plan → simulate → implement → review cycle | GLM auto-review + Codex code-review |

### Guard Enforcement (`lane-guard.json` v2)

```json
{
  "validation": {
    "pre_dispatch_check": true,
    "hard_block_on_diversity_violation": true,
    "exit_code_on_block": 2
  }
}
```

- `--validate`: マトリクスの diversity / schema / phase-evidence を事前検証
- Diversity violation → exit 2 (hard block)
- `role_weights`: security-analyst (2.0x), architect (1.5x) で合議投票を加重

### Observability

- `--dashboard`: provider 別成功率, 平均/p95 レイテンシ, agent 別統計
- `lane-runs.jsonl`: 全 lane 実行のストリーム記録
- `phase-evidence.jsonl`: plan/simulate/critique の証跡

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

## Kernel Contract Notes

- repo root で新規に開いた Codex セッションから `/kernel`
- chat 欄から 1語で起動したい場合の local alias は `/k`
- ローカルでの推奨実行経路は `kernel` または `codex-prompt-launch kernel`
- 1語 alias の prompt は [`.codex/prompts/k.md`](/Users/masayuki_otawara/fugue-orchestrator/.codex/prompts/k.md)
- ローカル実行契約の authority は shell wrapper ではなく `codex-kernel-guard launch`
- hot reload は保証しません
- bare `/kernel` は Codex chat UI の upstream 実装に依存
- RUN_CODEX_KERNEL_SMOKE=1 bash tests/test-codex-kernel-prompt.sh
- この repo では非自明な要件定義 / 計画 / 実装 / レビューを Kernel work として扱い、plain Codex-only work に落とさない
- 最低 6 本の active lane
- 6 列以上の並列を最低形
- normal minimum shape は `codex` + `glm` + `specialist`
- `codex` は sovereign なので代替不可
- `gemini-cli` / `cursor-cli` / `copilot-cli` は free-tier or quota-limited な specialist 候補
- normal minimum shape では specialist 1本が必須。1本も確保できない場合は fail-closed
- optional specialist は固定優先順を持たず、quota と可用性が最も健全なものを動的に選ぶ
- `kernel-optional-lane-exec.sh auto ...` はその動的選択を使う
- `copilot-cli` は scarce な free-tier 月次予算として one-shot 限定で扱う
- optional specialist は通常 `kgemini` / `kcursor` / `kcopilot` 経由で使い、手動計上は `codex-kernel-guard budget-consume` を使う
- GLM は通常 `kglm` 経由で実行し、failure / recovery を run state に反映する
- `glm` が同一 run で2回失敗したら `degraded-allowed` に入り、`codex + specialist + specialist` で継続しつつ `glm` 復旧 lane を並行で回す
- 計画段階では `glm` と specialist pool（`gemini-cli` / `cursor-cli` / `copilot-cli`）を明示的に織り込む
- Codex 側の simulation レーンは、利用可能なら dedicated な 1 列だけを `gpt-5.3-codex-spark` で走らせる
- 他の Codex-family subagent は役割別に選び、全部を `gpt-5.3-codex-spark` に固定しない
- 要件凍結後は routine な中間報告を出さず、`BLOCKED` / 外部承認待ち / 明示要求 / 最終完了 の時だけ報告する
- 進行中の依頼に対して、部分マイルストーンや途中スライスの総括で処理を止めない
- 1つの stage / track / 実装スライスが終わっただけでは止まらず、凍結済みの依頼全体が終わるまで続ける
- 完了調の総括は、その依頼が本当に完了した時か、真に blocked の時だけにする
- `degraded-allowed` は run 単位。`codex-kernel-guard launch` は `KERNEL_RUN_ID` 未指定時に新しい run id を払い出す
- `codex-kernel-guard doctor` は active run を `updated_at` 降順で表示する
- `codex-kernel-guard doctor --all-runs` は stale run を含む read-only 一覧を出す
- `codex-kernel-guard doctor --run <run_id>` は bounded run detail を出す
- `codex-kernel-guard recover-run <run_id>` は compact artifact から heavy-profile tmux session を再生成する
- `1 tmux session = 1 Kernel run = 1 Codex thread` を Kernel handoff 契約にする
- `recover-run` は再生成した `main` window で、その run 専用の Codex thread を立ち上げる
- `doctor -> doctor --run -> recover-run` が `MBP` degraded continuation の最小経路
- `cc pocket` は `doctor --all-runs -> doctor --run` を使う mobile degraded continuation node として扱う
- `k` は人間向けの短縮入口で、`k`, `k all`, `k latest`, `k run-id`, `k new <purpose> [focus]`, `k adopt <session:window> [purpose]`, `k <run_id>`, `k show <run_id>`, `k open [run_id]`, `k phase <phase>`, `k done <summary...>` を使う
- `codex-kernel-guard adopt-run <session:window> [purpose]` は unmanaged な live tmux window を Kernel run に昇格し、専用 heavy-profile session へ移す
- `Mac mini` では repo 内で bare `codex` を打った時の既定を `kernel` とし、raw Codex は明示的な opt-out に限る。repo context が明確な通常起動で毎回 `Kernelを起動しますか? [Y/n]` を聞かない
- `Mac mini` では `kernel` を引数なしで打つと最新の active run を開き、active run が無ければ通常の guarded launch に落ちる
- Kernel 起動アダプタは、Codex の初回表示に出る bootstrap 文面を最小限に保つ
- 初回表示では full prompt を inline せず、`.codex/prompts/kernel.md` への短い参照と run metadata を優先する
- `purpose` は run ごとに固定し、目的が変わるなら新しい run を切る
- `codex-kernel-guard phase-check <phase>` は phase 完了前の required model evidence を検査する
- `codex-kernel-guard phase-complete <phase>` は phase evidence を通した上で compact に `phase_completed` を記録する
- `codex-kernel-guard run-complete --summary <text>` は verify gate を通した上で completion backup と `run_completed` compact を記録する
- Kernel の自動記録は既定で節目だけに寄せる。`plan` / `implement` / `verify` 完了と `run-complete` を自動記録し、background completion scan は必要時だけ明示 opt-in にする
- 自動 save は coarse-grained に保ち、細かな編集や partial thought ごとに打たない
- 実装がある程度進んだ checkpoint では `bash scripts/lib/kernel-milestone-record.sh checkpoint "<summary>"` を使い、local save state を更新しつつ bounded な GHA mirror を試みる
- checkpoint save は in-flight work 保護用で、完了記録の代わりにはしない
- phase 完了と run 完了では remote backup だけでなく local save state も更新する
- タスク完了と判断したら必ず `codex-kernel-guard run-complete --summary <text>` を実行して completion を保存し、durable mirror まで通す
- unattended health のため、最初の acknowledgement 前に bootstrap receipt を書き、mode 変化時にも更新する
- bootstrap receipt には provider 数だけでなく `Active models`、manifest lane count、agent/subagent label 有無も入れて live manifest evidence を残す
- `Active models:` 行で、その run で実際に稼働している model だけを明示する
- Lane manifest:
- 各 lane は provider に加えて agent と `subagent1` / `subagent2` / ... / `none` を明示する
- planned / pending / failed lane は数えない
- Bootstrap target: 6+ lanes (minimum 6).
- Codex の `/vote` はローカル継続用の slash prompt
- vote-gh
- RUN_CODEX_VOTE_SMOKE=1 bash tests/test-codex-vote-prompt.sh
