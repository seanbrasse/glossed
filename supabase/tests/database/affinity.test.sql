-- Taste engine suite · affinity_for_user() (0035): weight ordering, the
-- exclusions, shrinkage, isolation, and the anon wall. GLO-169, tech/07 §2.
-- All fixtures created inside this transaction and rolled back — nothing
-- here depends on, or disturbs, seeded state.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- ── fixtures: a private catalog corner + one user with every signal type ──
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values
    ('a1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'affinity-u1@test.local', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''),
    ('a1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'affinity-u2@test.local', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');

insert into brands (id, name, normalized_name) values
    ('b1000000-0000-0000-0000-000000000001', 'affinity test brand', 'affinity test brand');
insert into categories (id, domain, slug, label) values
    ('c1000000-0000-0000-0000-000000000001', 'makeup',   'aff-cat-plain',  'aff plain'),
    ('c1000000-0000-0000-0000-000000000002', 'makeup',   'aff-cat-ranked', 'aff ranked'),
    ('c1000000-0000-0000-0000-000000000003', 'makeup',   'aff-cat-solo',   'aff solo'),
    ('c1000000-0000-0000-0000-000000000004', 'skincare', 'aff-cat-skin',   'aff skin');

-- eight products (P8 is skincare, for the domain filter), one variant each
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope)
select ('d1000000-0000-0000-0000-00000000000' || i)::uuid,
       'b1000000-0000-0000-0000-000000000001',
       case when i = '8' then 'c1000000-0000-0000-0000-000000000004'::uuid
            when i in ('5','6') then 'c1000000-0000-0000-0000-000000000002'::uuid
            when i = '7' then 'c1000000-0000-0000-0000-000000000003'::uuid
            else 'c1000000-0000-0000-0000-000000000001'::uuid end,
       case when i = '8' then 'skincare'::domain_enum else 'makeup'::domain_enum end,
       'aff product ' || i, 'aff product ' || i, 'canonical'
from unnest(array['1','2','3','4','5','6','7','8']) as i;
insert into variants (id, product_id, kind)
select ('e1000000-0000-0000-0000-00000000000' || i)::uuid,
       ('d1000000-0000-0000-0000-00000000000' || i)::uuid, 'default'
from unnest(array['1','2','3','4','5','6','7','8']) as i;

-- one attribute per product, so every product's weight is legible in the output
insert into attribute_chips (id, domain, slug, label)
select ('f1000000-0000-0000-0000-00000000000' || i)::uuid, null,
       'aff-attr-' || i, 'aff-attr-' || i
from unnest(array['1','2','3','4','5','6','7','8']) as i;
insert into product_attributes (product_id, attribute_chip_id, source)
select ('d1000000-0000-0000-0000-00000000000' || i)::uuid,
       ('f1000000-0000-0000-0000-00000000000' || i)::uuid, 'inci'
from unnest(array['1','2','3','4','5','6','7','8']) as i;

-- u1's shelf: every signal the weight table names, one item each
insert into user_items (id, user_id, variant_id, status, like_state, client_id)
select ('51000000-0000-0000-0000-00000000000' || i)::uuid,
       'a1000000-0000-0000-0000-000000000001',
       ('e1000000-0000-0000-0000-00000000000' || i)::uuid,
       case when i = '4' then 'want_to_try'::item_status else 'own'::item_status end,
       case when i = '1' then 1 when i = '2' then -1 else 0 end,
       ('61000000-0000-0000-0000-00000000000' || i)::uuid
from unnest(array['1','2','3','4','5','6','7','8']) as i;

-- i1 liked WITH a like-chip; i2 disliked WITH a dislike-chip
insert into item_chips (user_id, user_item_id, experience_chip_id)
values ('a1000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001',
        (select id from experience_chips where valence = 'like' order by slug limit 1)),
       ('a1000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002',
        (select id from experience_chips where valence = 'dislike' order by slug limit 1));

-- i5 over i6 in the ranked category; i7 alone in the solo category
insert into rank_positions (user_id, category_id, scope_key, user_item_id, position) values
    ('a1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002', 'default', '51000000-0000-0000-0000-000000000005', 1),
    ('a1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000002', 'default', '51000000-0000-0000-0000-000000000006', 2),
    ('a1000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000003', 'default', '51000000-0000-0000-0000-000000000007', 1);

-- ── the vector, as u1 ──────────────────────────────────────────────────────
select test_as('a1000000-0000-0000-0000-000000000001');

select is((select raw_score from affinity_for_user() where label = 'aff-attr-1'), 1.75::numeric,
    'like + like-chip: 0.25 ownership + 1.5');
select is((select raw_score from affinity_for_user() where label = 'aff-attr-2'), -1.75::numeric,
    'dislike + dislike-chip: 0.25 − 2.0 — outweighs any like');
select is((select raw_score from affinity_for_user() where label = 'aff-attr-3'), 0.25::numeric,
    'bare ownership is faint on purpose');
select ok(not exists(select 1 from affinity_for_user() where label = 'aff-attr-4'),
    'want_to_try contributes nothing — unworn is not evidence');
select is((select raw_score from affinity_for_user() where label = 'aff-attr-5'), 3.25::numeric,
    'top of a 2-item list: 0.25 + 3.0 — rank weighs highest');
select is((select raw_score from affinity_for_user() where label = 'aff-attr-6'), -2.75::numeric,
    'bottom of the list is negative evidence: 0.25 − 3.0');
select is((select raw_score from affinity_for_user() where label = 'aff-attr-7'), 0.25::numeric,
    'a single-item ranking list contributes nothing');
select is((select round(w, 3) from affinity_for_user() where label = 'aff-attr-1'), 0.091::numeric,
    'n=1 shrinks hard: w = 1/11 — a cold profile makes almost no claims');
select ok(exists(select 1 from affinity_for_user() where label = 'aff-attr-8'),
    'unfiltered, the skincare item is in the vector');
select ok(not exists(select 1 from affinity_for_user('makeup') where label = 'aff-attr-8'),
    'p_domain narrows the vector to that domain');

-- ── isolation: u2 sees an empty vector, not u1''s ──────────────────────────
select test_as('a1000000-0000-0000-0000-000000000002');
select is((select count(*) from affinity_for_user()), 0::bigint,
    'invoker + RLS: another user''s vector is empty, not borrowed');

-- ── anon has no shelf, so anon has no taste ───────────────────────────────
select set_config('role', 'anon', true);
select throws_ok('select * from affinity_for_user()', '42501', null,
    'anon cannot execute affinity_for_user');

select * from finish();
rollback;
