-- GLO-272 · Step 1 of filling 0057's ten new groups from what Shopify already
-- told us. The importer's TYPE_RULES (scripts/shopify_import.ts) learned the
-- groups on the same day; this file is the SAME rules as Postgres regexes,
-- because the importer's product insert is `on conflict do nothing` and a
-- re-run never moves a row already filed. Run it once after the rules land,
-- and again after any import that predates them.
--
-- Scope: Shopify-sourced products only (OBF rows carry no product_type worth
-- trusting, and the seed's ten are hand-filed). A product moves only when
-- its `product_type` names one of the ten groups; everything else keeps the
-- category the importer gave it. The CASE order is the TYPE_RULES order —
-- primer before lip, device before tools, lip care before body before
-- exfoliant — and must stay in step with it.
--
-- Moving a product moves its ladder: a ranked item's category_id is read
-- through variants → products. Measured Sept 1 on local before the first run:
-- 173 products, 0 shelf items, 0 rank_positions affected. Check again before
-- running against a database with drives on it:
--
--   select count(*) from rank_positions rp
--     join user_items ui on ui.id = rp.user_item_id
--     join variants v on v.id = ui.variant_id
--    where v.product_id in (select id from products where <the CASE below> is not null);
--
-- Idempotent: the second run finds nothing to move and says so.
begin;

create temp table reclass as
with target as (
    select p.id,
           p.category_id as old_category_id,
           case
               when p.product_type ~* '\mprimer\M' then 'primer'
               when p.product_type ~* '\mdevice\M|gua sha(?! (oil|serum))|roller(?! oil)|led mask|microcurrent|steamer|dermaplan|extractor|cleansing brush|high-frequency' then 'device'
               when p.product_type ~* '\m(brush|brushes|sponge|puff|tweezers|sharpener|tools?)\M' then 'tools'
               when p.product_type ~* '^(?!.*mascara).*\mlash(es)?\M' then 'lashes'
               when p.product_type ~* '\mscalp\M|dandruff|minoxidil|rosemary oil|thickening fibers' then 'scalp'
               when p.product_type ~* 'hair (color|colour|dye|gloss|toner)|color-depositing|demi-permanent|permanent dye|\mbleach\M|\mhenna\M|keratin treatment|relaxer|\mperm\M' then 'haircolor'
               when p.product_type ~* 'setting (spray|powder)|finishing (spray|powder)|loose powder|pressed powder|blotting' then 'setting'
               when p.product_type ~* 'lip\s?(balms?|masks?|scrubs?|treatments?|care)\M|\mbalm\M.*\mlip\M|\mlip\M.*\mbalm\M' then 'lipcare'
               when p.product_type ~* '(?<!face & )\mbody\M|hand cream|foot cream|deodorant|aftershave|shaving cream|depilatory|stretch mark' then 'body'
               when p.product_type ~* 'exfoliat|\mpeel\M|\mscrub\M|\maha\M|\mbha\M|\mpha\M' then 'exfoliant'
           end as slug
      from products p
     where p.source = 'shopify'
       and p.product_type is not null
)
select t.id, t.old_category_id, c.id as new_category_id, c.slug as new_slug, c.domain as new_domain
  from target t
  join categories c on c.slug = t.slug and c.parent_id is null
 where t.slug is not null
   and t.old_category_id <> c.id;

-- What is about to move, by destination — read this before the commit lands.
select new_slug, count(*) as products
  from reclass
 group by new_slug
 order by products desc;

update products p
   set category_id = r.new_category_id,
       domain = r.new_domain,
       updated_at = now()
  from reclass r
 where p.id = r.id;

select count(*) as moved from reclass;

commit;
