# LINE Article Claim Migration

目的:
- `LINE Send Note Article` の `select -> send -> mark notified` を Supabase 側の claim/finalize に寄せる
- GitHub Variables 依存を監査用途へ縮退し、重複再送の本質原因を DB 側で潰す

前提:
- `public.articles` が存在する本番 Supabase project で実行する
- `public.articles` は `id`, `title`, `url`, `published_at`, `is_notified` を持つ

追加する migration:
- `[20260403110000_line_article_claim_rpc.sql](/Users/masayuki_otawara/Dev/cursorvers_line_free_dev/supabase/migrations/20260403110000_line_article_claim_rpc.sql)`
- `[20260403123000_line_article_ambiguous_quarantine.sql](/Users/masayuki_otawara/Dev/cursorvers_line_free_dev/supabase/migrations/20260403123000_line_article_ambiguous_quarantine.sql)`

追加される state:
- `line_delivery_status`
- `line_delivery_claim_token`
- `line_delivery_processing_started_at`
- `line_delivery_attempts`
- `line_delivery_last_error`
- `line_delivery_next_retry_at`
- `line_delivery_request_id`
- `line_delivery_notified_at`
- `quarantined`

追加される RPC:
- `claim_article_for_line_delivery(p_lease_seconds, p_max_attempts)`
- `mark_article_line_delivery_accepted(p_article_id, p_claim_token, p_line_request_id)`
- `mark_article_line_delivery_succeeded(p_article_id, p_claim_token, p_line_request_id)`
- `mark_article_line_delivery_failed(p_article_id, p_claim_token, p_error, p_retry_seconds)`
- `reconcile_article_line_delivery(p_article_id, p_claim_token)`
- `mark_article_line_delivery_quarantined(p_article_id, p_claim_token, p_error)`

workflow 切替方針:
1. `Resolve latest unpublished article` の REST `select ... is_notified=eq.false` を廃止する
2. 代わりに `rpc/claim_article_for_line_delivery` を呼び、返却 `id/title/url/published_at/claim_token` を使う
3. `Persist prepared delivery lock` と `Revalidate delivery lock` は削除する
4. LINE送信成功後は `mark_article_line_delivery_accepted` を先に呼ぶ
5. その後 `mark_article_line_delivery_succeeded` で確定する
6. LINE送信失敗時は `mark_article_line_delivery_failed` を呼ぶ
7. accepted 状態の再開は `reconcile_article_line_delivery` に一本化する
8. LINE送信は成功したが finalize に失敗した場合は `mark_article_line_delivery_quarantined` を呼び、DB側で再claim不能にしてから `LINE_DELIVERY_PAUSED=true` にする

期待される効果:
- claim は DB で `FOR UPDATE SKIP LOCKED` により単一化される
- finalize は `claim_token` 一致条件で stale worker の上書きを防ぐ
- GitHub Variables 書き込み障害があっても exactly-once に近い挙動を保てる
- 曖昧成功は `quarantined` に退避され、lease切れ後の自動再claimを防げる

適用後に確認する SQL:
```sql
select id, is_notified, line_delivery_status, line_delivery_attempts, line_delivery_claim_token
from public.articles
order by published_at desc
limit 20;
```

`quarantined` が残っていた場合の復旧順序:
1. 対象 article の request id と LINE 側ログを照合し、実送信済みか確認する
2. 実送信済みなら `mark_article_line_delivery_succeeded` か `reconcile_article_line_delivery` で確定する
3. 未送信なら原因を除去したうえで `pending` か `failed` に戻す
4. その後でのみ `LINE_DELIVERY_PAUSED` を `false` に戻す

適用後に確認する workflow 変更点:
- `[line-send-note-article.yml](/Users/masayuki_otawara/Dev/.github/workflows/line-send-note-article.yml)` から `LINE_NOTE_ARTICLE_PENDING_*` を送信可否判定に使う箇所を外す
- `LAST_SENT_NOTE_ARTICLE_*` は監査用の receipt としてのみ残す
