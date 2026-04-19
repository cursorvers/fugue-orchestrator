# thumbnail-gen スキルアダプター（薄型）

この adapter は routing と safety gate だけを定義します。prompt policy / engine priority / QA threshold は source thumbnail skill を authority とし、このファイルに増やしません。

## 読み順

1. この skill の `SKILL.md`
2. `claude-config/assets/skills/thumbnail-gen/SKILL.md`
3. `claude-config/assets/skills/thumbnail-gen/prompt-library.json`
4. 実行手順が必要な場合のみ `claude-config/assets/skills/thumbnail-gen/scripts/`
5. 最寄り repository の `AGENTS.md`
6. 呼び出し元 skill の target constraints

source files が見つからない、または読めない場合は、即興で方針を作らず missing path を報告して停止します。

## 安全ゲート

- 呼び出し元の target constraints（note eyecatch / X image / banner など）を先に確認する。
- source skill と caller が衝突する場合は source thumbnail skill を優先し、公開・投稿側の安全 gate は caller 側で維持する。
- 画像生成/編集/upload を実行したと主張する前に、local path、receipt、または upload output を確認する。
- public upload、既存 approved asset の置換、不可逆変更、外部投稿に直結する変更は明示確認が必要。
- 破棄・却下済み候補を再提示しない。

## 完了報告

生成/編集した画像の path、size、target、source/caller、QA result を報告する。文字入り画像は指定文言欠落と文字化けを確認する。未実行の視覚確認や upload があれば理由と blocker を報告する。
