-- Look → routine / collection links (0050). The isolation template on both
-- tables, and the assertion this ticket exists for: A LINK MUST NOT LEAK THE
-- EXISTENCE OF THE THING IT LINKS. A public look that links an only_you routine
-- renders nothing to a stranger — no name, no row, no count. GLO-263.
-- Fixtures in-txn, rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       email, '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''
from (values
    ('aa000000-0000-0000-0000-000000000001'::uuid, 'links-owner@test.local'),
    ('aa000000-0000-0000-0000-000000000002'::uuid, 'links-stranger@test.local')
) as u (id, email);

insert into profiles (user_id, birth_year_month, domains) values
    ('aa000000-0000-0000-0000-000000000001', '1990-01', '{makeup}'),
    ('aa000000-0000-0000-0000-000000000002', '1992-06', '{makeup}');

-- The owner's looks scope is public from the start; the ROUTINE and COLLECTION
-- scopes are the variables under test, and they begin closed.
insert into privacy_scopes (user_id, looks, routines) values
    ('aa000000-0000-0000-0000-000000000001', 'public', 'only_you');

insert into looks (id, user_id, caption, state, posted_at) values
    ('1a000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001',
     'a public look', 'public', now());
insert into routines (id, user_id, title, slot) values
    ('2a000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001',
     'my private routine', 'am');
insert into collections (id, user_id, title, visibility) values
    ('3a000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001',
     'my private collection', 'only_you');

-- 1-2 · the owner links their own routine and their own collection
select test_as('aa000000-0000-0000-0000-000000000001');
select lives_ok(
    $$insert into look_routines (look_id, routine_id)
      values ('1a000000-0000-0000-0000-000000000001', '2a000000-0000-0000-0000-000000000001')$$,
    'the owner links their own routine to their own look');
select lives_ok(
    $$insert into look_collections (look_id, collection_id)
      values ('1a000000-0000-0000-0000-000000000001', '3a000000-0000-0000-0000-000000000001')$$,
    'the owner links their own collection to their own look');

-- 3-4 · the owner still sees their own links — a closed scope hides a thing
-- from STRANGERS, never from its owner
select is((select count(*)::int from look_routines), 1,
    'the owner reads their own routine link');
select is((select count(*)::int from look_collections), 1,
    'the owner reads their own collection link');

-- 5-8 · THE ASSERTION. The look is public and readable; the routine and the
-- collection are only_you. The stranger must see the LOOK and NOTHING ELSE.
select test_as('aa000000-0000-0000-0000-000000000002');
select is((select count(*)::int from looks where state = 'public'), 1,
    'the stranger can read the look itself — the fixture is doing its job');
select is((select count(*)::int from look_routines), 0,
    'a private routine linked by a PUBLIC look is invisible to a stranger');
select is((select count(*)::int from look_collections), 0,
    'a private collection linked by a PUBLIC look is invisible to a stranger');
select is((select count(*)::int from routines), 0,
    'and the routine itself stays invisible — the link opened no side door');

-- 9-10 · opening the scope is what reveals it, so the guard is the scope and
-- not an accident of the fixture
set local role postgres;
update privacy_scopes set routines = 'public'
 where user_id = 'aa000000-0000-0000-0000-000000000001';
update collections set visibility = 'public'
 where id = '3a000000-0000-0000-0000-000000000001';
select test_as('aa000000-0000-0000-0000-000000000002');
select is((select count(*)::int from look_routines), 1,
    'a public routine linked by a public look DOES render');
select is((select count(*)::int from look_collections), 1,
    'a public collection linked by a public look DOES render');

-- 11-12 · the other half fails closed too: the LOOK going unreadable hides the
-- link even though both linked things stay public
set local role postgres;
update looks set state = 'draft', posted_at = null
 where id = '1a000000-0000-0000-0000-000000000001';
select test_as('aa000000-0000-0000-0000-000000000002');
select is((select count(*)::int from look_routines), 0,
    'an unpublished look hides its links — state is tested as public, not as not-removed');
select is((select count(*)::int from look_collections), 0,
    'and the collection link with it');

-- 13 · a block severs regardless of every scope involved
set local role postgres;
update looks set state = 'public', posted_at = now()
 where id = '1a000000-0000-0000-0000-000000000001';
insert into blocks (user_id, blocked_id) values
    ('aa000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000002');
select test_as('aa000000-0000-0000-0000-000000000002');
select is((select count(*)::int from look_routines), 0,
    'a block severs the link read in the blocked direction');

-- 14-15 · a stranger cannot write links onto someone else's look
set local role postgres;
delete from blocks;
select test_as('aa000000-0000-0000-0000-000000000002');
select throws_ok(
    $$insert into look_routines (look_id, routine_id)
      values ('1a000000-0000-0000-0000-000000000001', '2a000000-0000-0000-0000-000000000001')$$,
    '42501', null, 'a stranger cannot link anything to a look they do not own');
select lives_ok(
    $$delete from look_routines where look_id = '1a000000-0000-0000-0000-000000000001'$$,
    'the id-guessing delete runs and matches nothing');

-- 16 · anon has no grant at all
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('role', 'anon', true);
select throws_ok('select count(*) from look_routines', '42501', null,
    'anon has no grant — revoked from the role, not from public');

select * from finish();
rollback;
