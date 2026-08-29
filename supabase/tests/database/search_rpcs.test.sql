-- search_catalog respects personal scope; record_failed_search counts demand.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- maya finds canonical products and her own personal one
select test_as('00000000-0000-0000-0000-000000000001');
select ok((select count(*) from search_catalog('soft pinch')) >= 1, 'canonical product is findable');
select ok(exists(select 1 from search_catalog('flaxseed')), 'maya finds her own personal product');
select ok(not exists(select 1 from search_catalog('decanted')), 'maya cannot find juli''s personal product');

-- brand-name matching, since people search by brand first
select ok(exists(select 1 from search_catalog('rare beauty')), 'brand name matches');

-- failed searches count demand rather than duplicating rows
select test_as('00000000-0000-0000-0000-000000000002');
select lives_ok($$ select record_failed_search('glow recipe dew drops', 'skincare') $$, 'records a miss');
select record_failed_search('glow recipe dew drops', 'skincare');

-- users write the queue only through the definer function and cannot read it
-- back, so verification runs with privilege restored.
select is((select count(*)::int from failed_searches), 0, 'users cannot read the failed-search queue');
reset role;
select is(
    (select user_count from failed_searches where lower(query) = 'glow recipe dew drops'),
    2, 'a repeat search bumps the count instead of inserting again');


-- the image ride-along (0016): the newest catalog image across the
-- product's variants comes back, and a product with none says null rather
-- than inventing one. The seed carries no image rows, so this creates one
-- inside the rolled-back transaction.
reset role;
insert into variant_images (variant_id, kind, r2_key, width, height)
select v.id, 'catalog', v.id::text || '/cut512.png', 512, 512
from variants v join products p on p.id = v.product_id
where p.name = 'soft pinch liquid blush' limit 1;
select test_as('00000000-0000-0000-0000-000000000001');
select ok(
    exists(select 1 from search_catalog('soft pinch') where catalog_image_key is not null),
    'a product with a catalog image returns its key');
select ok(
    exists(select 1 from search_catalog('flaxseed') where catalog_image_key is null),
    'a product with no image says null, not a made-up key');

-- the category-id ride-along (0017): item_logged needs it, and it must be
-- the product's real category, not merely non-null.
select ok(
    exists(
        select 1 from search_catalog('soft pinch') s
        join products p on p.id = s.id
        where s.category_id = p.category_id),
    'a hit carries its product''s category_id');


-- near_matches (0018): each band's reason is computable, and scope holds.
select test_as('00000000-0000-0000-0000-000000000001');
select is(
    (select why from near_matches('', null, '0810086019999') limit 1),
    'same maker as your scan',
    'a missed scan sharing a GS1 prefix names the maker band');
select ok(
    exists(select 1 from near_matches('soft pinch liquid blish')
           where why = 'similar name — check the shade and size'),
    'a typo lands in the similar-name band');
select ok(
    exists(select 1 from near_matches('rare beauty glitter bomb')
           where why = 'same brand — different product'),
    'a strong brand with a weak name names the brand band');
select ok(
    not exists(select 1 from near_matches('decanted')),
    'near matches cannot see another user''s personal product');

select * from finish();
rollback;
