-- 0017 · Search results carry the category id. GLO-80.
--
-- `item_logged` wants a category_id (tech/06) and the pick path never holds
-- one: the hit carries only `category_slug`, the sheet resolves a variant,
-- and the log fires with nothing to put in the event. The RPC already joins
-- categories for the slug — the id rides along from the same join, and the
-- hit becomes enough for the event on every path that starts from search
-- (Sean's call, session 7: the hit carries it; the enum stays as spec'd).
--
-- A function's return type cannot be altered in place, so this is 0016's
-- move again: drop, identical recreate plus the one column, re-grant.

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
    select p.id, p.name, b.name, c.id, c.slug, p.domain, p.scope,
           ars.n_face_offs,
           case when v.n = 1 then v.label end,
           img.r2_key, img.width, img.height
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
      and (
        p.normalized_name ilike '%' || lower(q) || '%'
        or b.normalized_name ilike '%' || lower(q) || '%'
        or p.normalized_name % lower(q)
        or b.normalized_name % lower(q)
      )
    order by
      greatest(similarity(p.normalized_name, lower(q)), similarity(b.normalized_name, lower(q))) desc,
      p.name;
$$;
grant execute on function search_catalog(text, domain_enum) to anon, authenticated;
