-- 0014 · GLO-75: the create rung's variant field, persisted.
--
-- The kit's create rung collects four fields — brand, product, variant,
-- category — and 0008's create_personal_product silently dropped the third:
-- it inserted a bare default variant, so "joy · 2.5ml mini" vanished and the
-- created product's shelf row rendered with no variant line.
--
-- The variant text lands in variants.shade_code, which is what feeds
-- variant_label() (0007) — so it renders on the shelf, the item sheet, and
-- the match card with no view changes. Free text in a shade column is the
-- honest mapping for a personal-scope product: the variant is whatever its
-- owner calls it, and nothing personal ever reaches aggregation.
--
-- The 5-arg overload is dropped rather than kept: two overloads make
-- PostgREST's RPC dispatch ambiguous, and the 6-arg version accepts every
-- old call shape through its defaults.

drop function if exists create_personal_product(uuid, uuid, domain_enum, text, text);

create function create_personal_product(
    p_brand_id uuid,
    p_category_id uuid,
    p_domain domain_enum,
    p_name text,
    p_gtin text default null,
    p_variant text default null
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

    insert into variants (product_id, kind, shade_code, submitted_gtin, source)
    values (v_product, 'default', nullif(btrim(p_variant), ''), nullif(btrim(p_gtin), ''), 'user')
    returning id into v_variant;

    return query select v_product, v_variant;
end
$$;
grant execute on function create_personal_product(uuid, uuid, domain_enum, text, text, text) to authenticated;
