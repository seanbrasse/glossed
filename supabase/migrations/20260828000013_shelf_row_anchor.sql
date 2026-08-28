-- 0013 · The shelf row learns whether its category is an anchor. GLO-16.
--
-- The item sheet shows its fit section only for anchor-category products —
-- shade is only evidence where a shade is meant to match skin — and the row
-- had no way to say so. One boolean, appended (CREATE OR REPLACE VIEW allows
-- appending, never reordering), same security posture as 0007.

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
    c.is_anchor
from user_items ui
join variants v on v.id = ui.variant_id
join products p on p.id = v.product_id
join brands b on b.id = p.brand_id
join categories c on c.id = p.category_id
left join rank_positions rp
       on rp.user_id = ui.user_id
      and rp.user_item_id = ui.id
      and rp.scope_key = 'default'
where ui.deleted_at is null;
