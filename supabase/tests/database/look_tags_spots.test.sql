-- Look tags after the 0049 reshape: a spot on ONE photo that holds SEVERAL
-- products, the two things 0043's shape could not express. Plus the isolation
-- template on both tables, the fail-closed state rule, and the assertion that
-- 0049's definer predicate and 0043's inline policy give the SAME answer.
-- GLO-266. Fixtures in-txn, rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

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
    ('a9000000-0000-0000-0000-000000000001'::uuid, 'tags-owner@test.local'),
    ('a9000000-0000-0000-0000-000000000002'::uuid, 'tags-viewer@test.local'),
    ('a9000000-0000-0000-0000-000000000003'::uuid, 'tags-minor@test.local')
) as u (id, email);

-- The third user has NO profiles row, which is_minor_user coalesces to minor
-- (0020's default-deny).
insert into profiles (user_id, birth_year_month, domains) values
    ('a9000000-0000-0000-0000-000000000001', '1990-01', '{makeup}'),
    ('a9000000-0000-0000-0000-000000000002', '1992-06', '{makeup}');

insert into brands (id, name, normalized_name) values
    ('b9000000-0000-0000-0000-000000000001', 'tags brand', 'tags brand');
insert into categories (id, domain, slug, label) values
    ('c9000000-0000-0000-0000-000000000001', 'makeup', 'tags-cat', 'tags cat');
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope) values
    ('d9000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-000000000001',
     'c9000000-0000-0000-0000-000000000001', 'makeup', 'tags product', 'tags product', 'canonical');
insert into variants (id, product_id, kind) values
    ('e9000000-0000-0000-0000-000000000001', 'd9000000-0000-0000-0000-000000000001', 'default'),
    ('e9000000-0000-0000-0000-000000000002', 'd9000000-0000-0000-0000-000000000001', 'shade');

-- 1-2 · the owner's look and two photos
select test_as('a9000000-0000-0000-0000-000000000001');
select lives_ok(
    $$insert into looks (id, user_id, caption)
      values ('19000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-000000000001', 'tagged look')$$,
    'an adult can create a draft look');
select lives_ok(
    $$insert into look_photos (id, look_id, r2_key, position) values
        ('f9000000-0000-0000-0000-000000000001', '19000000-0000-0000-0000-000000000001', 'o/l1/0.jpg', 0),
        ('f9000000-0000-0000-0000-000000000002', '19000000-0000-0000-0000-000000000001', 'o/l1/1.jpg', 1)$$,
    'the owner attaches two photos');

-- 3-5 · the reshape's whole point: a spot ON A PHOTO, holding SEVERAL products
select lives_ok(
    $$insert into look_tags (id, look_photo_id, x, y)
      values ('29000000-0000-0000-0000-000000000001', 'f9000000-0000-0000-0000-000000000001', 0.4, 0.6)$$,
    'a tag pins to a photo, not to the look');
select lives_ok(
    $$insert into look_tag_variants (look_tag_id, variant_id, position) values
        ('29000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000001', 0),
        ('29000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000002', 1)$$,
    'one spot holds several products — unrepresentable in 0043');
select throws_ok(
    $$insert into look_tag_variants (look_tag_id, variant_id)
      values ('29000000-0000-0000-0000-000000000001', 'e9000000-0000-0000-0000-000000000001')$$,
    '23505', null, 'the same product cannot sit twice in one spot');

-- 6 · tags across DIFFERENT photos of one look — the "scroll to that photo" case
select lives_ok(
    $$insert into look_tags (id, look_photo_id, x, y)
      values ('29000000-0000-0000-0000-000000000002', 'f9000000-0000-0000-0000-000000000002', 0.1, 0.2)$$,
    'a second tag sits on a different photo of the same look');

-- 7 · the cap is a constraint, not a client constant (GLO-266 §3)
select throws_ok(
    $$insert into look_photos (look_id, r2_key, position)
      values ('19000000-0000-0000-0000-000000000001', 'o/l1/5.jpg', 5)$$,
    '23514', null, 'a sixth photo has nowhere to sit — the cap is 5');

-- 8-10 · another user: a draft discloses nothing, and cannot be written to
select test_as('a9000000-0000-0000-0000-000000000002');
select is((select count(*)::int from look_tags), 0,
    'a draft look''s tags are invisible to anyone else');
select is((select count(*)::int from look_tag_variants), 0,
    'and so are the products in them');
select throws_ok(
    $$insert into look_tags (look_photo_id, x, y)
      values ('f9000000-0000-0000-0000-000000000001', 0.9, 0.9)$$,
    '42501', null, 'a stranger cannot tag a photo they do not own');

-- 11 · the minor gate holds BY CONSTRUCTION: a tag needs a photo, and this is
-- the door a minor cannot pass (delta 11).
select test_as('a9000000-0000-0000-0000-000000000003');
select throws_ok(
    $$insert into look_photos (look_id, r2_key, position)
      values ('19000000-0000-0000-0000-000000000001', 'm/x/2.jpg', 2)$$,
    '42501', null, 'a minor cannot attach a photo, so a minor can own no tag');

-- 12-14 · public read is scope-gated, and the tag rides the parent
set local role postgres;
update looks set state = 'public', posted_at = now()
 where id = '19000000-0000-0000-0000-000000000001';

select test_as('a9000000-0000-0000-0000-000000000002');
select is((select count(*)::int from look_tags), 0,
    'public state with no looks scope grants nothing — can_view default-deny holds');

set local role postgres;
update looks set visibility = 'public'
 where user_id = 'a9000000-0000-0000-0000-000000000001';

select test_as('a9000000-0000-0000-0000-000000000002');
select is((select count(*)::int from look_tags), 2,
    'public state + public looks scope renders both spots to a stranger');
select is((select count(*)::int from look_tag_variants), 2,
    'and the products inside them ride the same visibility');

-- 15 · the anti-drift assertion: 0049's definer predicate and 0043's inline
-- look_photos_public_read must answer the same question the same way.
select is(
    (select look_photo_is_public('f9000000-0000-0000-0000-000000000001')),
    (select exists (select 1 from look_photos where id = 'f9000000-0000-0000-0000-000000000001')),
    'look_photo_is_public agrees with 0043''s inline policy on a visible photo');

-- 16 · a block severs regardless of scope
set local role postgres;
insert into blocks (user_id, blocked_id) values
    ('a9000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-000000000002');
select test_as('a9000000-0000-0000-0000-000000000002');
select is((select count(*)::int from look_tags), 0,
    'a block severs the tag read in the blocked direction');

-- 17 · fail closed: a state the policy does not name renders to nobody
set local role postgres;
delete from blocks;
update looks set state = 'pending_review'
 where id = '19000000-0000-0000-0000-000000000001';
select test_as('a9000000-0000-0000-0000-000000000002');
select is((select count(*)::int from look_tags), 0,
    'pending_review is not public — the policy tests public, not not-removed');

-- 18 · anon has no grant at all
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select set_config('role', 'anon', true);
select throws_ok('select count(*) from look_tag_variants', '42501', null,
    'anon has no grant — revoked from the role, not from public');

select * from finish();
rollback;
