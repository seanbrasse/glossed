-- Routine → collection links + step notes (0052). The isolation template, and
-- 0050's assertion applied to the third pair: A LINK MUST NOT LEAK THE
-- EXISTENCE OF THE THING IT LINKS. Fixtures in-txn, rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

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
    ('ba000000-0000-0000-0000-000000000001'::uuid, 'rc-owner@test.local'),
    ('ba000000-0000-0000-0000-000000000002'::uuid, 'rc-stranger@test.local')
) as u (id, email);

insert into profiles (user_id, birth_year_month, domains) values
    ('ba000000-0000-0000-0000-000000000001', '1990-01', '{skincare}'),
    ('ba000000-0000-0000-0000-000000000002', '1992-06', '{skincare}');

-- The ROUTINE scope is public from the start; the COLLECTION's own visibility
-- is the variable under test, and it begins closed.
insert into privacy_scopes (user_id, routines) values
    ('ba000000-0000-0000-0000-000000000001', 'public');

insert into routines (id, user_id, title, slot) values
    ('2b000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001',
     'a public routine', 'am');
insert into collections (id, user_id, title, visibility) values
    ('3b000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001',
     'a private collection', 'only_you');
insert into collections (id, user_id, title, visibility) values
    ('3b000000-0000-0000-0000-000000000002', 'ba000000-0000-0000-0000-000000000002',
     'the stranger''s collection', 'only_you');

-- 1 · the owner links their own collection to their own routine
select test_as('ba000000-0000-0000-0000-000000000001');
select lives_ok(
    $$insert into routine_collections (routine_id, collection_id)
      values ('2b000000-0000-0000-0000-000000000001', '3b000000-0000-0000-0000-000000000001')$$,
    'the owner links their own collection to their own routine');

-- 2 · the owner reads their own link — a closed scope hides a thing from
-- STRANGERS, never from its owner
select is((select count(*)::int from routine_collections), 1,
    'the owner reads their own link');

-- 3 · own-only writes: someone else's collection is refused even by the
-- routine's owner (0050's stance, before any rows exist under a looser one)
select throws_ok(
    $$insert into routine_collections (routine_id, collection_id)
      values ('2b000000-0000-0000-0000-000000000001', '3b000000-0000-0000-0000-000000000002')$$,
    '42501', null,
    'a link may not annex a collection the caller does not own');

-- 4-6 · THE ASSERTION. The routine is public and readable; the collection is
-- only_you. The stranger must see the ROUTINE and NOTHING ELSE.
select test_as('ba000000-0000-0000-0000-000000000002');
select is((select count(*)::int from routines
            where user_id = 'ba000000-0000-0000-0000-000000000001'), 1,
    'the stranger can read the routine itself — the fixture is doing its job');
select is((select count(*)::int from routine_collections), 0,
    'the link to an only_you collection renders NOTHING to a stranger');
select is((select count(*)::int from collections
            where user_id = 'ba000000-0000-0000-0000-000000000001'), 0,
    'and the collection itself stays invisible — the link leaked nothing');

-- 7-8 · opening the collection opens the link, from the same stranger seat —
-- both halves were the gate, and the second half just turned
select test_as('ba000000-0000-0000-0000-000000000001');
update collections set visibility = 'public'
 where id = '3b000000-0000-0000-0000-000000000001';
select test_as('ba000000-0000-0000-0000-000000000002');
select is((select count(*)::int from routine_collections), 1,
    'routine public AND collection public: the stranger sees the link');
select is((select count(*)::int from collections
            where user_id = 'ba000000-0000-0000-0000-000000000001'), 1,
    'and the collection itself');

-- 9 · the stranger cannot write a link into someone else's routine
select throws_ok(
    $$insert into routine_collections (routine_id, collection_id)
      values ('2b000000-0000-0000-0000-000000000001', '3b000000-0000-0000-0000-000000000002')$$,
    '42501', null,
    'a stranger cannot link into someone else''s routine');

-- 10 · the owner unlinks
select test_as('ba000000-0000-0000-0000-000000000001');
select lives_ok(
    $$delete from routine_collections
       where routine_id = '2b000000-0000-0000-0000-000000000001'$$,
    'the owner unlinks');
select is((select count(*)::int from routine_collections), 0, 'and it is gone');

-- 12-14 · step notes ride the step, bounded, and reach whoever the routine
-- reaches — no scope of their own. Catalog fixtures need the superuser seat —
-- the catalog is not user-writable, which is its own policy doing its job.
reset role;
insert into categories (id, domain, slug, label, is_anchor)
values ('5b000000-0000-0000-0000-000000000001', 'skincare', 'serum-test', 'serum', false)
on conflict do nothing;
insert into brands (id, name, normalized_name)
values ('6b000000-0000-0000-0000-000000000001', 'test brand', 'test brand');
insert into products (id, brand_id, category_id, domain, name, normalized_name)
values ('7b000000-0000-0000-0000-000000000001', '6b000000-0000-0000-0000-000000000001',
        '5b000000-0000-0000-0000-000000000001', 'skincare', 'test serum', 'test serum');
insert into variants (id, product_id)
values ('8b000000-0000-0000-0000-000000000001', '7b000000-0000-0000-0000-000000000001');
insert into user_items (id, user_id, variant_id, status, client_id)
values ('9b000000-0000-0000-0000-000000000001', 'ba000000-0000-0000-0000-000000000001',
        '8b000000-0000-0000-0000-000000000001', 'own', '9b000000-0000-0000-0000-00000000c1a1');

select test_as('ba000000-0000-0000-0000-000000000001');
select lives_ok(
    $$insert into routine_steps (routine_id, user_item_id, position, note)
      values ('2b000000-0000-0000-0000-000000000001', '9b000000-0000-0000-0000-000000000001',
              0, 'three drops, pressed in — never rubbed')$$,
    'a step carries the owner''s note');

select throws_ok(
    $$update routine_steps set note = repeat('x', 501)
       where routine_id = '2b000000-0000-0000-0000-000000000001'$$,
    '23514', null,
    'a 501-character note is refused by the schema, not just the client');

select test_as('ba000000-0000-0000-0000-000000000002');
select is(
    (select note from routine_steps
      where routine_id = '2b000000-0000-0000-0000-000000000001'),
    'three drops, pressed in — never rubbed',
    'the note reaches whoever the routine reaches — the step''s own policy answers');

select * from finish();
rollback;
