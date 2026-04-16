-- 20260406193000_x_auto_quoted_author_registry_v1.sql
-- Minimal quoted-author registry for x-auto diversity tracking and replayable provenance.

create table if not exists public.quoted_authors (
  author_id uuid primary key default gen_random_uuid(),
  platform text not null,
  canonical_handle text,
  display_name text,
  profile_url text,
  normalized_key text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  quote_count integer not null default 0,
  last_quoted_at timestamptz,
  status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quoted_authors_platform_check check (platform in ('x', 'note', 'site', 'paper', 'other')),
  constraint quoted_authors_status_check check (status in ('active', 'merged', 'suppressed')),
  constraint quoted_authors_platform_normalized_key_key unique (platform, normalized_key)
);

create table if not exists public.quoted_sources (
  source_id uuid primary key default gen_random_uuid(),
  author_id uuid references public.quoted_authors(author_id),
  source_url text not null,
  normalized_source_url text not null,
  source_type text not null,
  source_domain text,
  title text,
  published_at timestamptz,
  source_hash text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quoted_sources_normalized_source_url_key unique (normalized_source_url),
  constraint quoted_sources_source_hash_key unique (source_hash)
);

create table if not exists public.quote_events (
  event_id uuid primary key default gen_random_uuid(),
  event_hash text not null unique,
  source_id uuid not null references public.quoted_sources(source_id) on delete cascade,
  author_id uuid references public.quoted_authors(author_id) on delete set null,
  notion_page_id text,
  cursorvers_post_id text,
  event_kind text not null,
  topic_tags jsonb not null default '[]'::jsonb,
  conclusion_tag text,
  pattern_tag text,
  diversity_score numeric(5,2),
  similarity_to_recent numeric(5,2),
  decision text,
  decided_by text,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint quote_events_event_kind_check check (event_kind in ('discovered', 'drafted', 'approved', 'rejected', 'posted'))
);

create index if not exists idx_quoted_authors_last_quoted_at
  on public.quoted_authors (last_quoted_at desc nulls last);

create index if not exists idx_quoted_sources_author_id
  on public.quoted_sources (author_id);

create index if not exists idx_quoted_sources_source_domain
  on public.quoted_sources (source_domain);

create index if not exists idx_quote_events_created_at
  on public.quote_events (created_at desc);

create index if not exists idx_quote_events_source_id
  on public.quote_events (source_id);

create index if not exists idx_quote_events_event_hash
  on public.quote_events (event_hash);

create index if not exists idx_quote_events_author_id
  on public.quote_events (author_id);

create index if not exists idx_quote_events_conclusion_tag
  on public.quote_events (conclusion_tag);
