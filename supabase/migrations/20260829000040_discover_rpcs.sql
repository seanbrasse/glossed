-- 0040 · The discover read path: Stage 0/1 picks + the crosswalk. GLO-20
-- (PR-plan item 2; item 1 was 0036–0039). tech/01 §8, tech/07 §3–4.
--
-- discover_for_user() returns search_catalog's EXACT column set plus
-- (basis, basis_n) — the NearMatch precedent: one row shape, one client
-- decoder. basis is a machine key ('taste' | 'shade' | 'everyone' |
-- 'popular' | 'exploration'); the client owns the copy, because copy is a
-- design decision and SQL is the wrong place to freeze one.
--
-- Stage 0 and Stage 1 are ONE query, per the spec's own line: "nothing
-- changes architecturally between stages." A user with affinity signals
-- gets taste-ranked rows first; a user with none falls through to their
-- shade cohort, then everyone, then plain popularity. Tiers, not modes.
--
-- The min-n rule is enforced HERE, not in the client (GLO-20 acceptance):
--   · population claims (shade / everyone / popular) render only at or
--     above their thresholds — min_n_faceoffs() for rank cohorts,
--     min_n_chip_claims() for ownership counts.
--   · taste rows are claims about the CALLER's own logs, not about a
--     population — min-n does not apply to what you told us yourself; the
--     n returned is how many of your signals back the pick, and the client
--     renders it as exactly that.
--
-- The exploration slot is real and labeled (§8: one explicit slot against
-- the filter bubble). It rotates DAILY by hashing (product id, date) —
-- deterministic within a day, so a stable function stays honestly stable
-- and the slot doesn't reshuffle on every pull-to-refresh.
--
-- An empty result is legitimate (a brand-new user on an empty catalog);
-- "never a blank screen" is the VIEW's obligation — it still knows your
-- anchor — not a reason to fabricate rows below min-n.

create function discover_for_user(p_limit int default 12)
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
    basis text,
    basis_n int
)
language sql stable security definer set search_path = public as $$
with owned as (
    select v.product_id
    from user_items ui join variants v on v.id = ui.variant_id
    where ui.user_id = auth.uid() and ui.deleted_at is null
),
-- Stage 1: the caller's affinity vector (0035, invoker semantics preserved:
-- auth.uid() resolves from the JWT even under definer), summed per product
-- over its attributes.
aff as (
    select pa.product_id,
           sum(a.shrunk_score)  as score,
           sum(a.n_signals)::int as n
    from affinity_for_user() a
    join product_attributes pa on pa.attribute_chip_id = a.attribute_chip_id
    group by pa.product_id
    having sum(a.shrunk_score) > 0
),
-- Stage 0: the caller's shade cohort, then everyone — min-n enforced.
my_shade_keys as (
    select distinct 'shade:' || variant_id::text as k
    from user_shade_anchor where user_id = auth.uid()
),
shade_rank as (
    select ars.product_id, max(ars.mean_percentile) as pctl, max(ars.n_face_offs)::int as n
    from agg_rank_scores ars
    where ars.cohort_key in (select k from my_shade_keys)
      and ars.n_face_offs >= min_n_faceoffs()
      and ars.mean_percentile is not null
    group by ars.product_id
),
all_rank as (
    select ars.product_id, max(ars.mean_percentile) as pctl, max(ars.n_face_offs)::int as n
    from agg_rank_scores ars
    where ars.cohort_key = 'all'
      and ars.n_face_offs >= min_n_faceoffs()
      and ars.mean_percentile is not null
    group by ars.product_id
),
pop as (
    select v.product_id, max(s.owners)::int as owners
    from agg_variant_stats s join variants v on v.id = s.variant_id
    where s.cohort_key = '-:-:-'
      and s.owners >= min_n_chip_claims()
    group by v.product_id
),
-- one basis per product: the best tier that has something true to say
scored as (
    select p.id as product_id,
           case when a.product_id  is not null then 'taste'
                when sr.product_id is not null then 'shade'
                when ar.product_id is not null then 'everyone'
                when po.product_id is not null then 'popular'
           end as basis,
           coalesce(a.n, sr.n, ar.n, po.owners) as basis_n,
           case when a.product_id  is not null then 400 + a.score
                when sr.product_id is not null then 300 + sr.pctl
                when ar.product_id is not null then 200 + ar.pctl
                else 100 + least(po.owners, 99) / 100.0
           end as tier_score
    from products p
    left join aff        a on a.product_id  = p.id
    left join shade_rank sr on sr.product_id = p.id
    left join all_rank   ar on ar.product_id = p.id
    left join pop        po on po.product_id = p.id
    where p.scope = 'canonical'
      and p.delisted_at is null
      and p.merged_into is null
      and p.id not in (select product_id from owned)
      and coalesce(a.product_id, sr.product_id, ar.product_id, po.product_id) is not null
),
picks as (
    select product_id, basis, basis_n
    from scored
    order by tier_score desc
    limit greatest(p_limit - 1, 1)
),
-- the labeled wander: one canonical product outside today's picks and the
-- caller's shelf, rotating daily, never pretending to be a recommendation
exploration as (
    select p.id as product_id, 'exploration'::text as basis, 0 as basis_n
    from products p
    where p.scope = 'canonical'
      and p.delisted_at is null
      and p.merged_into is null
      and p.id not in (select product_id from owned)
      and p.id not in (select product_id from picks)
    order by md5(p.id::text || current_date::text)
    limit 1
),
chosen as (
    select product_id, basis, basis_n, row_number() over () as ord from picks
    union all
    select product_id, basis, basis_n, 1000 from exploration
)
select p.id, p.name, b.name, c.id, c.slug, p.domain, p.scope,
       ars.n_face_offs,
       case when v.n = 1 then v.label end,
       img.r2_key, img.width, img.height,
       ch.basis, ch.basis_n
