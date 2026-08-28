-- Isolation suite · ranking (0003): owner-only, face-off log immutable.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- maya sets up two items and a face-off
select test_as('00000000-0000-0000-0000-000000000001');
select lives_ok($$
    insert into user_items (id, user_id, variant_id, client_id) values
    ('50000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001',
     '40000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000011'),
    ('50000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000001',
     '40000000-0000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000012')
$$, 'maya logs two items');
select lives_ok($$
    insert into face_offs (id, user_id, category_id, winner_item_id, loser_item_id, client_id)
    values ('60000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
            '10000000-0000-0000-0000-000000000002',
            '50000000-0000-0000-0000-000000000011', '50000000-0000-0000-0000-000000000012',
            'bbbbbbbb-0000-0000-0000-000000000001')
$$, 'maya records a face-off');

-- the log is immutable even for its owner (no update/delete policies)
select lives_ok($$ update face_offs set skipped = true where id = '60000000-0000-0000-0000-000000000001' $$,
    'owner update executes');
select is((select skipped from face_offs where id = '60000000-0000-0000-0000-000000000001'), false,
    'face-off log is immutable — update changed nothing');
select lives_ok($$ delete from face_offs where id = '60000000-0000-0000-0000-000000000001' $$,
    'owner delete executes');
select ok(exists(select 1 from face_offs where id = '60000000-0000-0000-0000-000000000001'),
    'face-off log is immutable — delete removed nothing');

-- juli sees nothing and cannot record a face-off over maya's items
select test_as('00000000-0000-0000-0000-000000000002');
select ok(not exists(select 1 from face_offs where id = '60000000-0000-0000-0000-000000000001'),
    'juli cannot read maya''s face-offs');
select throws_ok($$
    insert into face_offs (user_id, category_id, winner_item_id, loser_item_id, client_id)
    values ('00000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002',
            '50000000-0000-0000-0000-000000000011', '50000000-0000-0000-0000-000000000012',
            'bbbbbbbb-0000-0000-0000-000000000002')
$$, '42501', 'new row violates row-level security policy for table "face_offs"',
    'juli cannot face-off maya''s items');

select * from finish();
rollback;
