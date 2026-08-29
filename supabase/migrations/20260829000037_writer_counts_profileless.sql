-- 0037 · The writer counts profileless users. GLO-173.
--
-- 0036's base CTE reached cohort dims through an INNER join to profiles, so
-- a user with no profile row contributed to no cell at all — including the
-- all-cohort row. Found by running the writer against real local data
-- minutes after merge: 0 rows written over 8 live items, because seeds
-- create no profiles (onboarding does). The fixtures all created profiles,
-- which is exactly why 14 assertions could not see it: fixtures that all
-- satisfy a precondition cannot detect that the precondition is load-bearing.
--
-- A missing profile means all-null cohort dims, and the null-dimension rule
-- already handles those: roll-up cells only. LEFT JOIN is the whole fix.

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
    left join profiles pr on pr.user_id = ui.user_id
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

