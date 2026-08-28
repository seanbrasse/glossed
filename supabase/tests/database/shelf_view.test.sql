-- Isolation + shape suite · user_shelf_items (0007). GLO-66.
-- The view is the shelf's only read, so it is tested for three things: that it
-- carries every field a row draws, that it stays owner-only, and that it does
-- not invent the two facts the schema leaves null.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- The label, before any row exists: three shapes and the empty one.
select is(variant_label('joy', 7.5, null), 'joy · 7.5ml', 'shade and size read as the frame writes them');
select is(variant_label(null, 30, 10), '10% · 30ml', 'strength leads size for an active');
select is(variant_label(null, 150.0, null), '150ml', 'a whole number keeps no trailing zero');
select is(variant_label(null, null, null), null, 'a variant with nothing to say says nothing, not an empty line');

-- maya logs the blush (rare beauty · soft pinch · joy · 7.5ml) and ranks it
select test_as('00000000-0000-0000-0000-000000000001');
insert into user_items (id, user_id, variant_id, client_id, started_on)
values ('50000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000001', '2026-08-01');
insert into rank_positions (user_id, category_id, user_item_id, position)
values ('00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
        '50000000-0000-0000-0000-000000000011', 1);

select results_eq($$
    select brand_name, product_name, category_slug, category_label, domain::text,
           variant_label, height_mm, benefit_line, rank_position, ranked_in_category
    from user_shelf_items where user_item_id = '50000000-0000-0000-0000-000000000011'
$$, $$ values ('rare beauty', 'soft pinch liquid blush', 'blush', 'blush', 'makeup',
               'joy · 7.5ml', 70::numeric, 'one dot, blends forever', 1, 1) $$,
   'one select fills every field the bay draws');

-- A personal product is the caller''s own and reads as personal scope.
insert into user_items (id, user_id, variant_id, client_id)
values ('50000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000008', 'bbbbbbbb-0000-0000-0000-000000000002');
select is((select scope::text from user_shelf_items where user_item_id = '50000000-0000-0000-0000-000000000012'),
    'personal', 'maya''s own personal product reaches her shelf');

-- An unranked row admits it rather than reporting position zero.
select is((select rank_position from user_shelf_items where user_item_id = '50000000-0000-0000-0000-000000000012'),
    null, 'an unranked item has no position, not position 0');

-- A soft-deleted row leaves the shelf.
update user_items set deleted_at = now() where id = '50000000-0000-0000-0000-000000000012';
select ok(not exists(select 1 from user_shelf_items where user_item_id = '50000000-0000-0000-0000-000000000012'),
    'a removed item leaves the view');

-- juli sees none of maya''s shelf through the view.
select test_as('00000000-0000-0000-0000-000000000002');
select is((select count(*)::int from user_shelf_items where user_id = '00000000-0000-0000-0000-000000000001'),
    0, 'the view is owner-only');

-- juli''s own log of a canonical variant reads back; the rank count is hers alone.
insert into user_items (id, user_id, variant_id, client_id)
values ('50000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000002',
        '40000000-0000-0000-0000-000000000004', 'bbbbbbbb-0000-0000-0000-000000000003');
select is((select ranked_in_category from user_shelf_items where user_item_id = '50000000-0000-0000-0000-000000000013'),
    0, 'the denominator counts the caller''s ranks, not everyone''s');

-- Height crosses the join untouched. The shelf scales objects by it, so a
-- rounded or defaulted number here would be a design decision made in the
-- wrong place.
select is((select height_mm from user_shelf_items where user_item_id = '50000000-0000-0000-0000-000000000013'),
    70::numeric, 'height comes from the variant, unmodified');

select * from finish();
rollback;
