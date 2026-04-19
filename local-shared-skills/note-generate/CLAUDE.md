# note-generate スキルアダプター（薄型）

この adapter は routing と safety gate だけを定義します。記事生成・QC・handoff の手順は source skill と scripts を authority とし、このファイルに増やしません。

## 読み順

1. この skill の `SKILL.md`
2. `claude-config/assets/skills/note-generate/SKILL.md`
3. 実行手順が必要な場合のみ `claude-config/assets/skills/note-generate/scripts/`
4. 最寄り repository の `AGENTS.md`
5. runtime code/tests/logs は必要時のみ読む

source authority が見つからない、または読めない場合は、記憶で再構成せず missing path を報告して停止します。

## 安全ゲート

- thumbnail / eyecatch は `thumbnail-gen` に委譲し、ここで画像方針を再定義しない。
- x-auto handoff では x-auto 側の publish / approval / schedule gate を緩和しない。
- destructive、irreversible、public publish 相当、外部送信、認証・課金・権限境界に触れる操作は明示確認が必要。
- note preview URL / access key など private review link を public copy、x-auto row、source field に混在させない。
- source authority と実行結果が衝突した場合は、公開・外部副作用を停止して差分を報告する。

## 完了報告

draft upload / Notion / x-auto / file を変更した場合、変更先、ID/URL、status、残 blocker を報告する。X lead を作った場合は本文、source/reply URL、image state、x-auto status を明示する。未実行検証があれば理由を報告する。
