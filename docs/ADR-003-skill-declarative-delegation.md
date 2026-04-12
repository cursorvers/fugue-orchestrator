# ADR-003: Skill 宣言的委譲パターンの限定導入

## Status: VALIDATED (PoC implemented + real vote test passed 2026-03-22)

## Date: 2026-03-22

## Context

note 記事「Claude Code Skills: context:fork / !command / subagent」で提示されたパターンを
FUGUE orchestration に適用可能か、Codex architect + GLM auditor + FUGUE orchestrator の
三者合議を 2 ラウンド実施した。

### 合議結果サマリ

| パターン | 判定 | 理由 |
|---------|------|------|
| !command (情報取得) | 採用 | 決定論的トリガー、delegate.js facade |
| !command (codex exec 直接) | 不採用 | telemetry/fallback/retry が失われる |
| context:fork (artifact-only) | PoC | spawn ベースとの実質差を検証 |
| 孫エージェント | 不採用 | 未文書化動作依存、rate limit |
| LLM Debate → Tutti 統合 | 採用 | evidence collector として |
| 宣言的移行 (全面) | 不採用 | control-plane は Node に残す |

### FUGUE 制約 (不変条件)

- Claude は実装しない — delegate to engines
- subagent/agent-teams 禁止 — Claude rate limit 保護
- 多モデル多様性 — baseline trio (codex + claude + glm)
- Phase gate 必須 — plan → simulate → critique

## Decision

以下 2 つの PoC を実装する。

---

## PoC-1: !delegate wrapper skill

### 概要

既存の `delegate.js` / `delegate-glm.js` を SKILL.md の `!command` 構文から呼び出す
薄い宣言的 wrapper を作成する。control-plane (telemetry, fallback, retry) は
既存 Node スクリプトに残し、UX 層のみ宣言的にする。

### 要件

| ID | 要件 | 優先度 |
|----|------|--------|
| P1-R1 | `/.claude/skills/fugue-delegate/SKILL.md` を新規作成 | MUST |
| P1-R2 | `!command` で `delegate.js --auto-context` を呼出し、結果をコンテキストに注入 | MUST |
| P1-R3 | `$ARGUMENTS` からタスク文字列と `-a` (architect/code-reviewer/security-analyst) を受け取る | MUST |
| P1-R4 | 呼出例: `/fugue-delegate architect "review this PR"` | MUST |
| P1-R5 | GLM fallback: `delegate-glm.js` への自動切替えロジックは既存 Node 側に委ねる | MUST |
| P1-R6 | `context:fork` は使わない (親コンテキストで結果を受け取る) | MUST |
| P1-R7 | `subagent:` は使わない | MUST |
| P1-R8 | SKILL.md は 50 行以内 | SHOULD |

### 受入条件

1. `/fugue-delegate architect "list files"` で delegate.js が実行され、結果が表示される
2. 既存の telemetry/output-format が維持される
3. 直接 Bash で `node delegate.js` を呼んだ場合と同じ結果が得られる

### ファイル構成

```
~/.claude/skills/fugue-delegate/
  SKILL.md          # 新規作成
```

### 参照ファイル (読取専用)

- `~/.claude/skills/orchestra-delegator/scripts/delegate.js`
- `~/.claude/skills/orchestra-delegator/scripts/delegate-glm.js`
- `/Users/masayuki_otawara/Downloads/subagents/.claude/skills/red-test/SKILL.md` (パターン参照)

---

## PoC-2: LLM Debate → consensus-vote.js evidence collector

### 概要

記事の `build-prompt.js` パターンを FUGUE の `consensus-vote.js` の前段に統合する。
debate 結果を evidence として weighted vote に渡す。vote contract 自体は変更しない。

### 要件

| ID | 要件 | 優先度 |
|----|------|--------|
| P2-R1 | `~/.claude/skills/orchestra-delegator/scripts/lib/debate-evidence.js` を新規作成 | MUST |
| P2-R2 | 引数: `topic` (議題文字列), `files` (関連ファイルパス配列, optional) | MUST |
| P2-R3 | Codex (delegate.js) と GLM (delegate-glm.js) に同一議題を並列送信 | MUST |
| P2-R4 | 各回答を構造化 JSON `{ provider, conclusion, analysis, confidence }` で返す | MUST |
| P2-R5 | `consensus-vote.js` から呼出可能な関数として export | MUST |
| P2-R6 | consensus-vote.js の既存 vote ロジックは変更しない | MUST |
| P2-R7 | debate は vote の前段 evidence 収集であり、vote 置換ではない | MUST |
| P2-R8 | Gemini/Cursor は optional provider (環境に存在する場合のみ参加) | SHOULD |
| P2-R9 | timeout: 各 provider 最大 120 秒、超過は skip | SHOULD |

### 受入条件

1. `debate-evidence.js` 単体で実行可能: `node debate-evidence.js --topic "X vs Y"`
2. 出力が JSON 配列: `[{ provider: "codex", conclusion: "...", ... }, { provider: "glm", ... }]`
3. consensus-vote.js から `require('./lib/debate-evidence')` で import 可能
4. 既存の vote テストが全て pass

### ファイル構成

```
~/.claude/skills/orchestra-delegator/scripts/
  lib/
    debate-evidence.js  # 新規作成
  consensus-vote.js     # 変更なし (import 追加のみ、将来)
```

### 参照ファイル (読取専用)

- `/Users/masayuki_otawara/Downloads/subagents/.claude/skills/llm-debate/build-prompt.js`
- `/Users/masayuki_otawara/Downloads/subagents/.claude/skills/llm-debate/SKILL.md`
- `~/.claude/skills/orchestra-delegator/scripts/consensus-vote.js`
- `~/.claude/skills/orchestra-delegator/scripts/delegate.js`
- `~/.claude/skills/orchestra-delegator/scripts/delegate-glm.js`

---

## Not In Scope

- context:fork phase gate PoC (別 ADR で検討)
- 孫エージェント構成
- subagent / agent-teams の使用
- fugue-execute.mjs / fugue-lane-bridge.mjs の書替え
- Kernel 側への展開

## Consequences

- FUGUE の委譲 UX が改善される (SKILL.md 呼出で delegate.js が発火)
- consensus-vote.js に evidence 品質向上の前段が加わる
- 既存の control-plane (telemetry, fallback, retry) は一切変更しない
- Kernel 文書には影響しない (Claude Code ローカル拡張のみ)
