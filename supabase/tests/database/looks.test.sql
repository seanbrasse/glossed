-- Looks (0043): the four-test isolation template on all three tables, the
-- minor photo gate asserted directly (a launch requirement, delta 11), the
-- scope-gated public read, and the fail-closed state rule. GLO-197.
-- Fixtures in-txn, rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

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
    ('a8000000-0000-0000-0000-000000000001'::uuid, 'looks-adult@test.local'),
    ('a8000000-0000-0000-0000-000000000002'::uuid, 'looks-viewer@test.local'),
    ('a8000000-0000-0000-0000-000000000003'::uuid, 'looks-minor@test.local')
) as u (id, email);

-- adult + viewer are adults; the third user has NO profiles row, which
-- is_minor_user coalesces to minor (0020's default-deny) — the same shape
-- GLO-182 proved live.
insert into profiles (user_id, birth_year_month, domains) values
    ('a8000000-0000-0000-0000-000000000001', '1990-01', '{makeup}'),
    ('a8000000-0000-0000-0000-000000000002', '1992-06', '{makeup}');

insert into brands (id, name, normalized_name) values
    ('b8000000-0000-0000-0000-000000000001', 'looks brand', 'looks brand');
insert into categories (id, domain, slug, label) values
    ('c8000000-0000-0000-0000-000000000001', 'makeup', 'looks-cat', 'looks cat');
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope) values
    ('d8000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001',
     'c8000000-0000-0000-0000-000000000001', 'makeup', 'looks product', 'looks product', 'canonical');
insert into variants (id, product_id, kind) values
    ('e8000000-0000-0000-0000-000000000001', 'd8000000-0000-0000-0000-000000000001', 'default');

-- 1-5 · the adult owner: full CRUD on own rows
select test_as('a8000000-0000-0000-0000-000000000001');
select lives_ok(
    $$insert into looks (id, user_id, caption)
      values ('18000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000001', 'first look')$$,
    'an adult can create a draft look');
select lives_ok(
    $$insert into look_photos (look_id, r2_key, position)
      values ('18000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000001/l1/0.jpg', 0)$$,
    'the owner can attach a photo');
-- Reshaped by 0049 (GLO-266): the spot goes on a photo, the products go in the
-- spot. TWO statements, not one — look_tag_variants' policy resolves ownership
-- by reading look_tags, and a row inserted in the same statement is not yet
-- visible to it. look_tags_spots.test.sql carries the new contract in full.
select lives_ok(
    $$insert into look_tags (id, look_photo_id, x, y)
      select '28000000-0000-0000-0000-000000000001', p.id, 0.5, 0.5
        from look_photos p where p.look_id = '18000000-0000-0000-0000-000000000001'$$,
    'the owner can pin a tag to their photo');
select lives_ok(
    $$insert into look_tag_variants (look_tag_id, variant_id)
      values ('28000000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001')$$,
    'the owner can pin-tag a variant');
select is(
    (select count(*)::int from looks where user_id = 'a8000000-0000-0000-0000-000000000001'),
    1, 'the owner reads their own draft');

-- 6-9 · another user: a draft is invisible and untouchable
select test_as('a8000000-0000-0000-0000-000000000002');
select is((select count(*)::int from looks), 0, 'a draft is invisible to anyone else');
select is((select count(*)::int from look_photos), 0, 'draft photos are invisible to anyone else');
select lives_ok(
    $$update looks set caption = 'vandalized'
      where id = '18000000-0000-0000-0000-000000000001'$$,
    'the id-guessing update runs and matches nothing');
select test_as('a8000000-0000-0000-0000-000000000001');
select is((select caption from looks where id = '18000000-0000-0000-0000-000000000001'),
    'first look', 'and the caption is untouched');

-- 10-11 · the minor gate, asserted directly on both tables (delta 11)
select test_as('a8000000-0000-0000-0000-000000000003');
select throws_ok(
    $$insert into looks (user_id, caption)
      values ('a8000000-0000-0000-0000-000000000003', 'minor look')$$,
    '42501', null, 'a minor cannot create a look');
select throws_ok(
    $$insert into look_photos (look_id, r2_key, position)
      values ('18000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000003/x/0.jpg', 9)$$,
    '42501', null, 'a minor cannot attach a photo even to an existing look');

-- 12-14 · public read is scope-gated: state alone is not enough
set local role postgres;
update looks set state = 'public', posted_at = now()
 where id = '18000000-0000-0000-0000-000000000001';

select test_as('a8000000-0000-0000-0000-000000000002');
select is((select count(*)::int from looks where state = 'public'),
    0, 'public state with no looks scope grants nothing — can_view default-deny holds');

set local role postgres;
-- looks scope is PER ITEM since 0053; the fixture opens the look's own row below.
update looks set visibility = 'public'
 where user_id = 'a8000000-0000-0000-0000-000000000001';

select test_as('a8000000-0000-0000-0000-000000000002');
select is((select count(*)::int from looks where state = 'public'),
    1, 'public state + public looks scope renders to a stranger');
select is((select count(*)::int from look_tags),
    1, 'the tags ride the parent''s visibility');

-- 15 · a block severs regardless of scope
set local role postgres;
insert into blocks (user_id, blocked_id) values
    ('a8000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000002');
select test_as('a8000000-0000-0000-0000-000000000002');
select is((select count(*)::int from looks where state = 'public'),
    0, 'a block severs the public read in the blocked direction');

-- 16 · fail-closed: an unknown-to-the-policy state renders to nobody else
set local role postgres;
delete from blocks;
update looks set state = 'pending_review'
 where id = '18000000-0000-0000-0000-000000000001';
select test_as('a8000000-0000-0000-0000-000000000002');
select is((select count(*)::int from looks),
    0, 'pending_review is not public — the policy tests public, not not-removed');

-- 17 · anon: no grant at all
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('role', 'anon', true);
select throws_ok('select count(*) from looks', '42501', null,
    'anon has no grant on looks — revoked from the role, not from public');

select * from finish();
rollback;
