-- 0015 · The shelf row learns its catalog image. GLO-74.
--
-- GLO-48's pipeline now writes cut-out catalog images to storage and records
-- them in variant_images; nothing exposed them to a screen. Three appended
-- columns (CREATE OR REPLACE VIEW allows appending, never reordering — the
-- 0013 precedent): the newest catalog-kind image's key, width, and height
-- for the row's variant, or nulls, which the render chain answers with the
-- user's own cutout first and the drawn mock as the floor (PRD §08).
--
-- Width and height ride along because the shelf packs bays by drawn width:
-- a photo's width is its aspect times the drawn height, and a bay packed on
-- the mock's width while rendering a photo's puts rank stickers on top of
-- each other again (GLO-68's shape).
--
-- The key is storage-relative ("<variant_id>/cut512.png"); the app composes
-- the public URL from its own config, so moving the bucket (local storage
-- today, R2 when provisioned) touches no schema.

create or replace view user_shelf_items with (security_invoker = true) as
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
    v.height_mm,
    ui.status,
    ui.started_on,
    ui.note,
    ui.cutout_r2_key,
    ui.created_at        as logged_at,
    rp.position          as rank_position,
    (select count(*)
       from rank_positions rp2
      where rp2.user_id = ui.user_id
        and rp2.category_id = p.category_id
        and rp2.scope_key = 'default')::int as ranked_in_category,
    c.is_anchor,
    ci.r2_key as catalog_image_key,
    ci.width  as catalog_image_width,
    ci.height as catalog_image_height,
    -- Along for the same reason as width/height: with height_mm unset (every
    -- imported variant), the shelf can at least scale by volume — a 236ml
    -- pump should tower over a 30ml foundation (PRD §08). The estimate is the
    -- shelf's rule; the view just stops hiding the number it already has.
    v.size_ml
from user_items ui
join variants v on v.id = ui.variant_id
join products p on p.id = v.product_id
join brands b on b.id = p.brand_id
join categories c on c.id = p.category_id
left join rank_positions rp
       on rp.user_id = ui.user_id
      and rp.user_item_id = ui.id
      and rp.scope_key = 'default'
left join lateral (
    select vi.r2_key, vi.width, vi.height
      from variant_images vi
     where vi.variant_id = ui.variant_id
       and vi.kind = 'catalog'
     order by vi.created_at desc
     limit 1) ci on true
where ui.deleted_at is null;
