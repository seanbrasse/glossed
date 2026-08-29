-- Aggregates suite · refresh_shade_cooccurrence() (0039): the self-join, the
-- axis dedupe, pair ordering, and the walls. GLO-175. Fixtures in-txn.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- u1 and u2 both anchor V1+V2 · u3 anchors V1+V3 · u1's V1 carries TWO fit
-- axes (depth + undertone), the case the dedupe exists for.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
select ('a4000000-0000-0000-0000-00000000000' || i)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'co-u' || i || '@test.local', '', now(),
       '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''
from unnest(array['1','2','3']) as i;

insert into brands (id, name, normalized_name) values
    ('b4000000-0000-0000-0000-000000000001', 'co test brand', 'co test brand');
insert into categories (id, domain, slug, label, is_anchor) values
    ('c4000000-0000-0000-0000-000000000001', 'makeup', 'co-cat', 'co cat', true);
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope) values
    ('d4000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001',
     'c4000000-0000-0000-0000-000000000001', 'makeup', 'co product', 'co product', 'canonical');
insert into variants (id, product_id, kind, shade_code)
select ('e4000000-0000-0000-0000-00000000000' || i)::uuid,
       'd4000000-0000-0000-0000-000000000001', 'shade', '10' || i
from unnest(array['1','2','3']) as i;

insert into user_items (id, user_id, variant_id, status, client_id)
select ('54000000-0000-0000-0000-0000000000' || u || v)::uuid,
       ('a4000000-0000-0000-0000-00000000000' || u)::uuid,
       ('e4000000-0000-0000-0000-00000000000' || v)::uuid,
       'own',
       ('64000000-0000-0000-0000-0000000000' || u || v)::uuid
from (values ('1','1'), ('1','2'), ('2','1'), ('2','2'), ('3','1'), ('3','3')) as t(u, v);

insert into item_fits (user_id, user_item_id, fit) values
    -- u1's V1: two axes — the double-row case
    ('a4000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000011', 'too_light'),
    ('a4000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000011', 'too_pink'),
    ('a4000000-0000-0000-0000-000000000001', '54000000-0000-0000-0000-000000000012', 'just_right'),
    ('a4000000-0000-0000-0000-000000000002', '54000000-0000-0000-0000-000000000021', 'just_right'),
    ('a4000000-0000-0000-0000-000000000002', '54000000-0000-0000-0000-000000000022', 'just_right'),
    ('a4000000-0000-0000-0000-000000000003', '54000000-0000-0000-0000-000000000031', 'just_right'),
    ('a4000000-0000-0000-0000-000000000003', '54000000-0000-0000-0000-000000000033', 'just_right');

select refresh_shade_cooccurrence();

select is((select n from shade_cooccurrence
           where variant_a = 'e4000000-0000-0000-0000-000000000001'
             and variant_b = 'e4000000-0000-0000-0000-000000000002'),
    2, 'V1+V2 co-worn by two users — and u1''s two fit axes did not inflate it');
select is((select n from shade_cooccurrence
           where variant_a = 'e4000000-0000-0000-0000-000000000001'
             and variant_b = 'e4000000-0000-0000-0000-000000000003'),
    1, 'an n=1 pair is stored — the render thresholds, the data does not');
select ok(not exists (select 1 from shade_cooccurrence
          where variant_a = 'e4000000-0000-0000-0000-000000000002'
            and variant_b = 'e4000000-0000-0000-0000-000000000003'),
    'no user wears V2+V3 together, so no row says otherwise');
select is((select count(*) from shade_cooccurrence
           where variant_a > variant_b), 0::bigint,
    'every pair is stored ordered, once');
select lives_ok('select refresh_shade_cooccurrence()', 'refresh is a full rewrite');
select is((select n from shade_cooccurrence
           where variant_a = 'e4000000-0000-0000-0000-000000000001'
             and variant_b = 'e4000000-0000-0000-0000-000000000002'),
    2, 'a second run converges');

select test_as('a4000000-0000-0000-0000-000000000001');
select throws_ok('select refresh_shade_cooccurrence()', '42501', null,
    'authenticated cannot run the writer');

select * from finish();
rollback;
