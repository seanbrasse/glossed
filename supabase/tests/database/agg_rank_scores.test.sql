-- Aggregates suite · refresh_rank_scores() (0038): percentiles, both cohort
-- guards, both sides of a face-off, the single-item rule, and the walls.
-- GLO-174. Fixtures created in this transaction and rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- ── fixtures ───────────────────────────────────────────────────────────────
-- u1: 3-item makeup ranking + anchor on V1 · u2: 2-item ranking + same anchor
--     + hair 3b + a 2-item haircare ranking · u3: single-item list only
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
select ('a3000000-0000-0000-0000-00000000000' || i)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'rank-u' || i || '@test.local', '', now(),
       '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''
from unnest(array['1','2','3']) as i;
insert into profiles (user_id, birth_year_month, domains, hair_pattern) values
    ('a3000000-0000-0000-0000-000000000002', '1997-06', '{makeup,haircare}', '3b');
-- u1 and u3 have NO profile row — GLO-173's rule, asserted below.

insert into brands (id, name, normalized_name) values
    ('b3000000-0000-0000-0000-000000000001', 'rank test brand', 'rank test brand');
insert into categories (id, domain, slug, label, is_anchor) values
    ('c3000000-0000-0000-0000-000000000001', 'makeup',   'rank-cat-anchor', 'rank anchor cat', true),
    ('c3000000-0000-0000-0000-000000000002', 'haircare', 'rank-cat-hair',   'rank hair cat',   false);
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope)
select ('d3000000-0000-0000-0000-00000000000' || i)::uuid, 'b3000000-0000-0000-0000-000000000001',
       case when i in ('4','5') then 'c3000000-0000-0000-0000-000000000002'::uuid
            else 'c3000000-0000-0000-0000-000000000001'::uuid end,
       case when i in ('4','5') then 'haircare'::domain_enum else 'makeup'::domain_enum end,
       'rank product ' || i, 'rank product ' || i, 'canonical'
from unnest(array['1','2','3','4','5']) as i;
insert into variants (id, product_id, kind)
select ('e3000000-0000-0000-0000-00000000000' || i)::uuid,
       ('d3000000-0000-0000-0000-00000000000' || i)::uuid, 'default'
from unnest(array['1','2','3','4','5']) as i;

-- items: u1 owns P1..P3 · u2 owns P1,P2 and P4,P5 · u3 owns P3 only
insert into user_items (id, user_id, variant_id, status, client_id) values
    ('53000000-0000-0000-0000-000000000011', 'a3000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000001', 'own', '63000000-0000-0000-0000-000000000011'),
    ('53000000-0000-0000-0000-000000000012', 'a3000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000002', 'own', '63000000-0000-0000-0000-000000000012'),
    ('53000000-0000-0000-0000-000000000013', 'a3000000-0000-0000-0000-000000000001', 'e3000000-0000-0000-0000-000000000003', 'own', '63000000-0000-0000-0000-000000000013'),
    ('53000000-0000-0000-0000-000000000021', 'a3000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000001', 'own', '63000000-0000-0000-0000-000000000021'),
    ('53000000-0000-0000-0000-000000000022', 'a3000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000002', 'own', '63000000-0000-0000-0000-000000000022'),
    ('53000000-0000-0000-0000-000000000024', 'a3000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000004', 'own', '63000000-0000-0000-0000-000000000024'),
    ('53000000-0000-0000-0000-000000000025', 'a3000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000005', 'own', '63000000-0000-0000-0000-000000000025'),
    ('53000000-0000-0000-0000-000000000031', 'a3000000-0000-0000-0000-000000000003', 'e3000000-0000-0000-0000-000000000003', 'own', '63000000-0000-0000-0000-000000000031');

