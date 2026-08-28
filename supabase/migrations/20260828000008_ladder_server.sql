-- 0008 · What the submission ladder needs from the server. GLO-60 §0, GLO-63 §1–2.
--
-- Two gaps, both found by reading the frames against the schema:
--
--   1. The create rung produces a product that cannot be logged. `products` and
--      `variants` are two inserts with a window between them, and `user_items`
--      references the variant — so a half-finished create leaves a product
--      nobody can see or repair. It wants to be one atomic call.
--   2. The match card's `EvidenceLine` and its variant line have no source.
--      `search_catalog` returns products; the card asks for a face-off count
--      and a shade/size string.

-- ---------------------------------------------------------------------------
-- Normalization, once
-- ---------------------------------------------------------------------------
-- There are three implementations of this rule today and two of them disagree.
-- The seed writes "pro filt''r soft matte" as `pro filtr soft matte`;
-- `PersonalProductDraft.normalize` in Swift maps every non-alphanumeric to a
-- space and would write `pro filt r soft matte`. That is exactly how a catalog
-- acquires two rows for one product, so the rule lives here and the client
-- stops computing it.
--
-- An apostrophe is dropped, not spaced — "filt'r" and "l'oreal" are one word
-- each. Every other run of non-alphanumerics becomes a single space, so
-- "vitamin-c" stays two.
create or replace function normalize_name(p_raw text) returns text
language sql immutable parallel safe set search_path = public as $$
    select nullif(
        btrim(regexp_replace(
            regexp_replace(lower(p_raw), '[''’ʼ]', '', 'g'),
            '[^[:alnum:]]+', ' ', 'g')),
        '');
$$;

-- ---------------------------------------------------------------------------
-- The scanned code a user hands us at the create rung
-- ---------------------------------------------------------------------------
-- Not `variants.gtin`: that column is globally unique, so the second user to
-- scan the same missing barcode would fail to create their own personal
-- product — and the failure would report a conflict with a row they are not
-- allowed to see. `submitted_gtin` is the code as submitted, unverified and
-- deliberately not unique; late-binding promotion (domain.md §3.1) reads it.
alter table variants add column submitted_gtin text;
create index variants_submitted_gtin on variants (submitted_gtin) where submitted_gtin is not null;

-- ---------------------------------------------------------------------------
-- The create rung, atomically
-- ---------------------------------------------------------------------------
-- security definer so the product and its variant are one statement pair the
-- caller cannot interleave — but scope and ownership are set here from
-- auth.uid(), never from a parameter, so definer buys atomicity and not a
-- second permission model.
create or replace function create_personal_product(
    p_brand_id uuid,
    p_category_id uuid,
    p_domain domain_enum,
    p_name text,
    p_gtin text default null
) returns table (product_id uuid, variant_id uuid)
language plpgsql security definer set search_path = public as $$
declare
    v_user uuid := auth.uid();
    v_product uuid;
    v_variant uuid;
begin
    if v_user is null then
        raise exception 'not authenticated' using errcode = '42501';
    end if;
    if normalize_name(p_name) is null then
        raise exception 'a product needs a name' using errcode = '22023';
    end if;

    insert into products (brand_id, category_id, domain, name, normalized_name, scope, created_by, source)
    values (p_brand_id, p_category_id, p_domain, p_name, normalize_name(p_name), 'personal', v_user, 'user')
    returning id into v_product;

    insert into variants (product_id, kind, submitted_gtin, source)
    values (v_product, 'default', nullif(btrim(p_gtin), ''), 'user')
    returning id into v_variant;

    return query select v_product, v_variant;
end
$$;
grant execute on function create_personal_product(uuid, uuid, domain_enum, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The match card's two missing facts
-- ---------------------------------------------------------------------------
-- `n_face_offs` is nullable on purpose. An absent `agg_rank_scores` row means
-- we do not know, which is not the same claim as zero — and a shopper reads
-- "0 face-offs" as "nobody has tried this". The UI omits the line for null.
--
-- `variant_label` is supplied only when the product has exactly one variant.
-- A three-shade foundation cannot say which shade the row is without answering
-- GLO-56, and a row that names one shade of three is worse than a row that
-- names none.
drop function if exists search_catalog(text, domain_enum);
create function search_catalog(q text, p_domain domain_enum default null)
returns table (
    id uuid,
    name text,
    brand_name text,
    category_slug text,
    domain domain_enum,
    scope catalog_scope,
    n_face_offs int,
    variant_label text
)
language sql stable security definer set search_path = public as $$
    select p.id, p.name, b.name, c.slug, p.domain, p.scope,
           ars.n_face_offs,
           case when v.n = 1 then v.label end
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
