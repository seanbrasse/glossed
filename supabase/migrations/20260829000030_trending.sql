-- 0030 · Trending: ownership velocity over a trailing window.
-- GLO-127. docs/tech/02 §4.
--
-- SPEC CORRECTION, recorded here because the next reader will hit it too.
-- tech/02 §4 says trending "reads the identifier-free agg_* tables (0004),
-- never user_items directly." The aggregates that exist cannot answer it:
-- agg_variant_stats carries `owners` as a CUMULATIVE COUNT with no time
-- dimension at all, and velocity is a derivative. There is no window to take.
-- So this migration adds the missing aggregate rather than pretending §4 was
-- already satisfiable.
--
-- The rule §4 was actually protecting is preserved exactly: the CLIENT read
-- path (trending()) touches only identifier-free aggregate rows. The refresh
-- job reads user_items because something has to — that is what an aggregate
-- is. refresh_trending() is service-role territory and is revoked from clients
-- below, the same boundary 0004 draws around its own tables.
--
-- ALSO WORTH KNOWING: agg_variant_stats has no writer anywhere in migrations
-- 0001–0029. It is an empty table with no refresh function, which is why the
-- thresholds below could not be tuned from data. Not fixed here — it is a
-- Phase-1 gap and this is a 1.5 migration.

-- ---------------------------------------------------------------------------
-- Thresholds. Constants in one place so they stay auditable (ADR 0006), the
-- same shape as min_n_faceoffs()/min_n_payoff() in 0004.
--
-- BOTH VALUES ARE PROVISIONAL AND UNTUNED. docs/BACKLOG.md carries the row
-- ("Trending window length + per-skin-type min-n"); Phase-1 log velocity is
-- what sizes them, and there is no Phase-1 log velocity yet. They are written
-- as functions precisely so tuning is a one-line change with a test that
-- fails loudly, not a grep through query bodies.
--
-- The starting points and their (weak) basis:
--   window 30d — one purchase/restock cycle; short enough that "trending"
--                means something, long enough to survive a quiet week.
--   min-n 5    — matched to min_n_faceoffs(), so the two evidence surfaces do
--                not disagree about what counts as enough people.
-- ---------------------------------------------------------------------------
create or replace function trending_window_days() returns int language sql immutable as $$ select 30 $$;
create or replace function min_n_trending()      returns int language sql immutable as $$ select 5 $$;

-- ---------------------------------------------------------------------------
-- The aggregate. Identifier-free by construction: there is no user column and
-- no place to put one.
--
-- Minors' logs are counted here, deliberately. The minors lock is about
-- ATTRIBUTION — can_view refuses to show you a minor's shelf, profile, or
-- name. An unattributed "37 people logged this in 30 days" attributes nothing
-- to anyone, which is the same reason agg_variant_stats counts them. If that
-- ever changes it changes for every aggregate at once, not just this one.
-- ---------------------------------------------------------------------------
create table agg_trending (
    variant_id   uuid not null references variants (id),
    skin_type    text,  -- null = all skin types
    -- nullable cohort dim can't form a PK; a generated key can (0004's pattern)
    cohort_key   text generated always as (coalesce(skin_type, '-')) stored,
    n_logs       int not null default 0,
    window_days  int not null,
    refreshed_at timestamptz not null default now(),
    primary key (variant_id, cohort_key)
);

create index agg_trending_rank on agg_trending (cohort_key, n_logs desc);

alter table agg_trending enable row level security;

-- ---------------------------------------------------------------------------
-- The refresh. service_role only. Reads the identifier-carrying source and
-- writes the identifier-free aggregate — the one place those two touch.
--
-- want_to_try is excluded. Two reasons that agree: §4 says "ownership
-- velocity", and Sean's Aug 29 ruling keeps want_to_try unpublished. A
-- wishlist-velocity surface would be a different feature wearing this one's
-- name.
--
-- Personal-scope products are excluded because they never aggregate
-- (domain.md §3.1). Delisted and merged-away rows are excluded because
-- trending is a discovery surface and sending people at something they cannot
-- buy is worse than showing them nothing.
--
-- UserItem is unique per (user, variant), so a count of rows in the window IS
-- a count of distinct people. One number, one name.
-- ---------------------------------------------------------------------------
create or replace function refresh_trending() returns void
language plpgsql security definer set search_path = public as $$
declare
    v_window int := trending_window_days();
