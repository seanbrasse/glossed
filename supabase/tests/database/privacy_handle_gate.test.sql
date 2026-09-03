-- A public scope needs a handle (0058, GLO-258). tech/02 §3.1: a handle is
-- "chosen at first publish"; the profile's copy says "nothing of yours is
-- public until you pick one". This is the instrument that makes that sentence
-- true at the database.
--
-- Leak arm first, on purpose (the owner_scoped_reads rule): the owner here has
-- set every scope and visibility to public, holds a public collection, a
-- public routine and a published look, and has NO handle. A stranger must see
-- nothing. Then the owner claims a handle — the same RPC the app calls — and
-- the same stranger sees all of it. Fixtures in-txn, rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

select set_config('role', 'postgres', true);
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values
    ('0058a0de-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'handle-gate-owner@test.local', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''),
    ('0058a0de-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'handle-gate-viewer@test.local', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');
-- Both adults: a minor is invisible for its own reason and would make every
-- leak-arm assertion pass for the wrong one.
insert into profiles (user_id, birth_year_month, domains) values
    ('0058a0de-0000-0000-0000-000000000001', '1990-01', '{makeup}'),
    ('0058a0de-0000-0000-0000-000000000002', '1991-02', '{makeup}');
insert into privacy_scopes (user_id, shelf, rankings, discoverable) values
    ('0058a0de-0000-0000-0000-000000000001', 'public', 'public', true);
insert into brands (id, name, normalized_name) values
    ('0058a0de-0000-0000-0000-0000000000b1', 'handle gate brand', 'handle gate brand');
insert into categories (id, domain, slug, label) values
    ('0058a0de-0000-0000-0000-0000000000c1', 'makeup', 'handle-gate-cat', 'handle gate cat');
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope) values
    ('0058a0de-0000-0000-0000-0000000000d1', '0058a0de-0000-0000-0000-0000000000b1',
     '0058a0de-0000-0000-0000-0000000000c1', 'makeup', 'handle gate product', 'handle gate product', 'canonical');
insert into variants (id, product_id, kind) values
    ('0058a0de-0000-0000-0000-0000000000e1', '0058a0de-0000-0000-0000-0000000000d1', 'default');
insert into user_items (id, user_id, variant_id, status, client_id) values
    ('0058a0de-0000-0000-0000-0000000000f1', '0058a0de-0000-0000-0000-000000000001',
     '0058a0de-0000-0000-0000-0000000000e1', 'own', '0058a0de-0000-0000-0000-0000000000f1');
insert into rank_positions (user_id, category_id, scope_key, user_item_id, position) values
    ('0058a0de-0000-0000-0000-000000000001', '0058a0de-0000-0000-0000-0000000000c1',
     'default', '0058a0de-0000-0000-0000-0000000000f1', 1);
insert into collections (id, user_id, title, visibility) values
    ('0058a0de-0000-0000-0000-0000000000a1', '0058a0de-0000-0000-0000-000000000001',
     'published before a handle', 'public');
insert into collection_items (collection_id, user_item_id, position) values
    ('0058a0de-0000-0000-0000-0000000000a1', '0058a0de-0000-0000-0000-0000000000f1', 0);
insert into routines (id, user_id, title, slot, cadence, visibility) values
    ('0058a0de-0000-0000-0000-0000000000a4', '0058a0de-0000-0000-0000-000000000001',
     'a public routine', 'am', 'daily', 'public');
insert into looks (id, user_id, caption, state, posted_at, visibility) values
    ('0058a0de-0000-0000-0000-0000000000a2', '0058a0de-0000-0000-0000-000000000001',
     'a published look', 'public', now(), 'public');

-- ── leak arm: a stranger, before the owner has a handle ────────────────────
select test_as('0058a0de-0000-0000-0000-000000000002');

select is((select count(*)::int from user_items where user_id = '0058a0de-0000-0000-0000-000000000001'), 0,
    '1 · no handle: a public shelf is not readable');
select is((select count(*)::int from rank_positions where user_id = '0058a0de-0000-0000-0000-000000000001'), 0,
    '2 · no handle: public rankings are not readable');
select is((select count(*)::int from collections where user_id = '0058a0de-0000-0000-0000-000000000001'), 0,
    '3 · no handle: a public collection is not readable');
select is((select count(*)::int from routines where user_id = '0058a0de-0000-0000-0000-000000000001'), 0,
    '4 · no handle: a public routine is not readable');
select is((select count(*)::int from looks where user_id = '0058a0de-0000-0000-0000-000000000001'), 0,
    '5 · no handle: a published look is not readable');
-- The two-argument wrapper is what every policy calls; the three-argument
-- root is not executable by `authenticated`, on purpose.
select ok(not can_view('0058a0de-0000-0000-0000-000000000001', 'shelf'),
    '6 · can_view says no while the owner has no handle');

-- ── the owner still sees their own rows ────────────────────────────────────
select test_as('0058a0de-0000-0000-0000-000000000001');
select is((select count(*)::int from user_items where user_id = '0058a0de-0000-0000-0000-000000000001'), 1,
    '7 · the owner reads their own shelf regardless');

-- ── the owner claims a handle, the same RPC the app calls ──────────────────
select is(claim_handle('handlegate0058'), 'handlegate0058', '8 · the claim goes through');

-- ── clean arm: the same stranger, after ────────────────────────────────────
select test_as('0058a0de-0000-0000-0000-000000000002');
select is((select count(*)::int from user_items where user_id = '0058a0de-0000-0000-0000-000000000001'), 1,
    '9 · with a handle: the public shelf is readable');
select is((select count(*)::int from rank_positions where user_id = '0058a0de-0000-0000-0000-000000000001'), 1,
    '10 · with a handle: public rankings are readable');
select is((select count(*)::int from collections where user_id = '0058a0de-0000-0000-0000-000000000001'), 1,
    '11 · with a handle: the public collection is readable');
select is((select count(*)::int from looks where user_id = '0058a0de-0000-0000-0000-000000000001'), 1,
    '12 · with a handle: the published look is readable');

select * from finish();
rollback;
