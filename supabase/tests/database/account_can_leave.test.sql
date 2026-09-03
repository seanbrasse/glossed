-- An account can leave (0059, GLO-258). The session-22 audit's accounts were
-- deleted afterwards and the one that had created a personal-scope product
-- would not go: `products.created_by` has no delete rule, and neither did
-- `rec_dismissals.user_id`. A leaver's personal catalog goes with them; a
-- product of theirs that reached canonical stays, unsigned. Fixtures in-txn,
-- rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

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
    ('0059a0de-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'leaver@test.local', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');
insert into profiles (user_id, birth_year_month, domains) values
    ('0059a0de-0000-0000-0000-000000000001', '1990-01', '{skincare}');
insert into brands (id, name, normalized_name) values
    ('0059a0de-0000-0000-0000-0000000000b1', 'leaver brand', 'leaver brand');
insert into categories (id, domain, slug, label) values
    ('0059a0de-0000-0000-0000-0000000000c1', 'skincare', 'leaver-cat', 'leaver cat');
-- A canonical product the person merely dismissed, and one they once
-- submitted that has since reached canonical — the commons keeps that one.
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope, created_by) values
    ('0059a0de-0000-0000-0000-0000000000d1', '0059a0de-0000-0000-0000-0000000000b1',
     '0059a0de-0000-0000-0000-0000000000c1', 'skincare', 'a canonical product', 'a canonical product', 'canonical', null),
    ('0059a0de-0000-0000-0000-0000000000d2', '0059a0de-0000-0000-0000-0000000000b1',
     '0059a0de-0000-0000-0000-0000000000c1', 'skincare', 'their gift to the commons', 'their gift to the commons', 'canonical',
     '0059a0de-0000-0000-0000-000000000001');

-- The personal product goes in through the app's own RPC, and they log it.
select test_as('0059a0de-0000-0000-0000-000000000001');
select lives_ok(
    $$select create_personal_product('0059a0de-0000-0000-0000-0000000000b1', '0059a0de-0000-0000-0000-0000000000c1',
                                     'skincare', 'my decanted thing', null, null)$$,
    '1 · the person creates a personal product');
insert into user_items (user_id, variant_id, status, client_id)
select '0059a0de-0000-0000-0000-000000000001', v.id, 'own', '0059a0de-0000-0000-0000-0000000000f1'
  from variants v join products p on p.id = v.product_id where p.name = 'my decanted thing';
insert into rec_dismissals (user_id, product_id) values
    ('0059a0de-0000-0000-0000-000000000001', '0059a0de-0000-0000-0000-0000000000d1');

select set_config('role', 'postgres', true);
select is((select count(*)::int from products where created_by = '0059a0de-0000-0000-0000-000000000001'), 2,
    '2 · the personal product and the canonical one both carry their creator');

select lives_ok(
    $$delete from auth.users where id = '0059a0de-0000-0000-0000-000000000001'$$,
    '3 · deleting the account succeeds');
select is((select count(*)::int from auth.users where id = '0059a0de-0000-0000-0000-000000000001'), 0,
    '4 · the account is gone');
select is((select count(*)::int from products where name = 'my decanted thing'), 0,
    '5 · the personal product left with the person — theirs alone, never visible to anyone else');
select is((select count(*)::int from variants v join products p on p.id = v.product_id where p.name = 'my decanted thing'), 0,
    '6 · and its variants');
select is((select created_by from products where id = '0059a0de-0000-0000-0000-0000000000d2'), null,
    '7 · the product that reached canonical stays, unsigned');
select is((select count(*)::int from rec_dismissals where product_id = '0059a0de-0000-0000-0000-0000000000d1'), 0,
    '8 · the dismissals went with the person');

select * from finish();
rollback;
