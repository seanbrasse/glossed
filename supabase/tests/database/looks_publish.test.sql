-- Publishing a look (0048): the owner's transition, and nothing beyond it.
-- GLO-238's inverted criterion — an owner MAY publish, a stranger may not
-- publish theirs, a minor still cannot create one. Fixtures in-txn, rolled
-- back. Assertions 3-9 all fail against the pre-0048 schema.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

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
    ('a9000000-0000-0000-0000-000000000001'::uuid, 'publish-owner@test.local'),
    ('a9000000-0000-0000-0000-000000000002'::uuid, 'publish-stranger@test.local'),
    ('a9000000-0000-0000-0000-000000000003'::uuid, 'publish-minor@test.local')
) as u (id, email);

-- Owner and stranger are adults; the third has NO profiles row, which
-- is_minor_user coalesces to minor (0020's default-deny).
insert into profiles (user_id, birth_year_month, domains) values
    ('a9000000-0000-0000-0000-000000000001', '1990-01', '{makeup}'),
    ('a9000000-0000-0000-0000-000000000002', '1992-06', '{makeup}');

select test_as('a9000000-0000-0000-0000-000000000001');
insert into looks (id, user_id, caption)
values ('19000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-000000000001', 'a look to publish');

-- 1-4 · the ruled-in transition, both directions, and the timestamp the
-- server owns rather than the client
select lives_ok(
    $$update looks set state = 'public'
      where id = '19000000-0000-0000-0000-000000000001'$$,
    'an owner can publish their own look');
select is((select state::text from looks where id = '19000000-0000-0000-0000-000000000001'),
    'public', 'and the row is public');
select isnt((select posted_at from looks where id = '19000000-0000-0000-0000-000000000001'),
    null, 'posted_at is stamped by the trigger, never sent by the client');

update looks set state = 'draft' where id = '19000000-0000-0000-0000-000000000001';
select is((select posted_at from looks where id = '19000000-0000-0000-0000-000000000001'),
    null, 'unpublishing clears posted_at — the transition reverses');

-- 5-8 · everything the transition is NOT allowed to carry
select throws_ok(
    $$update looks set posted_at = '2000-01-01'
      where id = '19000000-0000-0000-0000-000000000001'$$,
    '42501', null, 'an owner cannot backdate posted_at into the feed''s top slot');
select throws_ok(
    $$update looks set moderation = '{"cleared": true}'::jsonb
      where id = '19000000-0000-0000-0000-000000000001'$$,
    '42501', null, 'an owner cannot write the moderation verdict');
select throws_ok(
    $$update looks set state = 'pending_review'
      where id = '19000000-0000-0000-0000-000000000001'$$,
    '42501', null, 'pending_review is unreachable from a client — no reviewer exists to leave it');
select throws_ok(
    $$update looks set state = 'removed'
      where id = '19000000-0000-0000-0000-000000000001'$$,
    '42501', null, 'removed is the takedown''s word, not the owner''s');

-- 9 · a look is born a draft; publishing is always a second, deliberate write
select throws_ok(
    $$insert into looks (id, user_id, caption, state)
      values ('19000000-0000-0000-0000-000000000002',
              'a9000000-0000-0000-0000-000000000001', 'born public', 'public')$$,
    '42501', null, 'a look cannot be inserted straight to public');

-- 10-11 · a stranger cannot publish someone else's look
select test_as('a9000000-0000-0000-0000-000000000002');
select lives_ok(
    $$update looks set state = 'public'
      where id = '19000000-0000-0000-0000-000000000001'$$,
    'the id-guessing publish runs and matches nothing');
select test_as('a9000000-0000-0000-0000-000000000001');
select is((select state::text from looks where id = '19000000-0000-0000-0000-000000000001'),
    'draft', 'and the look is still a draft');

-- 12 · the gate that did not move (delta 11): can_post_look() is untouched
select test_as('a9000000-0000-0000-0000-000000000003');
select throws_ok(
    $$insert into looks (user_id, caption)
      values ('a9000000-0000-0000-0000-000000000003', 'minor look')$$,
    '42501', null, 'a minor still cannot create a look');

select * from finish();
rollback;