from chosen ch
join products p on p.id = ch.product_id
join brands b on b.id = p.brand_id
join categories c on c.id = p.category_id
left join agg_rank_scores ars
       on ars.product_id = p.id and ars.category_id = p.category_id and ars.cohort_key = 'all'
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
order by ch.ord;
$$;

-- The crosswalk card (§8): "people who wear <your anchor> also wear X", the
-- n always shown, and NEVER "your match" — the copy rule the client owns,
-- the data rule this function owns. Thresholded on the same 5 the other
-- people-count claims use (min_n_chip_claims): a crosswalk pair is a claim
-- about people, and the surfaces should agree on what counts as enough.
create function crosswalk_for_user(p_limit int default 6)
returns table (
    anchor_variant_id uuid,
    anchor_label text,
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
    n int
)
language sql stable security definer set search_path = public as $$
with mine as (
    select distinct variant_id from user_shade_anchor where user_id = auth.uid()
),
partners as (
    select m.variant_id as anchor_id,
           case when sc.variant_a = m.variant_id then sc.variant_b else sc.variant_a end as partner_id,
           sc.n
    from shade_cooccurrence sc
    join mine m on m.variant_id in (sc.variant_a, sc.variant_b)
    where sc.n >= min_n_chip_claims()
),
owned as (
    select v.product_id
    from user_items ui join variants v on v.id = ui.variant_id
    where ui.user_id = auth.uid() and ui.deleted_at is null
)
select pt.anchor_id,
       (select b2.name || ' ' || coalesce(variant_label(av.shade_code, av.size_ml, av.strength_pct), '')
        from variants av join products ap on ap.id = av.product_id join brands b2 on b2.id = ap.brand_id
        where av.id = pt.anchor_id),
       p.id, p.name, b.name, c.id, c.slug, p.domain, p.scope,
       ars.n_face_offs,
       variant_label(pv.shade_code, pv.size_ml, pv.strength_pct),
       img.r2_key, img.width, img.height,
       pt.n
from partners pt
join variants pv on pv.id = pt.partner_id
join products p on p.id = pv.product_id
join brands b on b.id = p.brand_id
join categories c on c.id = p.category_id
left join agg_rank_scores ars
       on ars.product_id = p.id and ars.category_id = p.category_id and ars.cohort_key = 'all'
left join lateral (
    select vi.r2_key, vi.width, vi.height
    from variant_images vi
    where vi.variant_id = pv.id and vi.kind = 'catalog'
    order by vi.created_at desc
    limit 1
) img on true
where p.delisted_at is null and p.merged_into is null
  and p.id not in (select product_id from owned)
order by pt.n desc
limit p_limit;
$$;

-- Anon has no shelf, no anchor, no taste — both are caller-shaped reads.
revoke all on function discover_for_user(int)  from public, anon;
revoke all on function crosswalk_for_user(int) from public, anon;
grant execute on function discover_for_user(int)  to authenticated;
grant execute on function crosswalk_for_user(int) to authenticated;
