-- Discover suite · rec_dismissals (0041): the exclusion in both slots, the
-- affinity shift, isolation, and idempotence. GLO-181. Fixtures in-txn.
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- u1 owns P0 (liked) whose attribute also marks P1 and P2 — both surface as
-- taste picks. u1 then dismisses P1.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
select ('a6000000-0000-0000-0000-00000000000' || i)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'dis-u' || i || '@test.local', '', now(),
       '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''
from unnest(array['1','2']) as i;

insert into brands (id, name, normalized_name) values
    ('b6000000-0000-0000-0000-000000000001', 'dis brand', 'dis brand');
insert into categories (id, domain, slug, label) values
    ('c6000000-0000-0000-0000-000000000001', 'makeup', 'dis-cat', 'dis cat');
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope)
select ('d6000000-0000-0000-0000-00000000000' || i)::uuid, 'b6000000-0000-0000-0000-000000000001',
       'c6000000-0000-0000-0000-000000000001', 'makeup', 'dis product ' || i, 'dis product ' || i, 'canonical'
from unnest(array['0','1','2']) as i;
insert into variants (id, product_id, kind)
select ('e6000000-0000-0000-0000-00000000000' || i)::uuid,
       ('d6000000-0000-0000-0000-00000000000' || i)::uuid, 'default'
from unnest(array['0','1','2']) as i;
insert into attribute_chips (id, domain, slug, label) values
    ('f6000000-0000-0000-0000-000000000001', null, 'dis-attr', 'dis-attr');
insert into product_attributes (product_id, attribute_chip_id, source)
select ('d6000000-0000-0000-0000-00000000000' || i)::uuid,
       'f6000000-0000-0000-0000-000000000001', 'inci'
from unnest(array['0','1','2']) as i;
insert into user_items (id, user_id, variant_id, status, like_state, client_id) values
    ('56000000-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000001',
     'e6000000-0000-0000-0000-000000000000', 'own', 1, '66000000-0000-0000-0000-000000000001');

select test_as('a6000000-0000-0000-0000-000000000001');

-- before: both P1 and P2 are taste picks; the vector has one signal
select ok(exists (select 1 from discover_for_user() where name = 'dis product 1'),
    'before dismissal, P1 is a pick');
select is((select n_signals from affinity_for_user() where label = 'dis-attr'),
    1, 'one signal behind the attribute before the dismissal');

select lives_ok($$
    insert into rec_dismissals (user_id, product_id, reason)
    values ('a6000000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-000000000001', 'not_for_me')
$$, 'a user can dismiss a recommendation');

-- the exclusion, both slots
select ok(not exists (select 1 from discover_for_user() where name = 'dis product 1'),
    'a dismissed product leaves the picks');
select ok(not exists (select 1 from discover_for_user() where name = 'dis product 1' and basis = 'exploration'),
    'the wander does not re-offer it — no refusing to take no for an answer');
select ok(exists (select 1 from discover_for_user() where name = 'dis product 2'),
    'its attribute-siblings are untouched');

-- the engine learns: −0.75 joins the mean, n counts what you said
select is((select n_signals from affinity_for_user() where label = 'dis-attr'),
    2, 'the dismissal is a signal — n says so');
select is((select raw_score from affinity_for_user() where label = 'dis-attr'),
    0.25::numeric, 'the mean shifts: (+1.25 like − 0.75 dismissal) / 2 — the registry''s reserved weight, live');

-- walls: unique row, and never someone else's
select throws_ok($$
    insert into rec_dismissals (user_id, product_id)
    values ('a6000000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-000000000001')
$$, '23505', null, 'dismissing twice is a conflict, not a duplicate signal');
select test_as('a6000000-0000-0000-0000-000000000002');
select throws_ok($$
    insert into rec_dismissals (user_id, product_id)
    values ('a6000000-0000-0000-0000-000000000001', 'd6000000-0000-0000-0000-000000000002')
$$, '42501', 'new row violates row-level security policy for table "rec_dismissals"',
    'you cannot dismiss on someone else''s behalf');

select * from finish();
rollback;
