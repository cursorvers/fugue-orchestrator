# Proposal: Memory Autonomous Refresh & Self-Heal

> Status: DRAFT | Date: 2026-03-24
> Source: Gap analysis — Hayashi "AI-driven Management" vs FUGUE scoring (+11pt potential)
> Delegate: Codex (implementation) + GLM (review) + Claude (orchestration/acceptance)

---

## 1. Goal Statement

**FUGUE memory system を「セッション依存の手動更新」から「自律的に鮮度を維持し自己改善する」状態に進化させる。**

### Success Criteria (KPI)

| KPI | Before | Target | Measurement |
|-----|--------|--------|-------------|
| Memory stale rate (30日超未更新) | 未計測 (推定40%+) | < 15% | `memory-refresh --audit` |
| Self-heal actions/week | 0 | 3+ | `selfheal.jsonl` log count |
| Context freshness score | 4/10 | 7/10 | Hayashi比較スコアカード |
| Self-improvement score | 3/10 | 7/10 | Hayashi比較スコアカード |
| FUGUE total score | 78/120 | 88/120 | 12軸スコアカード再評価 |

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                  FUGUE Memory v2                 │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ Tier 1   │  │ Tier 2   │  │ Tier 3 (NEW)  │  │
│  │ MEMORY.md│→ │ _idx_*.md│→ │ Auto-Refresh  │  │
│  │ (always) │  │ (demand) │  │ + Self-Heal   │  │
│  └──────────┘  └──────────┘  └───────┬───────┘  │
│                                      │           │
│  ┌───────────────────────────────────┘           │
│  │                                               │
│  ▼                                               │
│  ┌──────────────┐  ┌──────────────┐              │
│  │ memory-      │  │ selfheal     │              │
│  │ refresh.sh   │  │ -diagnose.sh │              │
│  │ (launchd)    │  │ (launchd)    │              │
│  │ Daily 06:00  │  │ Daily 07:00  │              │
│  └──────┬───────┘  └──────┬───────┘              │
│         │                 │                      │
│         ▼                 ▼                      │
│  ┌──────────────────────────────┐                │
│  │ FTS5 Index (existing)        │                │
│  │ + stale_score column (NEW)   │                │
│  │ + source_citation (NEW)      │                │
│  └──────────────────────────────┘                │
└─────────────────────────────────────────────────┘
```

---

## 3. Requirements

### R1: Memory Stale Detection & Audit

**Goal**: 全memory fileの鮮度を定量評価し、staleエントリを自動検出する。

| ID | Requirement | Priority | Acceptance |
|----|-------------|----------|------------|
| R1.1 | memory fileのfrontmatterに `updated: YYYY-MM-DD` を必須化 | P0 | 既存ファイルへの後方互換: `updated` 未設定 → `created` or git mtime fallback |
| R1.2 | stale判定ロジック: `days_since_update > 30` → STALE, `> 60` → CRITICAL | P0 | `memory-refresh --audit` で一覧出力 |
| R1.3 | FTS5 index に `stale_score` カラム追加 (0.0-1.0, 時間減衰) | P1 | recall検索結果のランキングに反映 |
| R1.4 | `--audit` 結果を `memory-audit.json` に出力 (CI/hook連携用) | P1 | JSON schema定義済み |

### R2: Memory Auto-Refresh (Cron)

**Goal**: 毎朝自動でmemoryの鮮度を維持する。林式の「memory.md毎朝更新」に相当。

| ID | Requirement | Priority | Acceptance |
|----|-------------|----------|------------|
| R2.1 | launchd plist: `com.cursorvers.memory-refresh.plist` Daily 06:00 JST | P0 | Mac mini上で動作確認 |
| R2.2 | stale audit実行 → CRITICAL entries をログ出力 | P0 | `~/.claude/logs/memory-refresh.log` に記録 |
| R2.3 | FTS5 index rebuild (既存 `memory-recall.py index` 呼出) | P0 | index freshness < 24h 保証 |
| R2.4 | STALE memory の自動アーカイブ (60日超 → `_archived/` 移動) | P2 | 移動前に `_archived/` にコピー、元ファイルは `[ARCHIVED]` prefix |
| R2.5 | 実行結果サマリーをLINE/Discord通知 | P1 | 既存 `line-notify.sh` / `discord-notify.sh` 連携 |

### R3: Source Citation Enforcement

**Goal**: 林式「出典必須」ルールをFUGUE memoryに適用。

| ID | Requirement | Priority | Acceptance |
|----|-------------|----------|------------|
| R3.1 | memory frontmatter に `source:` フィールド追加 (optional but recommended) | P1 | 形式: `source: "2026-03-24 weekly meeting"` or `source: "commit abc123"` |
| R3.2 | 新規memory作成時に `source:` 未設定 → warning出力 (blocking しない) | P1 | SKILL.md + auto-memory ルールに追記 |
| R3.3 | `--audit` で source未設定率を計測 | P2 | target: < 30% missing |

### R4: Self-Heal Diagnosis Cycle

**Goal**: 毎朝の自己診断 → 自動修復。林式「自己改善サイクル」に相当。

| ID | Requirement | Priority | Acceptance |
|----|-------------|----------|------------|
| R4.1 | launchd plist: `com.cursorvers.fugue-selfheal.plist` Daily 07:00 JST | P0 | R2の後に実行（依存順序） |
| R4.2 | 診断項目: memory stale audit結果 (R1連携) | P0 | CRITICAL → 自動アクション |
| R4.3 | 診断項目: FTS5 index integrity check | P0 | 破損検知 → auto rebuild |
| R4.4 | 診断項目: MEMORY.md ⇔ _idx_*.md リンク整合性 | P1 | broken link → warning + 候補提示 |
| R4.5 | 診断項目: frontmatter schema validation (全memory file) | P1 | invalid frontmatter → log + 修正候補 |
| R4.6 | 診断項目: kernel-runtime-health.sh 結果 (既存) | P1 | degraded → auto-remediation (bootstrap再実行) |
| R4.7 | 全診断結果を `selfheal.jsonl` に追記 | P0 | 1行1JSON、timestamp + item + action + result |
| R4.8 | 修復アクション実行後、memory に学習記録を追記 | P2 | 「何を直したか」をmemory化 → 次回の判断精度向上 |

### R5: Stock/Flow Separation Rule

**Goal**: memory内のstock情報とflow情報を明確に分離。

| ID | Requirement | Priority | Acceptance |
|----|-------------|----------|------------|
| R5.1 | frontmatter に `durability: stock|flow` フィールド追加 | P1 | stock: 3ヶ月後も参照価値あり / flow: 一時的 |
| R5.2 | flow memory は 14日後に自動 `[STALE]` フラグ (stock は 30日) | P1 | R1.2 のstale判定にdurabilityを反映 |
| R5.3 | MEMORY.md / _idx_*.md にはstock onlyを掲載するルール | P1 | flow は FTS5 検索経由でのみアクセス |

### R6: Frontmatter Schema Unification

**Goal**: 既知の不整合（SKILL.md vs auto-memory ルール）を解消。

| ID | Requirement | Priority | Acceptance |
|----|-------------|----------|------------|
| R6.1 | 統一schema定義: `memory-schema.json` (JSON Schema) | P0 | name, description, type, created, updated, source, durability, status |
| R6.2 | 既存memory fileの一括マイグレーション | P1 | `memory-migrate.sh` で自動変換、dry-run モード付き |
| R6.3 | memory書込パスでYAML safe-quote処理 | P0 | コロン・引用符・改行を含むdescriptionが壊れない |

---

## 4. Implementation Phases

### Phase 1: Foundation (P0 items) — Codex delegate

| Task | Deliverable | Delegate |
|------|-------------|----------|
| Frontmatter schema定義 | `memory-schema.json` | Codex |
| YAML safe-quote修正 | memory書込パスの修正 | Codex |
| Stale detection script | `memory-refresh.sh` (audit mode) | Codex |
| Self-heal diagnosis script | `selfheal-diagnose.sh` | Codex |
| launchd plist x2 | `com.cursorvers.memory-refresh.plist`, `com.cursorvers.fugue-selfheal.plist` | Codex |
| Logging infrastructure | `selfheal.jsonl` + `memory-refresh.log` | Codex |

### Phase 2: Enrichment (P1 items) — Codex + GLM

| Task | Deliverable | Delegate |
|------|-------------|----------|
| FTS5 stale_score column | `memory-recall.py` patch | Codex |
| Source citation enforcement | SKILL.md + auto-memory rule update | Claude (policy) |
| Stock/flow separation | frontmatter extension + stale rule update | Codex |
| Link integrity checker | `memory-lint.sh` | GLM |
| Notification integration | LINE/Discord summary | Codex |
| Existing file migration | `memory-migrate.sh` | Codex |

### Phase 3: Intelligence (P2 items) — GLM + Codex

| Task | Deliverable | Delegate |
|------|-------------|----------|
| Auto-archive (60日超) | `memory-refresh.sh` archive mode | Codex |
| Self-learning from repairs | R4.8 memory蓄積ロジック | GLM |
| Source coverage metrics | audit dashboard | GLM |

---

## 5. Risk & Constraints

| Risk | Impact | Mitigation |
|------|--------|------------|
| 既存78+ memory fileのマイグレーション破損 | HIGH | dry-run + git backup必須 |
| launchd実行時のClaude API rate limit消費 | MED | selfhealはClaude不使用（shellスクリプトのみ） |
| frontmatter変更による既存hook/skill破損 | MED | 後方互換: 新フィールドは全てoptional |
| stale判定の誤検知 (長期有効なstock memory) | LOW | `durability: stock` で30→60日閾値に緩和 |

---

## 6. Non-Goals

- Slack bot / 非エンジニアIF (ソロ開発では ROI 低い)
- tl;dv 会議文字起こし統合 (Cursorvers社での運用実態なし)
- Semantic/Vector search (Phase 2 of FTS5, 3ヶ月運用データ待ち)
- memory.md の内容自動生成 (LLM依存の自動書込は品質リスク大)

---

## 7. Expected Score Impact

| 評価軸 | Before | After | Delta |
|--------|:------:|:-----:|:-----:|
| コンテキスト鮮度 | 4 | 7 | **+3** |
| 自己改善サイクル | 3 | 7 | **+4** |
| cron成熟度 | 6 | 8 | **+2** |
| コンテキスト整理 | 6 | 7 | **+1** |
| **FUGUE合計** | **78** | **88** | **+10** |
