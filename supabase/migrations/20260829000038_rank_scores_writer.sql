-- 0038 · agg_rank_scores gets its writer. GLO-174.
--
-- The GLO-157 gap-shape, in its sibling: created in 0004, written by nothing
-- — and this one has had LIVE READERS all along. search_catalog (0016/0017/
-- 0019) and near_matches (0018) left-join it on cohort_key = 'all', so the
-- search popularity signal has been silently zero since search shipped.
-- Nothing looked broken, because left joins don't.
--
-- Aggregation is tech/01 §3 verbatim:
--   percentile   = 1 − (position−1)/(list_len−1), per user per category,
--                  scope 'default' (the only scope in use — a scope column
--                  on this table is a decision, not a drift).
--                  SINGLE-ITEM LISTS CONTRIBUTE NOTHING (r is undefined).
--   mean         = mean over the cohort's users; n_users = distinct
--                  contributors; n_face_offs = non-skipped face-offs
--                  touching the product in-cohort, both sides counted.
--   cohorts (V1) = 'all' everywhere · 'shade:<anchor variant>' for MAKEUP
--                  (users sharing that anchor variant, via user_shade_anchor)
--                  · 'hair:<pattern>' for HAIRCARE. Fragrance and skincare
--                  stay 'all'-only — the spec says so, the shelf says so.
--
-- Everything is stored, including n=1: the ≥5-face-offs rule ("not enough
-- face-offs yet · k of 5") gates the RENDER, never the data — 0036's
-- principle. min_n_faceoffs() (0004) is already the constant the render
-- uses; this migration adds no threshold because the right one exists.
--
-- GLO-173's lesson is one migration old, so said aloud: nothing here makes
-- profiles a precondition. Percentiles and face-offs never touch profiles;
-- hair cohorts read them, and a user without a pattern simply has no hair
-- cohort — they still count in 'all' and any shade cohort they anchor.

create or replace function refresh_rank_scores() returns void
language sql
security definer
set search_path = public
as $$
delete from agg_rank_scores;
insert into agg_rank_scores (product_id, category_id, cohort_key, n_face_offs, n_users, mean_percentile, refreshed_at)
with scored as (
    -- each user's percentile per product per category; single-item lists
    -- yield null via nullif and are dropped in the same breath
    select * from (
        select rp.user_id, rp.category_id, v.product_id,
               1.0 - (rp.position - 1)::numeric
                   / nullif(count(*) over (partition by rp.user_id, rp.category_id) - 1, 0) as pct
        from rank_positions rp
        join user_items ui on ui.id = rp.user_item_id
        join variants v    on v.id = ui.variant_id
        where rp.scope_key = 'default'
          and ui.deleted_at is null
    ) s where pct is not null
),
fo as (
    -- both sides of every real face-off; skips are not evidence
    select f.user_id, f.category_id, v.product_id, count(*) as n
    from face_offs f
    cross join lateral (values (f.winner_item_id), (f.loser_item_id)) as pair(item_id)
    join user_items ui on ui.id = pair.item_id
    join variants v    on v.id = ui.variant_id
    where not f.skipped
      and f.scope_key = 'default'
    group by f.user_id, f.category_id, v.product_id
),
contributors as (
    select user_id from scored union select user_id from fo
),
user_cohorts as (
    select user_id, 'all'::text as cohort_key from contributors
    union
    select usa.user_id, 'shade:' || usa.variant_id::text
    from user_shade_anchor usa join contributors using (user_id)
    union
    select pr.user_id, 'hair:' || pr.hair_pattern
    from profiles pr join contributors using (user_id)
    where pr.hair_pattern is not null
),
-- a cohort applies to a category only where the spec says it does
applicable as (
    select uc.user_id, uc.cohort_key, c.id as category_id
    from user_cohorts uc
    cross join categories c
    where uc.cohort_key = 'all'
       or (uc.cohort_key like 'shade:%' and c.domain = 'makeup')
       or (uc.cohort_key like 'hair:%'  and c.domain = 'haircare')
),
pct_agg as (
    select s.product_id, s.category_id, a.cohort_key,
           avg(s.pct)                as mean_percentile,
           count(distinct s.user_id) as n_users
    from scored s
    join applicable a on a.user_id = s.user_id and a.category_id = s.category_id
    group by s.product_id, s.category_id, a.cohort_key
),
fo_agg as (
    select f.product_id, f.category_id, a.cohort_key, sum(f.n)::int as n_face_offs
    from fo f
    join applicable a on a.user_id = f.user_id and a.category_id = f.category_id
    group by f.product_id, f.category_id, a.cohort_key
)
select coalesce(p.product_id,  f.product_id),
       coalesce(p.category_id, f.category_id),
       coalesce(p.cohort_key,  f.cohort_key),
       coalesce(f.n_face_offs, 0),
       coalesce(p.n_users, 0),
       p.mean_percentile,
       now()
from pct_agg p
full join fo_agg f
  on f.product_id = p.product_id
 and f.category_id = p.category_id
 and f.cohort_key = p.cohort_key;
$$;

revoke execute on function refresh_rank_scores() from public, anon, authenticated;
grant execute on function refresh_rank_scores() to service_role;

-- hourly, off the :00 mark, 0011's idiom — a different minute than 0036's
-- :43 so the two rewrites never contend.
select cron.schedule('rank-scores-hourly', '53 * * * *',
    $$select refresh_rank_scores()$$);
