# まさおノート動画パイプライン — 技術リファレンス

> **出典**: note.com/masa_wunder「全コード共有：動画を作ってで30分の解説動画が完成」
> **目的**: FUGUE動画パイプライン設計の参照ドキュメント

---

## 1. まさおノートのアーキテクチャ

### コンセプト

「動画を作って」の一言から30分の解説動画を自律生成する。
Claude Code MAX + Skills + Harness による**ディレクター型パイプライン**。

```
ユーザー「動画を作って」
    ↓
Claude Code (MAX) — ディレクター兼実行者
    ├─ Phase 1: シナリオ構成（テーマ→章立て→話す内容）
    ├─ Phase 2: 台本生成（各シーンのナレーション文＋画像指示）
    ├─ Phase 3: アセット生成
    │   ├─ TTS: COEIROINK（無料、ローカル）
    │   └─ 画像: Gemini + fal.ai Banana Pro（~20円/枚）
    ├─ Phase 4: Remotion統合＋レンダリング
    └─ Phase 5: 品質チューニングループ（60→80-90点）
```

### 技術スタック

| 要素 | まさおノート | 備考 |
|------|-------------|------|
| Orchestrator | Claude Code MAX ($200/月) | Skills + Harness で自律実行 |
| TTS | COEIROINK | 無料、macOSローカル、HTTPサーバーモード |
| 画像生成 | Gemini Nano Banana Pro (fal.ai) | ~20円/枚、API経由 |
| 動画フレームワーク | Remotion | React + TypeScript |
| テンプレート | 独自実装 | コード生成型（非データ駆動） |
| 品質管理 | Claude自己評価ループ | 60点→修正→80-90点 |

### コスト構造

| 項目 | コスト |
|------|--------|
| Claude Code MAX | $200/月（定額） |
| 画像生成 | ~20円/枚（Gemini via fal.ai） |
| TTS | 無料（COEIROINK） |
| Remotion | 無料（OSS） |
| **30分動画1本あたり** | **~数百円（画像枚数依存）** |

### 核心的設計思想

1. **コンテキストオーバーフロー防止**: 長時間パイプラインでのトークン管理
2. **エラー自動リカバリ**: 生成失敗時のリトライ＋代替戦略
3. **品質チューニングループ**: 自己評価→修正の反復（3-5回で収束）
4. **ディレクターモデル**: AIが企画→制作→品質管理を一貫して担当

---

## 2. FUGUE進化版との対応マップ

### 差分分析

| 観点 | まさおノート | FUGUE進化版 |
|------|-------------|-------------|
| Orchestrator | Claude単体 | Claude + Codex + GLM（6並列） |
| TTS | COEIROINK（1種） | VOICEVOX/COEIROINK + API fallback |
| 画像生成 | Gemini + fal.ai | 複数モデル選択可 |
| 実行環境 | ローカルのみ | GHA（Phase 1-2）+ ローカル（Phase 3-4） |
| 品質管理 | Claude自己評価 | マルチエージェント合議 |
| テンプレート | コード生成型 | **データ駆動型（推奨）** |
| 夜間処理 | 不可 | GHA24でPhase 1-2は夜間自動 |

### FUGUE側の優位点

1. **マルチモデル品質**: 単一LLMの盲点を6エージェントで補完
2. **GHA24夜間処理**: シナリオ・台本をオーバーナイトで生成
3. **Orchestrator冗長性**: Claude limit時はCodex CLIがfallback
4. **コスト分散**: Claude MAX不要（Codex + GLM + 従量課金）

### まさおノート側の優位点

1. **シンプルさ**: 単一ツール完結、セットアップが容易
2. **ローカル完結**: ネットワーク障害に強い
3. **反復速度**: 品質ループが同一プロセス内で高速
4. **実績**: 実際に30分動画を完成させている

---

## 3. Issue #16 エージェントフィードバック統合

### 全エージェント合意事項（高確度）

1. **データ駆動アーキテクチャを採用すべき**
   - LLMがRemotionコンポーネント（.tsx）を動的生成するのは脆弱
   - LLMはJSON（script.json）のみ出力
   - 事前構築済みテンプレートがJSONを消費して描画
   - まさおノートのコード生成型とは異なるアプローチ

