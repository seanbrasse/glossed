-- 0054's two rules: a collection's description is bounded, and a look
-- commits to at most one routine and one collection while the other sides
-- stay many. Fixtures in-txn, rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

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
values ('cb000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'card-owner@test.local', '', now(), '{}', '{}',
        now(), now(), '', '', '', '', '', '', '', '');

insert into profiles (user_id, birth_year_month, domains)
values ('cb000000-0000-0000-0000-000000000001', '1990-01', '{makeup}');

select test_as('cb000000-0000-0000-0000-000000000001');

insert into collections (id, user_id, title) values
    ('c0000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', 'grails'),
    ('c0000000-0000-0000-0000-000000000002', 'cb000000-0000-0000-0000-000000000001', 'spring');
insert into routines (id, user_id, title, slot) values
    ('d0000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', 'am', 'am'),
    ('d0000000-0000-0000-0000-000000000002', 'cb000000-0000-0000-0000-000000000001', 'pm', 'pm');
insert into looks (id, user_id, caption) values
    ('e0000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001', 'one'),
    ('e0000000-0000-0000-0000-000000000002', 'cb000000-0000-0000-0000-000000000001', 'two');

-- 1-3 · the description: writable, clearable, bounded
select lives_ok(
    $$update collections set description = 'everything that survived a repurchase decision'
       where id = 'c0000000-0000-0000-0000-000000000001'$$,
    'the owner writes a description');
select lives_ok(
    $$update collections set description = null
       where id = 'c0000000-0000-0000-0000-000000000001'$$,
    'and clears it — null is a state, not a violation');
select throws_ok(
    $$update collections set description = repeat('x', 501)
       where id = 'c0000000-0000-0000-0000-000000000001'$$,
    '23514', null,
    'a 501-char description is refused by the schema, not just the client');

-- 4-6 · a look commits: the SECOND routine is refused, the FIRST replacing
-- write path (delete then insert) lives
insert into look_routines (look_id, routine_id)
values ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001');
select throws_ok(
    $$insert into look_routines (look_id, routine_id)
      values ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002')$$,
    '23505', null,
    'a second routine on the same look violates one-per-look');
select lives_ok(
    $$delete from look_routines where look_id = 'e0000000-0000-0000-0000-000000000001';
      insert into look_routines (look_id, routine_id)
      values ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002')$$,
    'replace — delete then insert — is the write path that lives');
select is((select routine_id from look_routines
            where look_id = 'e0000000-0000-0000-0000-000000000001'),
    'd0000000-0000-0000-0000-000000000002'::uuid,
    'and the look now holds the replacement, alone');

-- 7-8 · same rule on the collection pair
insert into look_collections (look_id, collection_id)
values ('e0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001');
select throws_ok(
    $$insert into look_collections (look_id, collection_id)
      values ('e0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002')$$,
    '23505', null,
    'a second collection on the same look violates one-per-look');
select is((select count(*)::int from look_collections
            where look_id = 'e0000000-0000-0000-0000-000000000001'), 1,
    'the look still holds exactly one collection');

-- 9-10 · the OTHER sides stay many: two looks may share one routine and one
-- collection — popularity is not a violation
select lives_ok(
    $$insert into look_routines (look_id, routine_id)
      values ('e0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000002')$$,
    'a second look linking the SAME routine lives — the routine side stays many');
select lives_ok(
    $$insert into look_collections (look_id, collection_id)
      values ('e0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001')$$,
    'a second look linking the SAME collection lives — the collection side stays many');

-- 11-13 · the photo swap (0054's third rule): the owner moves r2_key, a
-- stranger's update matches nothing, and the swap leaves id/position alone
insert into look_photos (id, look_id, r2_key, position) values
    ('f0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001',
     'users/cb.../looks/e1/0-old.jpg', 0);
select lives_ok(
    $$update look_photos set r2_key = 'users/cb.../looks/e1/0-new.jpg'
       where id = 'f0000000-0000-0000-0000-000000000001'$$,
    'the owner swaps a photo''s bytes — the row survives, the key moves');
select is((select position from look_photos
            where id = 'f0000000-0000-0000-0000-000000000001'), 0,
    'the slot did not move — a swap is a re-shoot, not a reorder');

-- Back to the definer seat to mint the stranger — an authenticated seat may
-- not write auth.users, and should not be able to.
reset role;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values ('cb000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'card-stranger@test.local', '', now(), '{}', '{}',
        now(), now(), '', '', '', '', '', '', '', '');
select test_as('cb000000-0000-0000-0000-000000000002');
update look_photos set r2_key = 'users/attacker/steal.jpg'
 where id = 'f0000000-0000-0000-0000-000000000001';
select test_as('cb000000-0000-0000-0000-000000000001');
select is((select r2_key from look_photos
            where id = 'f0000000-0000-0000-0000-000000000001'),
    'users/cb.../looks/e1/0-new.jpg',
    'a stranger''s swap moved nothing — RLS filtered the row before the SET');

select * from finish();
rollback;
