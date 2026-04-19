# note-manuscript スキルアダプター（薄型）

この adapter は routing と safety gate だけを定義します。執筆・検証の実務は `SKILL.md` を authority とし、このファイルに増やしません。

## 読み順

1. この skill の `SKILL.md`
2. 執筆対象 repository の `AGENTS.md`
3. 明示参照された `references/`、scripts、runtime docs
4. 外部ソース/過去記事/logs は必要時のみ読む

required source が見つからない、または読めない場合は、推測で補完せず missing path を報告して停止します。

## 安全ゲート

- publish-ready 判定は `SKILL.md` の hard veto order に従う。
- primary-source verification が必要な主張は、未検証のまま publish-ready としない。
- 法務・規制・医療・コンプライアンス近接の断定は `SKILL.md` の stop condition と caveat を優先する。
- user voice / worldview / house style を扱う場合も private material を不要に広く読まない。
- thumbnail / eyecatch は title と framing が安定してから `thumbnail-gen` に委譲する。
- public upload、既存 draft 削除、publish 相当、外部送信、不可逆変更は明示確認が必要。

## 完了報告

原稿更新時は最新版の所在、未解決 gate、主要 source 状態を報告する。note draft / eyecatch / x-auto lead を作成した場合は ID/URL、status、private/public 区分を明示する。検証省略があれば理由と残リスクを報告する。
