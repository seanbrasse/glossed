-- Suite · the ladder's server half (0008). GLO-60 §0, GLO-63 §1–2.
-- The assertion that matters is the last one: a product created at the last
-- rung reaches the shelf. That is the whole point of the ladder and it was
-- impossible before this migration.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

select is(normalize_name('Pro Filt''r Soft Matte'), 'pro filtr soft matte',
    'an apostrophe is dropped, not spaced — the seed already writes it this way');
select is(normalize_name('Vitamin-C 10%'), 'vitamin c 10', 'every other separator becomes one space');

select is(normalize_name('   '), null, 'a name with nothing in it is not an empty string');

-- An anonymous caller cannot create anything.
select throws_ok($$ select * from create_personal_product(
    '20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000006', 'haircare', 'ghost gel') $$,
    '42501', 'not authenticated', 'the create rung refuses an anonymous caller');

select test_as('00000000-0000-0000-0000-000000000001');
select throws_ok($$ select * from create_personal_product(
    '20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000006', 'haircare', '  ') $$,
    '22023', 'a product needs a name', 'a blank name is refused before anything is written');

-- maya creates a product after a scan miss and logs it.
create temp table made as
select * from create_personal_product(
    '20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000006',
    'haircare', 'Kinky-Curly Knot Today', '0850000000004');

select is((select count(*)::int from made), 1, 'the create rung returns one product and one variant');
select is((select scope::text from products where id = (select product_id from made)),
    'personal', 'a created product is personal scope');
select is((select created_by from products where id = (select product_id from made)),
    '00000000-0000-0000-0000-000000000001'::uuid, 'ownership comes from the session, not a parameter');
select is((select normalized_name from products where id = (select product_id from made)),
    'kinky curly knot today', 'the server normalizes, so the client cannot drift');
select is((select submitted_gtin from variants where id = (select variant_id from made)),
    '0850000000004', 'the scanned code is kept — it is the strongest identifier a user will ever hand us');
select is((select shade_code from variants where id = (select variant_id from made)),
    null, 'no variant typed means no shade_code — absent, not empty (0014)');

-- 0014: the variant field the frame collects is kept, and renders with no
-- view changes because shade_code is what variant_label() reads.
create temp table made_with_variant as
select * from create_personal_product(
    '20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000006',
    'haircare', 'Kinky-Curly Original', null, 'travel · 59ml');

select is((select variant_label(shade_code, size_ml, strength_pct)
           from variants where id = (select variant_id from made_with_variant)),
    'travel · 59ml', 'the variant the user typed renders through variant_label');
select is((select shade_code from variants where id = (select variant_id from (
    select * from create_personal_product(
        '20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000006',
        'haircare', 'Kinky-Curly Come Clean', null, '   ') ) t)),
    null, 'a whitespace variant stays null rather than becoming an empty label');

-- juli scans the same missing barcode. `variants.gtin` is globally unique, so
-- putting the code there would fail her create against a row she cannot see.
select test_as('00000000-0000-0000-0000-000000000002');
select lives_ok($$ select * from create_personal_product(
    '20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000006',
    'haircare', 'Kinky-Curly Knot Today', '0850000000004') $$,
    'a second user may submit the same scanned code');

-- The match card's two facts.
select test_as('00000000-0000-0000-0000-000000000001');
select results_eq($$
    select n_face_offs, variant_label from search_catalog('pineapple refresh')
    where id = '30000000-0000-0000-0000-000000000003'
$$, $$ values (null::int, '150ml'::text) $$,
   'no aggregate row says nothing rather than zero; a single-variant product names its size');
select is((select variant_label from search_catalog('pro filt') where id = '30000000-0000-0000-0000-000000000001'),
    null, 'a three-shade foundation names no shade rather than one of three');

-- The end of the ladder reaches the shelf. This was impossible before 0008.
insert into user_items (user_id, variant_id, client_id)
values ('00000000-0000-0000-0000-000000000001', (select variant_id from made),
        'cccccccc-0000-0000-0000-000000000001');
select is((select product_name from user_shelf_items
           where variant_id = (select variant_id from made)),
    'Kinky-Curly Knot Today', 'a product created at the last rung reaches the shelf');

select * from finish();
rollback;
