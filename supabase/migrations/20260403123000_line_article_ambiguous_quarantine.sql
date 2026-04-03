-- 20260403123000_line_article_ambiguous_quarantine.sql
-- LINE送信成功後に finalize できなかった曖昧状態を DB 側で quarantine し、
-- GitHub Variables の pause 書き込み失敗だけに依存しないようにする。

DO $$
BEGIN
  IF to_regclass('public.articles') IS NULL THEN
    RAISE EXCEPTION 'public.articles table not found; apply this migration in the production content database.';
  END IF;
END $$;

ALTER TABLE public.articles
  DROP CONSTRAINT IF EXISTS articles_line_delivery_status_check;

ALTER TABLE public.articles
  ADD CONSTRAINT articles_line_delivery_status_check
  CHECK (line_delivery_status IN ('pending', 'processing', 'accepted', 'succeeded', 'failed', 'quarantined'));

CREATE OR REPLACE FUNCTION public.mark_article_line_delivery_accepted(
  p_article_id uuid,
  p_claim_token uuid,
  p_line_request_id text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.articles
  SET line_delivery_status = 'accepted',
      line_delivery_request_id = COALESCE(NULLIF(p_line_request_id, ''), line_delivery_request_id)
  WHERE id = p_article_id
    AND line_delivery_status = 'processing'
    AND line_delivery_claim_token = p_claim_token;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_article_line_delivery_succeeded(
  p_article_id uuid,
  p_claim_token uuid,
  p_line_request_id text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.articles
  SET is_notified = true,
      line_delivery_status = 'succeeded',
      line_delivery_claim_token = NULL,
      line_delivery_processing_started_at = NULL,
      line_delivery_last_error = NULL,
      line_delivery_next_retry_at = NULL,
      line_delivery_request_id = COALESCE(NULLIF(p_line_request_id, ''), line_delivery_request_id),
      line_delivery_notified_at = now()
  WHERE id = p_article_id
    AND line_delivery_status IN ('processing', 'accepted')
    AND line_delivery_claim_token = p_claim_token;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_article_line_delivery_quarantined(
  p_article_id uuid,
  p_claim_token uuid,
  p_error text DEFAULT 'ambiguous_line_delivery_state'
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.articles
  SET line_delivery_status = 'quarantined',
      line_delivery_claim_token = NULL,
      line_delivery_processing_started_at = NULL,
      line_delivery_last_error = left(COALESCE(p_error, 'ambiguous_line_delivery_state'), 1000),
      line_delivery_next_retry_at = NULL
  WHERE id = p_article_id
    AND line_delivery_claim_token = p_claim_token
    AND line_delivery_status IN ('processing', 'accepted');

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;
