-- 0018 · The near-match rung gets its own question. GLO-63 item 3.
--
-- The rung's whole instruction is "check the photo, not the name", and the
-- `why` line is what makes that actionable — without it the rung is a second
-- search results list with a different eyebrow. Until now it literally was
-- one: `NearMatchRungModel` re-ran `search_catalog`. This RPC asks the
-- dedupe middle band's real question (tech/01 §4) and says which confusion
-- each candidate is.
--
-- Three reasons, each computable and therefore true — a `why` the data
-- cannot support is a claim, and claims carry their evidence here:
--   band 1 · 'same maker as your scan'   — a missed scan whose GS1 company
--             prefix (first 9 of gtin14) matches a variant we do carry. The
--             strongest signal a miss ever gives us.
--   band 2 · 'similar name — check the shade and size' — trigram-near the
--             words they typed.
--   band 3 · 'same brand — different product' — the brand matched strongly
--             but the product name did not.
-- One row per product, strongest band wins. Same column set as
-- `search_catalog` (0017) plus `why`, so the client's near-match row and
-- search row stay one shape.

create function near_matches(
    q text,
    p_domain domain_enum default null,
    p_gtin text default null
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
    why text
)
language sql stable security definer set search_path = public as $$
    with base as (
        select p.id as pid, p.name as pname, b.name as bname,
               c.id as cid, c.slug as cslug, p.domain as pdomain, p.scope as pscope,
               ars.n_face_offs as nfo,
               case when v.n = 1 then v.label end as vlabel,
               img.r2_key as ikey, img.width as iw, img.height as ih,
               p.normalized_name as pnorm, b.normalized_name as bnorm
        from products p
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
        where p.delisted_at is null
          and p.merged_into is null
          and (p.scope = 'canonical' or p.created_by = auth.uid())
          and (p_domain is null or p.domain = p_domain)
    ),
    banded as (
        select base.*, 1 as band, 1.0::real as score,
               'same maker as your scan' as reason
        from base
        where p_gtin is not null and exists (
            select 1 from variants vg
            where vg.product_id = base.pid
              and vg.gtin14 is not null
              and left(vg.gtin14, 9) = left(lpad(regexp_replace(p_gtin, '\D', '', 'g'), 14, '0'), 9)
        )
        union all
        select base.*, 2, similarity(base.pnorm, lower(q)),
               'similar name — check the shade and size'
        from base
        where coalesce(q, '') <> '' and similarity(base.pnorm, lower(q)) >= 0.3
        union all
        select base.*, 3, similarity(base.bnorm, lower(q)),
               'same brand — different product'
        from base
        where coalesce(q, '') <> ''
          and similarity(base.bnorm, lower(q)) >= 0.4
          and similarity(base.pnorm, lower(q)) < 0.3
    ),
    best as (
        select distinct on (banded.pid) banded.*
        from banded
        order by banded.pid, banded.band, banded.score desc
    )
    select best.pid, best.pname, best.bname, best.cid, best.cslug, best.pdomain,
           best.pscope, best.nfo, best.vlabel, best.ikey, best.iw, best.ih,
           best.reason
    from best
    order by best.band, best.score desc, best.pname
    limit 12;
$$;
grant execute on function near_matches(text, domain_enum, text) to anon, authenticated;