2. **GHA⇔ローカルのハンドオフ自動化**
   - GHA上でPhase 3-4（TTS/レンダリング）は実行不可
   - GitHub Artifactsで `scenario.json` / `script.json` を受け渡し
   - `npm run download-pipeline` で自動取得

3. **Zodによる厳密なスキーマ検証**
   - Phase間のJSON受け渡しを型安全にする
   - バリデーション失敗→LLMに自動修正依頼

4. **TTS選定: VOICEVOX（MVP）**
   - HTTPサーバーモード（`--run_mode`）で自動化可能
   - COEIROINK同様に無料、高品質
   - GUI依存を避けAPI-firstで統合

5. **品質チェックの定量化**
   - 「80-90点」は主観的。バイナリチェックで自動ループの終了条件を定義
   - Failure: アセット欠損、テキストはみ出し、尺ずれ > 0.5s
   - Success: 全アセット存在 + 視覚エラーなし

### セキュリティ指摘

- API キーの管理（fal.ai, TTS API）→ Org Secrets経由
- ローカルTTSサーバーのポート公開範囲を制限

---

## 4. 推奨MVP実装順序

```
Step 1: script.json スキーマ定義 + Zod バリデーション
Step 2: Remotion テンプレート3種（Intro, Content, Outro）をデータ駆動で実装
Step 3: 手動 script.json → Remotion レンダリング動作確認
Step 4: TTS統合（VOICEVOX HTTPサーバー → audio files）
Step 5: Phase 2 自動化（LLM → script.json生成）
Step 6: Phase 1 自動化（LLM → scenario.json生成）
Step 7: GHA24統合（Phase 1-2をクラウド化）
Step 8: 品質ループ追加
```

**原則: 後工程（レンダリング）から先に固める。前工程（シナリオ）は後から。**

---

## 5. まさおノート原文の要点抽出

### パイプライン詳細

- **入力**: 「動画を作って」→ テーマ相談 → 方向性決定
- **シナリオ**: 章立て（5-10章）、各章のキーポイント、想定時間
- **台本**: 各シーンごとに `{ナレーション文, 画像指示, 表示時間, テンプレート種別}`
- **画像**: プロンプト → Gemini/fal.ai → PNG（1920x1080）
- **TTS**: テキスト → COEIROINK → WAV → 各シーンの音声ファイル
- **統合**: Remotion で `<Composition>` に全シーン配置 → MP4レンダリング
- **品質**: Claude が出力動画を（スクリーンショットで）評価 → 修正指示 → 再レンダリング

### 重要な設計判断

1. **コンテキスト分割**: 長い台本を章単位で分割処理（オーバーフロー防止）
2. **キャッシュ戦略**: 変更のないシーンは再生成しない
3. **エラーリカバリ**: 画像生成失敗 → プロンプト変更して再試行（3回まで）
4. **ブランド一貫性**: 色・フォント・トランジションを統一設定ファイルで管理

### 技術的制約

- macOS必須（COEIROINK）
- Node.js 20+
- RAM 16GB+（Remotionレンダリング時）
- COEIROINK HTTPサーバーが起動している前提

---

## 6. 既存リソース参照

| リソース | パス | 内容 |
|----------|------|------|
| Remotion セットアップ | `~/.claude-sync/skills/claude-code-harness/skills/setup/references/remotion-setup.md` | プロジェクト初期設定、package.json |
| V8テンプレート仕様 | `~/.claude-sync/skills/claude-code-harness/agents/video-scene-generator.md` | 9テンプレート定義、brand.ts、品質ルール |
| Miyabi動画ガイド | `~/Dev/Miyabi/docs/VIDEO_GENERATION_GUIDE.md` | FFmpeg版（参考） |
| テロップパック | `~/Dev/telop-pack-srt-02/` | 既存Remotionリポジトリ |

### V8品質ルール（video-scene-generator.md由来）

- CSS transitions禁止（`interpolate` / `spring` のみ）
- `useCurrentFrame()` のみ使用
- ハードコードカラー禁止（`brand.ts` からインポート）
- Audio は `@remotion/media` の `<Audio>` コンポーネント
- spring: `damping: 200` 推奨

---

*Last updated: 2026-02-13*
*Based on: まさおノート (note.com/masa_wunder) + FUGUE Issue #16 agent consensus*
