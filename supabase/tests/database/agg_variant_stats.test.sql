-- Aggregates suite · refresh_variant_stats() (0036): the cohort lattice, the
-- null-dimension rule, both exclusions, the payoff fix, and the walls.
-- GLO-157. Fixtures created in this transaction and rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- ── fixtures: three cohort shapes, one variant ─────────────────────────────
-- u1: tone 6 · combo · no hair pattern     u2: tone 6 · oily · 3b
-- u3: no tone · combo · no hair pattern
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
select ('a2000000-0000-0000-0000-00000000000' || i)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'agg-u' || i || '@test.local', '', now(),
       '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''
from unnest(array['1','2','3','4']) as i;

insert into profiles (user_id, birth_year_month, domains, tone_band, skin_type, hair_pattern) values
    ('a2000000-0000-0000-0000-000000000001', '1998-04', '{makeup}', 6,    'combo', null),
    ('a2000000-0000-0000-0000-000000000002', '1996-11', '{makeup}', 6,    'oily',  '3b'),
    ('a2000000-0000-0000-0000-000000000003', '2001-02', '{makeup}', null, 'combo', null);

insert into brands (id, name, normalized_name) values
    ('b2000000-0000-0000-0000-000000000001', 'agg test brand', 'agg test brand');
insert into categories (id, domain, slug, label) values
    ('c2000000-0000-0000-0000-000000000001', 'makeup', 'agg-cat', 'agg cat');
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope) values
    ('d2000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001',
     'c2000000-0000-0000-0000-000000000001', 'makeup', 'agg product', 'agg product', 'canonical');
insert into variants (id, product_id, kind) values
    ('e2000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'default'),
    ('e2000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001', 'default');

-- u4 has an item and NO profile row — the GLO-173 case: a profile is not a
-- precondition for counting; they belong to roll-up cells only.
-- all four own V1; u1 also wants-to-try V2, which must contribute nothing
insert into user_items (id, user_id, variant_id, status, client_id) values
    ('52000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'own', '62000000-0000-0000-0000-000000000001'),
    ('52000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000001', 'own', '62000000-0000-0000-0000-000000000002'),
    ('52000000-0000-0000-0000-000000000003', 'a2000000-0000-0000-0000-000000000003', 'e2000000-0000-0000-0000-000000000001', 'own', '62000000-0000-0000-0000-000000000003'),
    ('52000000-0000-0000-0000-000000000004', 'a2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000002', 'want_to_try', '62000000-0000-0000-0000-000000000004'),
    ('52000000-0000-0000-0000-000000000005', 'a2000000-0000-0000-0000-000000000004', 'e2000000-0000-0000-0000-000000000001', 'own', '62000000-0000-0000-0000-000000000005');

-- u1 fit just_right (lands only in u1's cells); u2 fit too_light (u2 has a
-- hair pattern, so this fit is what makes the payoff double-count observable)
insert into item_fits (user_id, user_item_id, fit) values
    ('a2000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001', 'just_right'),
    ('a2000000-0000-0000-0000-000000000002', '52000000-0000-0000-0000-000000000002', 'too_light');

insert into item_chips (user_id, user_item_id, experience_chip_id) values
    ('a2000000-0000-0000-0000-000000000001', '52000000-0000-0000-0000-000000000001',
     (select id from experience_chips where slug = 'lasted-all-day'));

select refresh_variant_stats();

-- ── the lattice ────────────────────────────────────────────────────────────
select is((select owners from agg_variant_stats
           where variant_id = 'e2000000-0000-0000-0000-000000000001' and cohort_key = '-:-:-'),
    4, 'the all-cohort row counts every owner — including u4, who has no profile row (GLO-173)');
select ok(not exists (select 1 from agg_variant_stats
          where variant_id = 'e2000000-0000-0000-0000-000000000001' and cohort_key <> '-:-:-'
            and owners = 4),
    'the profileless user reaches roll-up cells only, never a named cohort');
select is((select owners from agg_variant_stats
           where variant_id = 'e2000000-0000-0000-0000-000000000001' and cohort_key = '6:-:-'),
    2, 'tone-6 cohort: u1 and u2');
select is((select owners from agg_variant_stats
           where variant_id = 'e2000000-0000-0000-0000-000000000001' and cohort_key = '6:combo:-'),
    1, 'an n=1 cell is STORED — min-n gates the render, never the data');
select is((select owners from agg_variant_stats
           where variant_id = 'e2000000-0000-0000-0000-000000000001' and cohort_key = '-:-:3b'),
    1, 'hair_pattern is a cohort axis now — the GLO-157 requirement');
select is((select count(*) from agg_variant_stats
           where variant_id = 'e2000000-0000-0000-0000-000000000001'),
    10::bigint, 'no phantom cells: a user''s missing dimension rolls up, it does not become a cohort');

-- ── the payload columns ────────────────────────────────────────────────────
select is((select fit_counts ->> 'just_right' from agg_variant_stats
           where variant_id = 'e2000000-0000-0000-0000-000000000001' and cohort_key = '-:-:-'),
    '1', 'fit_counts keys on the fit value');
select is((select chip_counts ->> 'lasted-all-day' from agg_variant_stats
           where variant_id = 'e2000000-0000-0000-0000-000000000001' and cohort_key = '-:-:-'),
    '1', 'chip_counts keys on the chip slug — the moat''s read side has data');

-- ── the exclusions and idempotency ─────────────────────────────────────────
select ok(not exists (select 1 from agg_variant_stats
          where variant_id = 'e2000000-0000-0000-0000-000000000002'),
    'want_to_try contributes nothing — unworn is not evidence');
select lives_ok('select refresh_variant_stats()', 'refresh is a full rewrite');
select is((select count(*) from agg_variant_stats
           where variant_id = 'e2000000-0000-0000-0000-000000000001'),
    10::bigint, 'a second run converges to the same lattice');

-- ── the payoff fix, observably necessary ───────────────────────────────────
-- u2's fit also lives in hair cells; without the hair_pattern-is-null
-- predicate the SUM reads 3, not 2.
select is((select n_exact_shade from payoff_for_variant('e2000000-0000-0000-0000-000000000001')),
    4, 'payoff n comes from the all-cohort row alone');
select is((select n_with_fit from payoff_for_variant('e2000000-0000-0000-0000-000000000001')),
    2, 'fits are not double-counted through hair cohorts');

-- ── the walls ──────────────────────────────────────────────────────────────
select test_as('a2000000-0000-0000-0000-000000000001');
select throws_ok('select refresh_variant_stats()', '42501', null,
    'authenticated cannot run the writer');
select set_config('role', 'anon', true);
select throws_ok('select count(*) from agg_variant_stats', '42501', null,
    'anon has no grant on the aggregate table at all (0060) — definer RPCs, for accounts, are the door');

select * from finish();
rollback;
