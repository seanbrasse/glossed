-- apply_face_off_session: atomic, idempotent, owner-scoped.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

select test_as('00000000-0000-0000-0000-000000000001');
insert into user_items (id, user_id, variant_id, client_id) values
    ('50000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001',
     '40000000-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-0000000000a1'),
    ('50000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000001',
     '40000000-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-0000000000a2');

select lives_ok($$
    select apply_face_off_session(
        '[{"category_id":"10000000-0000-0000-0000-000000000002",
           "winner_item_id":"50000000-0000-0000-0000-0000000000a1",
           "loser_item_id":"50000000-0000-0000-0000-0000000000a2",
           "client_id":"bbbbbbbb-0000-0000-0000-0000000000a1"}]'::jsonb,
        '[{"category_id":"10000000-0000-0000-0000-000000000002",
           "user_item_id":"50000000-0000-0000-0000-0000000000a1","position":1},
          {"category_id":"10000000-0000-0000-0000-000000000002",
           "user_item_id":"50000000-0000-0000-0000-0000000000a2","position":2}]'::jsonb)
$$, 'a session applies');

select is((select count(*)::int from face_offs where user_id = '00000000-0000-0000-0000-000000000001'), 1,
    'the comparison is logged');
select is((select count(*)::int from rank_positions where user_id = '00000000-0000-0000-0000-000000000001'), 2,
    'positions are written');
select is((select user_item_id from rank_positions where position = 1
           and user_id = '00000000-0000-0000-0000-000000000001'),
    '50000000-0000-0000-0000-0000000000a1'::uuid, 'the winner sits at #1');

-- replaying the same session (dropped connection, retry) must not double-count
select apply_face_off_session(
    '[{"category_id":"10000000-0000-0000-0000-000000000002",
       "winner_item_id":"50000000-0000-0000-0000-0000000000a1",
       "loser_item_id":"50000000-0000-0000-0000-0000000000a2",
       "client_id":"bbbbbbbb-0000-0000-0000-0000000000a1"}]'::jsonb,
    '[{"category_id":"10000000-0000-0000-0000-000000000002",
       "user_item_id":"50000000-0000-0000-0000-0000000000a1","position":1},
      {"category_id":"10000000-0000-0000-0000-000000000002",
       "user_item_id":"50000000-0000-0000-0000-0000000000a2","position":2}]'::jsonb);
select is((select count(*)::int from face_offs where user_id = '00000000-0000-0000-0000-000000000001'), 1,
    'replaying a session does not double-count comparisons');
select is((select count(*)::int from rank_positions where user_id = '00000000-0000-0000-0000-000000000001'), 2,
    'positions are rebuilt, not duplicated');

-- a reordering rewrites the list wholesale
select apply_face_off_session('[]'::jsonb,
    '[{"category_id":"10000000-0000-0000-0000-000000000002",
       "user_item_id":"50000000-0000-0000-0000-0000000000a2","position":1},
      {"category_id":"10000000-0000-0000-0000-000000000002",
       "user_item_id":"50000000-0000-0000-0000-0000000000a1","position":2}]'::jsonb);
select is((select user_item_id from rank_positions where position = 1
           and user_id = '00000000-0000-0000-0000-000000000001'),
    '50000000-0000-0000-0000-0000000000a2'::uuid, 'a later result reorders the list');

-- juli cannot rank maya's items even through the function
select test_as('00000000-0000-0000-0000-000000000002');
select throws_ok($$
    select apply_face_off_session(
        '[{"category_id":"10000000-0000-0000-0000-000000000002",
           "winner_item_id":"50000000-0000-0000-0000-0000000000a1",
           "loser_item_id":"50000000-0000-0000-0000-0000000000a2",
           "client_id":"bbbbbbbb-0000-0000-0000-0000000000b9"}]'::jsonb, '[]'::jsonb)
$$, '42501', 'new row violates row-level security policy for table "face_offs"',
    'the function grants no extra reach — RLS still refuses another user''s items');

select * from finish();
rollback;
