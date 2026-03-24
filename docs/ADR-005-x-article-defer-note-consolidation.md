# ADR-005: X Article見送り — 長文コンテンツはnote一本化

- **Status**: Accepted
- **Date**: 2026-03-25
- **Deciders**: masayuki (Cursorvers Inc.) + FUGUE orchestrator

## Context

SocialData APIで1,000件超のX Article分析を実施。x-autoパイプラインにArticle提案ロジックを追加するか検討した結果、上流に未解決の戦略課題が発見された。

## Decision

**X Article導入を見送り、長文コンテンツはnote.com一本化とする。**

X投稿からnote記事へのリンク誘導で流入を確保する戦略を採用。

## Rationale

| # | 理由 | 詳細 |
|---|------|------|
| 1 | 自動化不可能 | X Article作成APIが存在しない (2026-03時点)。手動のみではx-autoパイプラインの価値を活かせない |
| 2 | カニバリゼーション | 同じ長文を2チャネルに出すと読者が分散。note資産を毀損するリスク |
| 3 | 収益非対称 | noteは有料記事・メンバーシップ可。X Articleは無料のみ |
| 4 | データ不足 | pillar1 (医療AI) はn=1。「ブルーオーシャン」の根拠として統計的に無意味 |

### 批判的吟味で棄却した前提

- 「1,000字超ならArticle」→ 誤り。X Premiumではツイートも文字制限なし
- バズるArticleパターン (平均2,746字・見出し5.5個) → 結果であって原因ではない (因果逆転)

## Consequences

- x-autoパイプラインにArticle提案ロジックを追加しない
- 長文コンテンツはnote-generate skill (v3.4) で完結
- X投稿 → note記事リンクの誘導パターンを標準化

## Revisit Triggers

- X Article作成APIが公開された場合
- X Articleに収益化機能が追加された場合
- note.comのアルゴリズムが大幅に劣化した場合
