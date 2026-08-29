-- 0041 · The dismissal signal: discover's first lesson back to the engine.
-- GLO-181. tech/07 §2's first reserved registry row comes due — and this
-- migration is the registry's proof case: the doc claimed a new signal
-- source costs "one term and one weight ... and one CTE". Count them below.
--
-- A dismissal is a DOMAIN ROW the user owns and can delete — never a mined
-- analytics event (the tech/07 boundary: the user's ledger feeds the engine,
-- their telemetry never does). The rec_dismissed event is emitted by the
-- client alongside the write, for rec-quality measurement; nothing reads it
-- back.

create table rec_dismissals (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id),
    product_id uuid not null references products (id),
    -- the client's reason vocabulary ('own_it' | 'not_for_me' | …); free
    -- text on the wire because the picker owns the words, same as chips'
    -- freetext. Never rendered to anyone but its author.
    reason text,
    created_at timestamptz not null default now(),
    unique (user_id, product_id)
);

alter table rec_dismissals enable row level security;
-- the item_chips shape: own rows, every verb
create policy rec_dismissals_own on rec_dismissals for all
    using (user_id = auth.uid()) with check (user_id = auth.uid());
-- new table, so 0030's rule applies without touching 0004's tested contract:
-- silence is a grant, and anon has no recommendations to dismiss.
revoke all on table rec_dismissals from anon;

-- ── discover forgets what you dismissed ─────────────────────────────────────
-- tech/01 §8: candidates are "minus owned/ranked/dismissed". The exclusion
-- covers the wander too — re-offering a dismissed product as "curiosity"
-- would be the recommendation refusing to take no for an answer.
create or replace function discover_for_user(p_limit int default 12)
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
dismissed as (
    select product_id from rec_dismissals where user_id = auth.uid()
),
aff as (
    select pa.product_id,
           sum(a.shrunk_score)  as score,
           sum(a.n_signals)::int as n
    from affinity_for_user() a
    join product_attributes pa on pa.attribute_chip_id = a.attribute_chip_id
    group by pa.product_id
    having sum(a.shrunk_score) > 0
),
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
      and p.id not in (select product_id from dismissed)
      and coalesce(a.product_id, sr.product_id, ar.product_id, po.product_id) is not null
),
picks as (
    select product_id, basis, basis_n
    from scored
    order by tier_score desc
    limit greatest(p_limit - 1, 1)
),
exploration as (
    select p.id as product_id, 'exploration'::text as basis, 0 as basis_n
    from products p
    where p.scope = 'canonical'
      and p.delisted_at is null
      and p.merged_into is null
      and p.id not in (select product_id from owned)
      and p.id not in (select product_id from dismissed)
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

-- ── the engine learns from no ───────────────────────────────────────────────
-- The registry's promised cost, paid exactly: ONE new CTE (dismissal_weight)
-- and ONE new term in the union. Weight −0.75, the reserved value from
-- tech/07 §2 — between a bare dislike (−1.0) and nothing, because "not for
-- me" said once in a feed is weaker evidence than a dislike logged on a
-- product you actually own. n_signals counts dismissals: they ARE something
-- the user told us, and the receipt stays honest saying so.
create or replace function affinity_for_user(p_domain domain_enum default null)
returns table (
    attribute_chip_id uuid,
    label text,
    raw_score numeric,
    n_signals int,
    w numeric,
    shrunk_score numeric
)
language sql
stable
security invoker
as $$
with my_items as (
    select ui.id, v.product_id, ui.like_state
    from user_items ui
    join variants v on v.id = ui.variant_id
    join products p on p.id = v.product_id
    where ui.user_id = auth.uid()
      and ui.deleted_at is null
      and ui.status <> 'want_to_try'
      and (p_domain is null or p.domain = p_domain)
),
chip_valence as (
    select ic.user_item_id,
           count(*) filter (where ec.valence = 'like')    as like_chips,
           count(*) filter (where ec.valence = 'dislike') as dislike_chips
    from item_chips ic
    join experience_chips ec on ec.id = ic.experience_chip_id
    where ic.user_id = auth.uid()
    group by ic.user_item_id
),
ranked as (
    select rp.user_item_id,
           1.0 - (rp.position - 1)::numeric
               / nullif(count(*) over (partition by rp.category_id, rp.scope_key) - 1, 0)
               as pct
    from rank_positions rp
    where rp.user_id = auth.uid()
),
dismissal_weight as (
    select rd.product_id, -0.75::numeric as weight
    from rec_dismissals rd
    join products p on p.id = rd.product_id
    where rd.user_id = auth.uid()
      and (p_domain is null or p.domain = p_domain)
),
item_weight as (
    select mi.product_id,
           0.25
         + case
               when mi.like_state = 1  and coalesce(cv.like_chips, 0)    > 0 then  1.5
               when mi.like_state = 1                                        then  1.0
               when mi.like_state = -1 and coalesce(cv.dislike_chips, 0) > 0 then -2.0
               when mi.like_state = -1                                       then -1.0
               else 0
           end
         + coalesce(3.0 * (2 * r.pct - 1), 0)
           as weight
    from my_items mi
    left join chip_valence cv on cv.user_item_id = mi.id
    left join ranked r        on r.user_item_id  = mi.id
    union all
    select product_id, weight from dismissal_weight
)
select ac.id                                              as attribute_chip_id,
       ac.label,
       avg(iw.weight)                                     as raw_score,
       count(*)::int                                      as n_signals,
       count(*)::numeric / (count(*) + 10)                as w,
       avg(iw.weight) * count(*)::numeric / (count(*) + 10) as shrunk_score
from item_weight iw
join product_attributes pa on pa.product_id = iw.product_id
join attribute_chips ac    on ac.id = pa.attribute_chip_id
group by ac.id, ac.label
order by shrunk_score desc
$$;
