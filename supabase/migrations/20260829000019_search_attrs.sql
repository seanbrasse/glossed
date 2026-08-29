-- 0019 · Search learns what things ARE. GLO-101 (Sean's ask, Aug 29).
--
-- "korean" should find K-beauty across brands; "lipgloss" should find glosses
-- whose names never say gloss ("ultra glossy lip", "high gloss"). The facts
-- that answer those queries exist at import time and were thrown away:
-- Shopify's product_type dies after category mapping, tags are never read,
-- and nothing records that a brand is Korean. Three columns keep them, and
-- search_catalog learns to use them.
--
-- The matching rule: the old whole-query name/brand paths stand unchanged
-- (nothing that matched yesterday stops matching), OR every token of the
-- query lands somewhere in name / brand / attrs — where attrs is the
-- product's type, tags, brand origin, domain and category slug in one
-- string. Token-AND is what makes "korean skincare" mean korean ∧ skincare
-- instead of either. word_similarity handles the lipgloss↔"lip gloss" gap.
--
-- No index on attrs: ~2k products seq-scan in microseconds; an expression
-- index earns its keep at ~100× that. Return type changes not at all, so
-- clients are untouched.

alter table products
    add column product_type text,
    add column tags text[] not null default '{}';

-- Curated at import (the store map knows where a brand sells from);
-- deliberately a plain lowercase word ("korean", "french") so a search
-- token can hit it without a lookup table.
alter table brands
    add column origin text;

drop function search_catalog(text, domain_enum);

create function search_catalog(q text, p_domain domain_enum default null)
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
    catalog_image_height int
)
language sql stable security definer set search_path = public as $$
    with toks as (
        select tok
        from unnest(regexp_split_to_array(lower(trim(q)), '\s+')) as tok
        where tok <> ''
    )
    select p.id, p.name, b.name, c.id, c.slug, p.domain, p.scope,
           ars.n_face_offs,
           case when v.n = 1 then v.label end,
           img.r2_key, img.width, img.height
    from products p
    join brands b on b.id = p.brand_id
    join categories c on c.id = p.category_id
    cross join lateral (
        select lower(
            coalesce(p.product_type, '') || ' ' ||
            array_to_string(p.tags, ' ') || ' ' ||
            coalesce(b.origin, '') || ' ' ||
            p.domain::text || ' ' || c.slug
        ) as text
    ) attrs
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
      and (
        p.normalized_name ilike '%' || lower(q) || '%'
        or b.normalized_name ilike '%' || lower(q) || '%'
        or p.normalized_name % lower(q)
        or b.normalized_name % lower(q)
        or (
            exists (select 1 from toks)
            and not exists (
                select 1 from toks t
                where not (
                    p.normalized_name ilike '%' || t.tok || '%'
                    or b.normalized_name ilike '%' || t.tok || '%'
                    or attrs.text ilike '%' || t.tok || '%'
                    -- "lipgloss" ⊆ despaced "lip gloss": the compound-word
                    -- gap word_similarity alone leaves under its threshold.
                    or replace(attrs.text, ' ', '') ilike '%' || t.tok || '%'
                    or t.tok <% attrs.text
                )
            )
        )
      )
    order by
      greatest(
          similarity(p.normalized_name, lower(q)),
          similarity(b.normalized_name, lower(q)),
          word_similarity(lower(q), attrs.text)
      ) desc,
      p.name;
$$;
grant execute on function search_catalog(text, domain_enum) to anon, authenticated;
