-- 0005 · Catalog search + failed-search intake. tech/01 §4, §6.
-- Both are security definer so they can read across the catalog and write the
-- failed-search queue, which users have no direct grants on.

-- Type-ahead. Trigram-ranked, scope-aware: canonical products plus the
-- caller's own personal ones, never anyone else's.
create or replace function search_catalog(q text, p_domain domain_enum default null)
returns table (
    id uuid,
    name text,
    brand_name text,
    category_slug text,
    domain domain_enum,
    scope catalog_scope
)
language sql stable security definer set search_path = public as $$
    select p.id, p.name, b.name, c.slug, p.domain, p.scope
    from products p
    join brands b on b.id = p.brand_id
    join categories c on c.id = p.category_id
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

-- Every empty search names exactly which product is missing, weighted by
-- demand. Counts bump on repeat so the weekly fill list ranks itself.
create or replace function record_failed_search(p_query text, p_domain domain_enum default null)
returns void
language sql security definer set search_path = public as $$
    insert into failed_searches (query, domain, user_count, last_seen)
    values (p_query, p_domain, 1, now())
    on conflict (lower(query)) do update
        set user_count = failed_searches.user_count + 1,
            last_seen = now();
$$;
grant execute on function record_failed_search(text, domain_enum) to anon, authenticated;
