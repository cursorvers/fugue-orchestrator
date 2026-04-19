# x-auto スキルアダプター（薄型）

この adapter は routing と safety gate だけを定義します。実行手順は `SKILL.md` と x-auto runtime authority に従い、このファイルに増やしません。

## 読み順

1. この skill の `SKILL.md`
2. current workspace の `x-auto/CLAUDE.md`。無い場合のみ `$FUGUE_DEV_ROOT/x-auto/CLAUDE.md`（`FUGUE_DEV_ROOT` 未設定なら fallback せず停止）
3. Codex 固有規則が必要な場合のみ current workspace の `x-auto/AGENTS.md`。無い場合のみ `$FUGUE_DEV_ROOT/x-auto/AGENTS.md`（`FUGUE_DEV_ROOT` 未設定なら fallback せず停止）
4. 最寄り repository の `AGENTS.md`
5. runtime code/tests/logs は必要時のみ読む

authority file が見つからない、または読めない場合は、記憶で補完せず missing path を報告して停止します。
投稿安全、publish 判定、Single Writer は x-auto runtime authority を最優先し、一般規約で緩和しないでください。
live runtime behavior は状態診断にだけ使い、安全・承認ゲートの緩和根拠にしないでください。

## 安全ゲート

- Single Writer は Mac mini `com.cursorvers.x-auto` scheduler のみ。代替投稿経路を追加・再有効化しない。
- `delete/trash/move/overwrite-risk`、database/data source の schema・構造変更、`Status=approved` を含む publish 相当は毎回ユーザー明示確認が必要。
- ユーザーが `approve` / `publish` / `schedule-as-approved` を明示しない限り、既定は `Status=draft`。
- 合議フローが single-lane fallback になった場合、`draft -> approved` は実行せずエスカレーションする。
- Notion と local queue のどちらかを変更した場合、同一作業内で同期状態を回復する。
- thumbnail policy は `thumbnail-gen` authority を使用し、ここで再定義しない。

## 完了報告

変更後は `status`、queue row / Notion URL、schedule、source/reply URL、image state、実行した health/audit check、未実行理由と blocker を報告する。publish 相当の gate が未実行または失敗なら `Status=draft` を維持する。
