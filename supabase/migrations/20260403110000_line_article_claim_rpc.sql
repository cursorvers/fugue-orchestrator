-- 20260403110000_line_article_claim_rpc.sql
-- Exactly-onceに近づけるため、LINE note article配信を
-- GitHub VariablesではなくSupabase側のlease/claim state machineへ寄せる。
--
-- 前提:
-- - public.articles が既に存在すること
-- - public.articles は少なくとも id, title, url, published_at, is_notified を持つこと

DO $$
BEGIN
  IF to_regclass('public.articles') IS NULL THEN
    RAISE EXCEPTION 'public.articles table not found; apply this migration in the production content database.';
  END IF;
END $$;

ALTER TABLE public.articles
  ADD COLUMN IF NOT EXISTS line_delivery_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS line_delivery_claim_token uuid,
  ADD COLUMN IF NOT EXISTS line_delivery_processing_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS line_delivery_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS line_delivery_last_error text,
  ADD COLUMN IF NOT EXISTS line_delivery_next_retry_at timestamptz,
  ADD COLUMN IF NOT EXISTS line_delivery_request_id text,
  ADD COLUMN IF NOT EXISTS line_delivery_notified_at timestamptz;

ALTER TABLE public.articles
  DROP CONSTRAINT IF EXISTS articles_line_delivery_status_check;

ALTER TABLE public.articles
  ADD CONSTRAINT articles_line_delivery_status_check
  CHECK (line_delivery_status IN ('pending', 'processing', 'accepted', 'succeeded', 'failed'));

CREATE INDEX IF NOT EXISTS idx_articles_line_delivery_claim
  ON public.articles (line_delivery_status, line_delivery_next_retry_at, published_at DESC);

CREATE INDEX IF NOT EXISTS idx_articles_line_delivery_processing
  ON public.articles (line_delivery_status, line_delivery_processing_started_at)
  WHERE line_delivery_status = 'processing';

CREATE OR REPLACE FUNCTION public.claim_article_for_line_delivery(
  p_lease_seconds integer DEFAULT 21600,
  p_max_attempts integer DEFAULT 10
)
RETURNS TABLE (
  id uuid,
  title text,
  url text,
  published_at timestamptz,
  delivery_action text,
  claim_token uuid,
  delivery_attempts integer
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_claim_token uuid := gen_random_uuid();
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.articles AS accepted_row
    WHERE accepted_row.published_at IS NOT NULL
      AND COALESCE(accepted_row.is_notified, false) = false
      AND accepted_row.line_delivery_status = 'accepted'
  ) THEN
    RETURN QUERY
    SELECT
      a.id,
      a.title,
      a.url,
      a.published_at,
      'reconcile'::text,
      a.line_delivery_claim_token,
      a.line_delivery_attempts
    FROM public.articles AS a
    WHERE a.published_at IS NOT NULL
      AND COALESCE(a.is_notified, false) = false
      AND a.line_delivery_status = 'accepted'
    ORDER BY a.published_at DESC, a.id DESC
    LIMIT 1;
    RETURN;
  END IF;

  RETURN QUERY
  WITH candidate AS (
    SELECT a.id
    FROM public.articles AS a
    WHERE a.published_at IS NOT NULL
      AND COALESCE(a.is_notified, false) = false
      AND (
        a.line_delivery_status IN ('pending', 'failed')
        OR (
          a.line_delivery_status = 'processing'
          AND a.line_delivery_processing_started_at < now() - make_interval(secs => p_lease_seconds)
        )
      )
      AND COALESCE(a.line_delivery_attempts, 0) < p_max_attempts
      AND (
        a.line_delivery_next_retry_at IS NULL
        OR a.line_delivery_next_retry_at <= now()
      )
    ORDER BY a.published_at DESC, a.id DESC
    FOR UPDATE SKIP LOCKED
    LIMIT 1
  ),
  claimed AS (
    UPDATE public.articles AS a
    SET line_delivery_status = 'processing',
        line_delivery_claim_token = v_claim_token,
        line_delivery_processing_started_at = now(),
        line_delivery_attempts = COALESCE(a.line_delivery_attempts, 0) + 1,
        line_delivery_last_error = NULL,
        line_delivery_next_retry_at = NULL
    FROM candidate
    WHERE a.id = candidate.id
    RETURNING
      a.id,
      a.title,
      a.url,
      a.published_at,
      'send'::text AS delivery_action,
      a.line_delivery_claim_token,
      a.line_delivery_attempts
  )
  SELECT
    claimed.id,
    claimed.title,
    claimed.url,
    claimed.published_at,
    claimed.delivery_action,
    claimed.line_delivery_claim_token,
    claimed.line_delivery_attempts
  FROM claimed;
END;
$$;

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
      line_delivery_request_id = COALESCE(p_line_request_id, line_delivery_request_id)
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
      line_delivery_request_id = COALESCE(p_line_request_id, line_delivery_request_id),
      line_delivery_notified_at = now()
  WHERE id = p_article_id
    AND line_delivery_status IN ('processing', 'accepted')
    AND line_delivery_claim_token = p_claim_token;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_article_line_delivery_failed(
  p_article_id uuid,
  p_claim_token uuid,
  p_error text,
  p_retry_seconds integer DEFAULT 300
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.articles
  SET line_delivery_status = 'failed',
      line_delivery_claim_token = NULL,
      line_delivery_processing_started_at = NULL,
      line_delivery_last_error = left(COALESCE(p_error, 'unknown error'), 1000),
      line_delivery_next_retry_at = now() + make_interval(secs => GREATEST(p_retry_seconds, 60))
  WHERE id = p_article_id
    AND line_delivery_status = 'processing'
    AND line_delivery_claim_token = p_claim_token;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.reconcile_article_line_delivery(
  p_article_id uuid,
  p_claim_token uuid
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
      line_delivery_notified_at = COALESCE(line_delivery_notified_at, now())
  WHERE id = p_article_id
    AND line_delivery_claim_token = p_claim_token
    AND line_delivery_status IN ('processing', 'accepted', 'failed');

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;
