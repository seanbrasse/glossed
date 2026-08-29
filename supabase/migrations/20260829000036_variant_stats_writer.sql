-- 0036 · agg_variant_stats gets its writer — cohort-shaped from day one.
-- GLO-157. The table was created in 0004, RLS'd, and read by
-- payoff_for_variant(), and nothing anywhere populated it: empty by
-- construction on local and hosted both (verified Aug 29). Which is why the
-- ALTER below is safe: there has never been a row to migrate.
--
-- Sean's ruling (Aug 29, recorded on GLO-157 and in tech/07 §1): chips are
-- relative facts — the observation is the chip, the meaning comes from who
-- reports it — so the writer is per-cohort from its first run. The all-cohort
-- row ('-:-:-') is one row among many, not the product.

-- ── 1 · hair_pattern joins the cohort key ──────────────────────────────────
-- profiles capture '1a'..'4c' and the aggregate could not see it, so haircare
-- chips — the domain where the cohort axis matters most — were structurally
-- unconditionable (GLO-157 requirement 2). A generated column's expression
-- cannot be altered, so the key is rebuilt; the PK depends on it and is
-- rebuilt with it. climate and concerns[] stay unkeyed DELIBERATELY: axes
-- enter the key by decision, not by drift, and nobody has made the case yet.
alter table agg_variant_stats drop constraint agg_variant_stats_pkey;
alter table agg_variant_stats drop column cohort_key;
alter table agg_variant_stats add column hair_pattern text; -- null = all
alter table agg_variant_stats add column cohort_key text generated always as (
    coalesce(tone_band::text, '-') || ':' || coalesce(skin_type, '-') || ':' || coalesce(hair_pattern, '-')
) stored;
alter table agg_variant_stats add primary key (variant_id, cohort_key);

-- (Deliberately NOT revoking the 0004 tables' default grants, though 0030
-- would suggest it: aggregates_isolation.test.sql records the 0004 contract
-- explicitly — RLS-with-no-policy is the wall, direct reads are silently
-- empty, and a direct insert fails with the RLS error, not a grant error.
-- Two philosophies now coexist (0030's new tables revoke; 0004's rely on
-- RLS) and reconciling them is a decision for a ticket, not a side effect
-- of a writer migration.)

-- ── 2 · the min-n, picked BEFORE the writer ships ──────────────────────────
-- A chip count of 1 in a cohort is one person's opinion wearing the clothes
-- of an aggregate. No chip or fit claim renders below this n — and the
-- cohort split makes small n easy to hit: the same variant can be
-- well-attested overall while every cohort cell is n=1. PROVISIONAL AND
-- UNTUNED, chosen equal to min_n_faceoffs()/min_n_trending() so the evidence
-- surfaces agree on what counts as enough people; BACKLOG carries the row.
create or replace function min_n_chip_claims() returns int language sql immutable as $$ select 5 $$;
grant execute on function min_n_chip_claims() to anon, authenticated;

