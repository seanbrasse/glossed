-- Discover suite · leaderboard() (0042): the claim gate, the not-yet rows,
-- both orderings, the your-scope resolution, and the lowest board's reasons.
-- GLO-20. Fixtures in-txn, rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

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
values ('a7000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'lead-u1@test.local', '', now(),
        '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');

insert into brands (id, name, normalized_name) values
    ('b7000000-0000-0000-0000-000000000001', 'lead brand', 'lead brand');
insert into categories (id, domain, slug, label, is_anchor) values
    ('c7000000-0000-0000-0000-000000000001', 'makeup', 'lead-cat', 'lead cat', true);
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope)
select ('d7000000-0000-0000-0000-00000000000' || i)::uuid, 'b7000000-0000-0000-0000-000000000001',
       'c7000000-0000-0000-0000-000000000001', 'makeup', 'lead product ' || i, 'lead product ' || i, 'canonical'
from unnest(array['1','2','3']) as i;
insert into variants (id, product_id, kind)
select ('e7000000-0000-0000-0000-00000000000' || i)::uuid,
       ('d7000000-0000-0000-0000-00000000000' || i)::uuid, 'default'
from unnest(array['1','2','3']) as i;

-- P1 well-attested and loved (0.9, 8 face-offs) · P2 well-attested and
-- disliked (0.2, 6) · P3 below min-n (0.99, 2 — the trap row: a great mean
-- nobody may see yet)
insert into agg_rank_scores (product_id, category_id, cohort_key, n_face_offs, n_users, mean_percentile) values
    ('d7000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001', 'all', 8, 5, 0.9),
    ('d7000000-0000-0000-0000-000000000002', 'c7000000-0000-0000-0000-000000000001', 'all', 6, 4, 0.2),
    ('d7000000-0000-0000-0000-000000000003', 'c7000000-0000-0000-0000-000000000001', 'all', 2, 2, 0.99),
    -- u1's shade cohort sees P2 differently
    ('d7000000-0000-0000-0000-000000000002', 'c7000000-0000-0000-0000-000000000001',
     'shade:e7000000-0000-0000-0000-000000000001', 7, 5, 0.95);

-- the "why" behind P2's low rank: a dislike chip above threshold, plus one
-- below it that must NOT surface
insert into agg_variant_stats (variant_id, owners, chip_counts) values
    ('e7000000-0000-0000-0000-000000000002', 9,
     '{"foundation-flashback": 6, "oxidized-on-me": 2}');

-- u1 anchors on V1, which resolves their 'yours' scope
insert into user_items (id, user_id, variant_id, status, client_id) values
    ('57000000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-000000000001',
     'e7000000-0000-0000-0000-000000000001', 'own', '67000000-0000-0000-0000-000000000001');
insert into item_fits (user_id, user_item_id, fit) values
    ('a7000000-0000-0000-0000-000000000001', '57000000-0000-0000-0000-000000000001', 'just_right');

select test_as('a7000000-0000-0000-0000-000000000001');

-- ── the claim gate and the ordering ────────────────────────────────────────
select results_eq(
    $$ select name, mean_percentile is not null from leaderboard('c7000000-0000-0000-0000-000000000001') $$,
    $$ values ('lead product 1', true), ('lead product 2', true), ('lead product 3', false) $$,
    'claimed rows lead in mean order; the below-min row trails with its claim nulled — a 0.99 nobody may see yet');
select is((select n_face_offs from leaderboard('c7000000-0000-0000-0000-000000000001') where name = 'lead product 3'),
    2, 'the not-yet row still ships its n — "not enough face-offs yet · 2 of 5"');
select is((select needed from leaderboard('c7000000-0000-0000-0000-000000000001') limit 1),
    5, 'the denominator travels with the row, not the client');

-- ── the lowest board ───────────────────────────────────────────────────────
select is((select name from leaderboard('c7000000-0000-0000-0000-000000000001', 'all', true) limit 1),
    'lead product 2', 'ascending flips the board: the worst claimed row leads');
select is((select dislike_reasons from leaderboard('c7000000-0000-0000-0000-000000000001', 'all', true)
           where name = 'lead product 2'),
    array['flashback in photos'], 'the why: dislike chips at or above min-n, and only those');
select ok((select dislike_reasons is null from leaderboard('c7000000-0000-0000-0000-000000000001', 'all', false)
           where name = 'lead product 2'),
    'the best board carries no dislike reasons — they belong to the question being asked');

-- ── the your-shade scope ───────────────────────────────────────────────────
select is((select mean_percentile from leaderboard('c7000000-0000-0000-0000-000000000001', 'yours')
           where name = 'lead product 2'),
    0.95::numeric, 'yours resolves the caller''s anchor cohort server-side');
select is((select count(*) from leaderboard('c7000000-0000-0000-0000-000000000001', 'yours')),
    1::bigint, 'the shade cohort shows only what it has rows for');

-- ── anon ───────────────────────────────────────────────────────────────────
select set_config('role', 'anon', true);
-- and clear the previous impersonation's claims — a real anon has no sub,
-- and auth.uid() reads the GUC, not the role
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select lives_ok($$ select * from leaderboard('c7000000-0000-0000-0000-000000000001') $$,
    'anon reads the population board — the payoff precedent');
select is((select count(*) from leaderboard('c7000000-0000-0000-0000-000000000001')),
    3::bigint, 'and sees every row');
select is((select count(*) from leaderboard('c7000000-0000-0000-0000-000000000001', 'yours')),
    3::bigint, 'yours with nobody to resolve falls back to all rather than erroring');

select * from finish();
rollback;
