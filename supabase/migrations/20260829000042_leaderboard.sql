-- 0042 · The leaderboard read. GLO-20 (PR-plan item 4's data half).
-- tech/01 §3: mean percentile over the cohort, n_face_offs shown always,
-- and THE render rule — "a row needs ≥5 face-offs in the scope, else it
-- shows 'not enough face-offs yet · k of 5'". PRD §10 adds the spicy half:
-- the lowest-ranked board, with the dislike-chip reasons why.
--
-- The min-n rule is enforced HERE the way 0040 enforces it: a below-min row
-- is RETURNED (hiding it would fake an opinion the data does not have — the
-- kit's own caption) but its CLAIM is nulled: mean_percentile comes back
-- null below min_n_faceoffs(), so no client can accidentally rank what the
-- evidence cannot. n always ships. Ordering puts claimed rows first by
-- their mean (desc, or asc for the lowest board), then the not-yet rows by
-- how close they are.
--
-- p_scope is 'all' or 'yours' — 'yours' resolves the CALLER's cohort
-- server-side (their anchor-shade cohorts for makeup, their hair pattern
-- for haircare), so the client never constructs a cohort key and the
-- §5 disclosure rule has no surface to slip through: you can only ask
-- about cohorts you are in. Fragrance and skincare fall back to 'all',
-- the spec's own scoping.
--
-- Dislike reasons (the lowest board's "why") come from the all-cohort
-- chip_counts (0036), top two dislike-valence chips at or above
-- min_n_chip_claims() — a population claim, so the population threshold.

create function leaderboard(
    p_category uuid,
    p_scope text default 'all',
    p_ascending bool default false,
    p_limit int default 25
)
returns table (
    id uuid,
    name text,
    brand_name text,
    category_id uuid,
    category_slug text,
    domain domain_enum,
    scope catalog_scope,
    n_face_offs int,
    variant_label text,
    catalog_image_key text,
    catalog_image_width int,
    catalog_image_height int,
    mean_percentile numeric,
    n_users int,
    needed int,
    dislike_reasons text[]
)
language sql stable security definer set search_path = public as $$
with cohort_keys as (
    select case
        when p_scope <> 'yours' then 'all'
        when (select c.domain from categories c where c.id = p_category) = 'makeup' then
            coalesce((
                select 'shade:' || usa.variant_id::text
                from user_shade_anchor usa
                where usa.user_id = auth.uid()
                order by usa.captured_at desc
                limit 1
            ), 'all')
        when (select c.domain from categories c where c.id = p_category) = 'haircare' then
            coalesce((
                select 'hair:' || pr.hair_pattern
                from profiles pr
                where pr.user_id = auth.uid() and pr.hair_pattern is not null
            ), 'all')
        else 'all'
    end as k
),
rows_in_scope as (
    select ars.product_id,
           ars.n_face_offs,
           ars.n_users,
           case when ars.n_face_offs >= min_n_faceoffs()
                then ars.mean_percentile end as claim
    from agg_rank_scores ars
    where ars.category_id = p_category
      and ars.cohort_key = (select k from cohort_keys)
),
reasons as (
    -- the lowest board's "why": the product's top dislike chips across the
    -- all-cohort variant stats, thresholded like every population claim
    select v.product_id,
           (array_agg(ec.label order by (kv.value)::int desc))[1:2] as labels
    from agg_variant_stats s
    join variants v on v.id = s.variant_id
    cross join lateral jsonb_each_text(s.chip_counts) as kv(slug, value)
    join experience_chips ec on ec.slug = kv.slug and ec.valence = 'dislike'
    where s.cohort_key = '-:-:-'
      and (kv.value)::int >= min_n_chip_claims()
    group by v.product_id
)
select p.id, p.name, b.name, c.id, c.slug, p.domain, p.scope,
       r.n_face_offs,
       case when v.n = 1 then v.label end,
       img.r2_key, img.width, img.height,
       r.claim,
       r.n_users,
       min_n_faceoffs(),
       case when p_ascending then coalesce(re.labels, '{}') end
from rows_in_scope r
join products p on p.id = r.product_id
join brands b on b.id = p.brand_id
join categories c on c.id = p.category_id
left join reasons re on re.product_id = p.id
left join lateral (
    select count(*) as n,
           min(variant_label(vv.shade_code, vv.size_ml, vv.strength_pct)) as label
    from variants vv where vv.product_id = p.id
) v on true
left join lateral (
    select vi.r2_key, vi.width, vi.height
    from variants vv2
    join variant_images vi on vi.variant_id = vv2.id and vi.kind = 'catalog'
    where vv2.product_id = p.id
    order by vi.created_at desc
    limit 1
) img on true
where p.delisted_at is null and p.merged_into is null
order by (r.claim is null),
         case when p_ascending then r.claim end asc,
         case when not p_ascending then r.claim end desc,
         r.n_face_offs desc,
         p.name
limit p_limit;
$$;

-- 'all' is a population read and anon can see populations (the payoff RPC
-- precedent); 'yours' resolves auth.uid() and simply falls back to 'all'
-- when there is nobody to resolve.
grant execute on function leaderboard(uuid, text, bool, int) to anon, authenticated;
