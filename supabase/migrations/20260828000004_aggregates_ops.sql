-- 0004 · Aggregates + ops. tech/01 §1.3–1.4; ADR 0006.
-- Aggregate tables store NO user identifiers — anonymous contribution is
-- structural. Clients read only through min-n-enforcing definer RPCs.

create table agg_variant_stats (
    variant_id uuid not null references variants (id),
    tone_band int, -- null = all
    skin_type text, -- null = all
    -- nullable cohort dims can't form a PK; a generated key can
    cohort_key text generated always as (coalesce(tone_band::text, '-') || ':' || coalesce(skin_type, '-')) stored,
    owners int not null default 0,
    fit_counts jsonb not null default '{}',
    chip_counts jsonb not null default '{}',
    refreshed_at timestamptz not null default now(),
    primary key (variant_id, cohort_key)
);

create table agg_rank_scores (
    product_id uuid not null references products (id),
    category_id uuid not null references categories (id),
    cohort_key text not null, -- 'all' | 'shade:<variant_id>' | 'hair:3b'
    n_face_offs int not null default 0,
    n_users int not null default 0,
    mean_percentile numeric,
    refreshed_at timestamptz not null default now(),
    primary key (product_id, category_id, cohort_key)
);

create table shade_cooccurrence (
    variant_a uuid not null references variants (id),
    variant_b uuid not null references variants (id),
    n int not null default 0,
    refreshed_at timestamptz not null default now(),
    primary key (variant_a, variant_b),
    constraint ordered_pair check (variant_a < variant_b)
);

create table failed_searches (
    id uuid primary key default gen_random_uuid(),
    query text not null,
    domain domain_enum,
    user_count int not null default 1,
    last_seen timestamptz not null default now(),
    resolved_product_id uuid references products (id)
);
create unique index failed_searches_query on failed_searches (lower(query));

create table ingest_jobs (
    id uuid primary key default gen_random_uuid(),
    kind text not null check (kind in ('feed_diff', 'snapshot_import', 'inci_enrich', 'image_fetch')),
    payload jsonb not null default '{}',
    state text not null default 'queued' check (state in ('queued', 'running', 'done', 'failed', 'dead')),
    attempts int not null default 0,
    last_error text,
    run_after timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index ingest_jobs_runnable on ingest_jobs (run_after) where state = 'queued';

create table merge_candidates (
    id uuid primary key default gen_random_uuid(),
    product_a uuid not null references products (id),
    product_b uuid not null references products (id),
    similarity numeric,
    llm_verdict jsonb,
    state text not null default 'pending' check (state in ('pending', 'auto_merged', 'approved', 'rejected')),
    verb text check (verb in ('merge', 'attach_variant', 'fork')),
    decided_by text,
    decided_at timestamptz,
    created_at timestamptz not null default now()
);

create table audit_records (
    id bigint generated always as identity primary key,
    actor text not null,
    action text not null,
    entity text not null,
    entity_id text not null,
    before jsonb,
    after jsonb,
    at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- RLS: everything here is service-role territory. No user policies at all —
-- authenticated/anon reach aggregates only through the definer RPC below.
-- ---------------------------------------------------------------------------
alter table agg_variant_stats enable row level security;
alter table agg_rank_scores enable row level security;
alter table shade_cooccurrence enable row level security;
alter table failed_searches enable row level security;
alter table ingest_jobs enable row level security;
alter table merge_candidates enable row level security;
alter table audit_records enable row level security;

-- Min-n constants live in one place so thresholds stay auditable (ADR 0006).
create or replace function min_n_faceoffs() returns int language sql immutable as $$ select 5 $$;
create or replace function min_n_payoff() returns int language sql immutable as $$ select 8 $$;

-- The onboarding payoff: anonymous-callable, returns the n for an exact shade.
-- Client shows the match claim only when evidence_backed; else neutral fallback.
create or replace function payoff_for_variant(p_variant_id uuid)
returns table (n_exact_shade int, n_with_fit int, evidence_backed boolean)
language sql security definer set search_path = public as $$
    select
        coalesce(max(s.owners), 0)::int,
        coalesce((
            select (sum((value)::int))::int
            from agg_variant_stats v2, jsonb_each_text(v2.fit_counts)
            where v2.variant_id = p_variant_id and v2.tone_band is null and v2.skin_type is null
        ), 0),
        coalesce(max(s.owners), 0) >= min_n_payoff()
    from agg_variant_stats s
    where s.variant_id = p_variant_id and s.tone_band is null and s.skin_type is null;
$$;
grant execute on function payoff_for_variant(uuid) to anon, authenticated;