-- ── 3 · the writer ─────────────────────────────────────────────────────────
-- Full rewrite per run, the refresh_trending() shape: reads identifier-
-- carrying rows under service_role, writes identifier-free cells, clients
-- never touch either side directly. CUBE generates every roll-up cell in one
-- pass; the HAVING filter drops cells keyed on a user's *missing* dimension
-- (a null-skin user belongs to the all-skins roll-up, not to a phantom
-- "skin = null" cohort that would collide with it).
--
-- want_to_try contributes nothing — unworn is not evidence, the same rule as
-- fit capture (GLO-145) and the affinity function (0035). fit_counts keys on
-- the fit value; axis is derivable from it (0009's fit_axis is a generated
-- column of fit), so axes can be regrouped at read time without being stored.
create or replace function refresh_variant_stats() returns void
language sql
security definer
set search_path = public
as $$
delete from agg_variant_stats;
insert into agg_variant_stats (variant_id, tone_band, skin_type, hair_pattern, owners, fit_counts, chip_counts, refreshed_at)
with base as (
    select ui.id as user_item_id, ui.user_id, ui.variant_id,
           pr.tone_band, pr.skin_type, pr.hair_pattern
    from user_items ui
    join profiles pr on pr.user_id = ui.user_id
    where ui.deleted_at is null
      and ui.status <> 'want_to_try'
),
cells as (
    select variant_id, tone_band, skin_type, hair_pattern,
           count(distinct user_id) as owners
    from base
    group by variant_id, cube(tone_band, skin_type, hair_pattern)
    having (grouping(tone_band) = 1     or tone_band is not null)
       and (grouping(skin_type) = 1    or skin_type is not null)
       and (grouping(hair_pattern) = 1 or hair_pattern is not null)
),
fit_cells as (
    select b.variant_id, b.tone_band, b.skin_type, b.hair_pattern, f.fit::text as fit, count(*) as n
    from base b
    join item_fits f on f.user_item_id = b.user_item_id
    group by b.variant_id, f.fit, cube(b.tone_band, b.skin_type, b.hair_pattern)
    having (grouping(b.tone_band) = 1     or b.tone_band is not null)
       and (grouping(b.skin_type) = 1    or b.skin_type is not null)
       and (grouping(b.hair_pattern) = 1 or b.hair_pattern is not null)
),
fit_j as (
    select variant_id, tone_band, skin_type, hair_pattern, jsonb_object_agg(fit, n) as fj
    from fit_cells group by variant_id, tone_band, skin_type, hair_pattern
),
chip_cells as (
    select b.variant_id, b.tone_band, b.skin_type, b.hair_pattern, ec.slug, count(*) as n
    from base b
    join item_chips ic       on ic.user_item_id = b.user_item_id
    join experience_chips ec on ec.id = ic.experience_chip_id
    group by b.variant_id, ec.slug, cube(b.tone_band, b.skin_type, b.hair_pattern)
    having (grouping(b.tone_band) = 1     or b.tone_band is not null)
       and (grouping(b.skin_type) = 1    or b.skin_type is not null)
       and (grouping(b.hair_pattern) = 1 or b.hair_pattern is not null)
),
chip_j as (
    select variant_id, tone_band, skin_type, hair_pattern, jsonb_object_agg(slug, n) as cj
    from chip_cells group by variant_id, tone_band, skin_type, hair_pattern
)
select c.variant_id, c.tone_band, c.skin_type, c.hair_pattern,
       c.owners, coalesce(f.fj, '{}'), coalesce(ch.cj, '{}'), now()
from cells c
left join fit_j f   on f.variant_id = c.variant_id
                   and f.tone_band     is not distinct from c.tone_band
                   and f.skin_type     is not distinct from c.skin_type
                   and f.hair_pattern  is not distinct from c.hair_pattern
left join chip_j ch on ch.variant_id = c.variant_id
                   and ch.tone_band    is not distinct from c.tone_band
                   and ch.skin_type    is not distinct from c.skin_type
                   and ch.hair_pattern is not distinct from c.hair_pattern;
$$;

revoke execute on function refresh_variant_stats() from public, anon, authenticated;
grant execute on function refresh_variant_stats() to service_role;

-- ── 4 · payoff_for_variant learns the third axis ───────────────────────────
-- Its "all-cohort" filter was `tone is null and skin is null`, which now also
-- matches hair cohorts — max(owners) would survive that by luck (the all-row
-- is the superset), but the fit SUM would double-count every fit that also
-- lands in a hair cell. Same signature, same grants, one predicate added in
-- both places.
create or replace function payoff_for_variant(p_variant_id uuid)
returns table (n_exact_shade int, n_with_fit int, evidence_backed boolean)
language sql security definer set search_path = public as $$
    select
        coalesce(max(s.owners), 0)::int,
        coalesce((
            select (sum((value)::int))::int
            from agg_variant_stats v2, jsonb_each_text(v2.fit_counts)
            where v2.variant_id = p_variant_id
              and v2.tone_band is null and v2.skin_type is null and v2.hair_pattern is null
        ), 0),
        coalesce(max(s.owners), 0) >= min_n_payoff()
    from agg_variant_stats s
    where s.variant_id = p_variant_id
      and s.tone_band is null and s.skin_type is null and s.hair_pattern is null;
$$;

-- ── 5 · the refresh runs itself ────────────────────────────────────────────
-- tech/01 §1.3: "refreshed by pg_cron (hourly is fine at this scale)". Off
-- the :00 mark, 0011's idiom. Runs harmlessly against an empty shelf.
select cron.schedule('variant-stats-hourly', '43 * * * *',
    $$select refresh_variant_stats()$$);