-- rankings. u1 in the makeup cat: P1 > P2 > P3 (pcts 1, .5, 0).
-- u2 in the makeup cat: P2 > P1 (pcts 1, 0). u2 in haircare: P4 > P5.
-- u3: a single-item "list" — contributes nothing.
insert into rank_positions (user_id, category_id, scope_key, user_item_id, position) values
    ('a3000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'default', '53000000-0000-0000-0000-000000000011', 1),
    ('a3000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'default', '53000000-0000-0000-0000-000000000012', 2),
    ('a3000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'default', '53000000-0000-0000-0000-000000000013', 3),
    ('a3000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000001', 'default', '53000000-0000-0000-0000-000000000022', 1),
    ('a3000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000001', 'default', '53000000-0000-0000-0000-000000000021', 2),
    ('a3000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000002', 'default', '53000000-0000-0000-0000-000000000024', 1),
    ('a3000000-0000-0000-0000-000000000002', 'c3000000-0000-0000-0000-000000000002', 'default', '53000000-0000-0000-0000-000000000025', 2),
    ('a3000000-0000-0000-0000-000000000003', 'c3000000-0000-0000-0000-000000000001', 'default', '53000000-0000-0000-0000-000000000031', 1);

-- both users anchor on V1 (P1) with a fit → shade:V1 cohort = {u1, u2}
insert into item_fits (user_id, user_item_id, fit) values
    ('a3000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000011', 'just_right'),
    ('a3000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000021', 'just_right');

-- one real face-off (u1: P1 beats P2) and one skipped (must not count)
insert into face_offs (user_id, category_id, scope_key, winner_item_id, loser_item_id, skipped, client_id) values
    ('a3000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'default',
     '53000000-0000-0000-0000-000000000011', '53000000-0000-0000-0000-000000000012', false, '73000000-0000-0000-0000-000000000001'),
    ('a3000000-0000-0000-0000-000000000001', 'c3000000-0000-0000-0000-000000000001', 'default',
     '53000000-0000-0000-0000-000000000011', '53000000-0000-0000-0000-000000000013', true,  '73000000-0000-0000-0000-000000000002');

select refresh_rank_scores();

-- ── percentiles and cohorts ────────────────────────────────────────────────
select is((select mean_percentile from agg_rank_scores
           where product_id = 'd3000000-0000-0000-0000-000000000001' and cohort_key = 'all'),
    0.5::numeric, 'P1 all-cohort mean: u1 gives 1.0, u2 gives 0 — the spec formula');
select is((select n_users from agg_rank_scores
           where product_id = 'd3000000-0000-0000-0000-000000000001' and cohort_key = 'all'),
    2, 'both rankers count');
select ok(not exists (select 1 from agg_rank_scores
          where product_id = 'd3000000-0000-0000-0000-000000000003' and cohort_key = 'all' and n_users > 1),
    'u3''s single-item list contributes nothing — P3''s n_users is u1 alone');
select is((select n_users from agg_rank_scores
           where product_id = 'd3000000-0000-0000-0000-000000000001'
             and cohort_key = 'shade:e3000000-0000-0000-0000-000000000001'),
    2, 'the shade cohort exists: both users anchor on V1 with a fit');
select is((select mean_percentile from agg_rank_scores
           where product_id = 'd3000000-0000-0000-0000-000000000004' and cohort_key = 'hair:3b'),
    1.0::numeric, 'hair cohort scores the haircare category');
select ok(not exists (select 1 from agg_rank_scores
          where product_id = 'd3000000-0000-0000-0000-000000000001' and cohort_key = 'hair:3b'),
    'hair cohorts do not leak into makeup categories — the spec guard');
select ok(not exists (select 1 from agg_rank_scores
          where product_id = 'd3000000-0000-0000-0000-000000000004' and cohort_key like 'shade:%'),
    'shade cohorts do not leak into haircare');

-- ── face-offs ──────────────────────────────────────────────────────────────
select is((select n_face_offs from agg_rank_scores
           where product_id = 'd3000000-0000-0000-0000-000000000002' and cohort_key = 'all'),
    1, 'the loser side of a face-off counts too');
select is((select n_face_offs from agg_rank_scores
           where product_id = 'd3000000-0000-0000-0000-000000000003' and cohort_key = 'all'),
    0, 'a skipped face-off is not evidence');

-- ── idempotency and the walls ──────────────────────────────────────────────
select lives_ok('select refresh_rank_scores()', 'refresh is a full rewrite');
select is((select n_users from agg_rank_scores
           where product_id = 'd3000000-0000-0000-0000-000000000001' and cohort_key = 'all'),
    2, 'a second run converges');
select test_as('a3000000-0000-0000-0000-000000000001');
select throws_ok('select refresh_rank_scores()', '42501', null,
    'authenticated cannot run the writer');

select * from finish();
rollback;
