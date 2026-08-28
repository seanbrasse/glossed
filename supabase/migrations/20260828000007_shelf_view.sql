-- 0007 · The shelf's one read. GLO-66.
--
-- `user_items` stores a variant id and a status. The shelf draws a named,
-- branded, categorised object standing at its real height, with its rank on it
-- — five joins away. Doing them client-side is N+1 round trips on the app's
-- most-visited screen, so the shelf gets one view and selects it once.
--
-- security_invoker: RLS on every underlying table applies to the caller, so
-- this view grants nothing that a direct select would not. A row whose product
-- the caller cannot read (someone else's personal scope) drops out of the join
-- rather than leaking — losing a shelf row is the safe direction to fail.

-- The shade-or-size line a row writes: "joy · 7.5ml", "10% · 30ml", "150ml".
-- One definition, because search_catalog needs the same string on a match card
-- (GLO-63) and two implementations of one label is how two screens disagree.
create or replace function variant_label(
    p_shade_code text,
    p_size_ml numeric,
    p_strength_pct numeric
) returns text
language sql immutable parallel safe set search_path = public as $$
    select nullif(
        concat_ws(' · ',
            p_shade_code,
            case when p_strength_pct is not null
                 then trim_scale(p_strength_pct)::text || '%' end,
            case when p_size_ml is not null
                 then trim_scale(p_size_ml)::text || 'ml' end),
        '');
$$;

create view user_shelf_items with (security_invoker = true) as
select
    ui.id                as user_item_id,
    ui.user_id,
    ui.variant_id,
    v.product_id,
    p.name               as product_name,
    b.name               as brand_name,
    c.slug               as category_slug,
    c.label              as category_label,
    p.domain,
    p.scope,
    p.benefit_line,
    variant_label(v.shade_code, v.size_ml, v.strength_pct) as variant_label,
    -- Nullable, and deliberately not defaulted here: what a shelf draws for an
    -- object of unknown height is a design decision the shelf owns (GLO-16),
    -- not a number the database should invent.
    v.height_mm,
    ui.status,
    ui.started_on,
    ui.note,
    ui.cutout_r2_key,
    ui.created_at        as logged_at,
    rp.position          as rank_position,
    -- The other half of "#2 of 5". Both halves come from one row so a shelf
    -- can never say you are second of five while showing you three things.
    (select count(*)
       from rank_positions rp2
      where rp2.user_id = ui.user_id
        and rp2.category_id = p.category_id
        and rp2.scope_key = 'default')::int as ranked_in_category
from user_items ui
join variants v on v.id = ui.variant_id
join products p on p.id = v.product_id
join brands b on b.id = p.brand_id
join categories c on c.id = p.category_id
-- The default scope only. Scoped buckets (everyday/full_glam) are a Discover
-- concern; joining every scope_key would multiply each shelf row by its buckets.
left join rank_positions rp
       on rp.user_id = ui.user_id
      and rp.user_item_id = ui.id
      and rp.scope_key = 'default'
where ui.deleted_at is null;

comment on view user_shelf_items is
    'One shelf row, joined. GLO-66. security_invoker — caller RLS applies.';