begin
    delete from agg_trending;

    -- The eligible set is defined ONCE. The two cohorts below are the same
    -- rows counted two ways, which is the only way they can be guaranteed
    -- consistent with each other.
    with eligible as (
        select ui.user_id, ui.variant_id, pr.skin_type
          from user_items ui
          join variants v on v.id = ui.variant_id
          join products p on p.id = v.product_id
          left join profiles pr on pr.user_id = ui.user_id
         where ui.deleted_at is null
           and ui.status <> 'want_to_try'
           and ui.created_at >= now() - make_interval(days => v_window)
           and p.scope = 'canonical'
           and p.merged_into is null
           and p.delisted_at is null
    ),
    -- The all-skin-types cohort. Everyone counts, including people with no
    -- skin type on their profile.
    overall as (
        insert into agg_trending (variant_id, skin_type, n_logs, window_days)
        select variant_id, null, count(*)::int, v_window
          from eligible group by variant_id
        returning 1
    )
    -- Per-skin-type cohorts. `skin_type is not null` is load-bearing, not
    -- tidiness: without it a profile with no skin type would land a second row
    -- on the (variant, '-') key and collide with the overall row above.
    insert into agg_trending (variant_id, skin_type, n_logs, window_days)
    select variant_id, skin_type, count(*)::int, v_window
      from eligible
     where skin_type is not null
     group by variant_id, skin_type;
end $$;

-- ---------------------------------------------------------------------------
-- The read. Products, not people — nothing here is scope-gated because
-- nothing here is attributed, so there is no can_view call and no mute filter.
--
-- MIN-N IS RENDERED, NOT HIDDEN (§4, matching the leaderboard in tech/01 §3).
-- A row below the threshold comes back WITH its n and the threshold beside it
-- so the client can say "not enough yet · k of N". Dropping those rows would
-- make a young surface look empty rather than honest, and every claim in UI
-- copy carries its n.
--
-- No explicit tie-break beyond n_logs: below-threshold rows sort under every
-- qualifying row for free, since n < min_n < any qualifying n.
-- ---------------------------------------------------------------------------
create or replace function trending(p_skin_type text default null, p_limit int default 20)
returns table (
    variant_id   uuid,
    brand_name   text,
    product_name text,
    shade_code   text,
    n_logs       int,
    min_n        int,
    meets_min_n  boolean,
    window_days  int,
    refreshed_at timestamptz)
language sql stable security definer set search_path = public as $$
    select t.variant_id, b.name, p.name, v.shade_code,
           t.n_logs, min_n_trending(), t.n_logs >= min_n_trending(),
           t.window_days, t.refreshed_at
      from agg_trending t
      join variants v on v.id = t.variant_id
      join products p on p.id = v.product_id
      join brands   b on b.id = p.brand_id
     where t.cohort_key = coalesce(p_skin_type, '-')
     order by t.n_logs desc, b.name, p.name
     limit least(coalesce(p_limit, 20), 100);
$$;

-- ---------------------------------------------------------------------------
-- Grants.
--
-- agg_trending is revoked EXPLICITLY from anon and authenticated. This table
-- did not exist when 0024 and 0027 swept the tables that did, and that is the
-- whole lesson those two migrations taught: a rule applied to every table that
-- exists is not applied to the next one. Supabase's default privileges hand
-- new tables straight to anon — silence is a grant.
-- ---------------------------------------------------------------------------
revoke all on table agg_trending from anon, authenticated;

revoke execute on function refresh_trending() from public, anon, authenticated;

grant execute on function trending(text, int)     to anon, authenticated;
grant execute on function min_n_trending()        to anon, authenticated;
grant execute on function trending_window_days()  to anon, authenticated;

comment on table agg_trending is
    'Identifier-free ownership velocity over a trailing window. Written only by refresh_trending(), read only through trending(). GLO-127, docs/tech/02 §4.';
comment on function min_n_trending() is
    'PROVISIONAL, untuned — see docs/BACKLOG.md "Trending window length + per-skin-type min-n". Matched to min_n_faceoffs() so the evidence surfaces agree.';
comment on function trending_window_days() is
    'PROVISIONAL, untuned — see docs/BACKLOG.md "Trending window length + per-skin-type min-n". 30d = one restock cycle, chosen not measured.';
