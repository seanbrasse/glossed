-- Per-item visibility (0053, GLO-272): looks and routines carry their own
-- scope, and the archive semantics Sean asked for hold — a look can be
-- "archived" by scope without unposting, unposted by state without deleting,
-- and the two compose. Fixtures in-txn, rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

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
    ('ca000000-0000-0000-0000-000000000001'::uuid, 'piv-owner@test.local'),
    ('ca000000-0000-0000-0000-000000000002'::uuid, 'piv-friend@test.local'),
    ('ca000000-0000-0000-0000-000000000003'::uuid, 'piv-stranger@test.local')
) as u (id, email);

insert into profiles (user_id, birth_year_month, domains) values
    ('ca000000-0000-0000-0000-000000000001', '1990-01', '{makeup}'),
    ('ca000000-0000-0000-0000-000000000002', '1991-02', '{makeup}'),
    ('ca000000-0000-0000-0000-000000000003', '1992-03', '{makeup}');
-- 0058: a public scope needs a handle, so every fixture owner claims one
-- (directly — the fixture runs as postgres; `claim_handle` is the app's door).
insert into handles (user_id, handle) values
    ('ca000000-0000-0000-0000-000000000001', 'tstca000000001'),
    ('ca000000-0000-0000-0000-000000000002', 'tstca000000002'),
    ('ca000000-0000-0000-0000-000000000003', 'tstca000000003');

-- friends = MUTUAL follow (§1.3, Sean's ruling)
insert into follows (follower_id, followed_id) values
    ('ca000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000002'),
    ('ca000000-0000-0000-0000-000000000002', 'ca000000-0000-0000-0000-000000000001');

-- Two posted looks and two routines, one of each per scope story.
insert into looks (id, user_id, caption, state, posted_at, visibility) values
    ('1c000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001',
     'the public one', 'public', now(), 'public'),
    ('1c000000-0000-0000-0000-000000000002', 'ca000000-0000-0000-0000-000000000001',
     'posted then archived', 'public', now(), 'only_you');
insert into routines (id, user_id, title, slot, visibility) values
    ('2c000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001',
     'friends routine', 'am', 'friends'),
    ('2c000000-0000-0000-0000-000000000002', 'ca000000-0000-0000-0000-000000000001',
     'private routine', 'pm', 'only_you');

-- 1-3 · the stranger: only the public look, neither routine
select test_as('ca000000-0000-0000-0000-000000000003');
select is((select count(*)::int from looks
            where user_id = 'ca000000-0000-0000-0000-000000000001'), 1,
    'a stranger sees exactly the public look');
select is((select caption from looks
            where user_id = 'ca000000-0000-0000-0000-000000000001'), 'the public one',
    'and it is the right one — the archived look is invisible despite state = public');
select is((select count(*)::int from routines
            where user_id = 'ca000000-0000-0000-0000-000000000001'), 0,
    'a friends routine renders nothing to a stranger');

-- 4-5 · the mutual: friends routine opens, only_you stays shut
select test_as('ca000000-0000-0000-0000-000000000002');
select is((select count(*)::int from routines
            where user_id = 'ca000000-0000-0000-0000-000000000001'), 1,
    'a mutual sees the friends routine');
select is((select title from routines
            where user_id = 'ca000000-0000-0000-0000-000000000001'), 'friends routine',
    'and not the private one — per item means PER ITEM');

-- 6 · the owner sees everything, whatever the scopes say
select test_as('ca000000-0000-0000-0000-000000000001');
select is((select count(*)::int from looks
            where user_id = 'ca000000-0000-0000-0000-000000000001'), 2,
    'the owner sees both looks, archived included');

-- 7-8 · ARCHIVE by scope: the owner tightens the public look; the stranger
-- loses it without the look being unposted
update looks set visibility = 'only_you'
 where id = '1c000000-0000-0000-0000-000000000001';
select test_as('ca000000-0000-0000-0000-000000000003');
select is((select count(*)::int from looks
            where user_id = 'ca000000-0000-0000-0000-000000000001'), 0,
    'archiving by scope hides a still-posted look');
select test_as('ca000000-0000-0000-0000-000000000001');
select is((select count(*)::int from looks
            where user_id = 'ca000000-0000-0000-0000-000000000001'
              and state = 'public'), 2,
    'and the owner still holds them as POSTED — archive is scope, not state');

-- 9 · UNPOST by state: back to draft, invisible even at visibility public
update looks set visibility = 'public', state = 'draft'
 where id = '1c000000-0000-0000-0000-000000000001';
select test_as('ca000000-0000-0000-0000-000000000003');
select is((select count(*)::int from looks
            where user_id = 'ca000000-0000-0000-0000-000000000001'), 0,
    'a draft renders nothing to a stranger whatever its scope — state and scope COMPOSE');

-- 10-11 · the owner writes visibility; a stranger cannot
select test_as('ca000000-0000-0000-0000-000000000001');
select lives_ok(
    $$update looks set visibility = 'friends'
       where id = '1c000000-0000-0000-0000-000000000002'$$,
    'the owner moves an item between scopes');
select test_as('ca000000-0000-0000-0000-000000000003');
update looks set visibility = 'public'
 where id = '1c000000-0000-0000-0000-000000000002';
select is((select count(*)::int from looks
            where id = '1c000000-0000-0000-0000-000000000002'
              and visibility = 'public'), 0,
    'a stranger''s scope write moves nothing — RLS filters the row before the SET');

-- 12-13 · the retired surface arms fail closed for everyone
reset role;
select ok(not can_view('ca000000-0000-0000-0000-000000000003',
                       'ca000000-0000-0000-0000-000000000001', 'routines'),
    'the routines surface arm answers only_you now, always');
select ok(not can_view('ca000000-0000-0000-0000-000000000002',
                       'ca000000-0000-0000-0000-000000000001', 'looks'),
    'the looks surface arm too — even for a mutual');

-- 14-15 · defaults: a new item is born private, on both tables
select is((select column_default::text from information_schema.columns
            where table_name = 'looks' and column_name = 'visibility'),
    '''only_you''::scope_enum', 'a new look defaults only_you');
select is((select column_default::text from information_schema.columns
            where table_name = 'routines' and column_name = 'visibility'),
    '''only_you''::scope_enum', 'a new routine defaults only_you');

select * from finish();
rollback;
