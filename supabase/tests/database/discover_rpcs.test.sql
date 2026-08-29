-- Discover suite · discover_for_user() + crosswalk_for_user() (0040): tier
-- order, min-n at the RPC, the exclusions, the labeled wander, and the
-- crosswalk's threshold. GLO-20. Fixtures in-txn, rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- ── fixtures ───────────────────────────────────────────────────────────────
-- caller u1: owns P0 (liked, so P-taste's shared attribute scores), anchors
-- V-anchor. cohort data: P-shade rated in u1's shade cohort (n=6 face-offs),
-- P-every rated in 'all' (n=8), P-thin rated in 'all' below min-n (n=2),
-- P-pop owned by 6 (variant stats). P-owned is on u1's shelf. crosswalk:
-- V-anchor co-worn with V-partner at n=6, and with V-rare at n=1.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values ('a5000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'disc-u1@test.local', '', now(),
        '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');

insert into brands (id, name, normalized_name) values
    ('b5000000-0000-0000-0000-000000000001', 'disc brand', 'disc brand');
insert into categories (id, domain, slug, label, is_anchor) values
    ('c5000000-0000-0000-0000-000000000001', 'makeup', 'disc-cat', 'disc cat', true);
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope)
select ('d5000000-0000-0000-0000-00000000000' || i)::uuid, 'b5000000-0000-0000-0000-000000000001',
       'c5000000-0000-0000-0000-000000000001', 'makeup', 'disc product ' || i, 'disc product ' || i, 'canonical'
from unnest(array['0','1','2','3','4','5','6','7']) as i;
-- P0=owned+liked · P1=taste (shares attr) · P2=shade-rated · P3=all-rated ·
-- P4=below-min-n · P5=popular · P6=crosswalk partner · P7=filler
insert into variants (id, product_id, kind)
select ('e5000000-0000-0000-0000-00000000000' || i)::uuid,
       ('d5000000-0000-0000-0000-00000000000' || i)::uuid, 'default'
from unnest(array['0','1','2','3','4','5','6','7']) as i;

insert into attribute_chips (id, domain, slug, label) values
    ('f5000000-0000-0000-0000-000000000001', null, 'disc-attr', 'disc-attr');
insert into product_attributes (product_id, attribute_chip_id, source) values
    ('d5000000-0000-0000-0000-000000000000', 'f5000000-0000-0000-0000-000000000001', 'inci'),
    ('d5000000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001', 'inci');

-- u1's shelf: owns P0, liked → taste signal for disc-attr → scores P1
insert into user_items (id, user_id, variant_id, status, like_state, client_id) values
    ('55000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001',
     'e5000000-0000-0000-0000-000000000000', 'own', 1, '65000000-0000-0000-0000-000000000001');
insert into item_fits (user_id, user_item_id, fit) values
    ('a5000000-0000-0000-0000-000000000001', '55000000-0000-0000-0000-000000000001', 'just_right');

-- cohort aggregates, written directly as the service would
insert into agg_rank_scores (product_id, category_id, cohort_key, n_face_offs, n_users, mean_percentile) values
    ('d5000000-0000-0000-0000-000000000002', 'c5000000-0000-0000-0000-000000000001',
     'shade:e5000000-0000-0000-0000-000000000000', 6, 4, 0.9),
    ('d5000000-0000-0000-0000-000000000003', 'c5000000-0000-0000-0000-000000000001', 'all', 8, 5, 0.8),
    ('d5000000-0000-0000-0000-000000000004', 'c5000000-0000-0000-0000-000000000001', 'all', 2, 2, 0.99);
insert into agg_variant_stats (variant_id, owners) values
    ('e5000000-0000-0000-0000-000000000005', 6);
insert into shade_cooccurrence (variant_a, variant_b, n) values
    (least('e5000000-0000-0000-0000-000000000000'::uuid, 'e5000000-0000-0000-0000-000000000006'::uuid),
     greatest('e5000000-0000-0000-0000-000000000000'::uuid, 'e5000000-0000-0000-0000-000000000006'::uuid), 6),
    (least('e5000000-0000-0000-0000-000000000000'::uuid, 'e5000000-0000-0000-0000-000000000007'::uuid),
     greatest('e5000000-0000-0000-0000-000000000000'::uuid, 'e5000000-0000-0000-0000-000000000007'::uuid), 1);

select test_as('a5000000-0000-0000-0000-000000000001');

-- ── the tiers, in one call ─────────────────────────────────────────────────
select is((select basis from discover_for_user() where name = 'disc product 1'),
    'taste', 'a product sharing a liked attribute is a taste pick — Stage 1');
select is((select basis from discover_for_user() where name = 'disc product 2'),
    'shade', 'the caller''s shade cohort is Stage 0''s first tier');
select is((select basis from discover_for_user() where name = 'disc product 3'),
    'everyone', 'the all cohort is the next tier');
select is((select basis from discover_for_user() where name = 'disc product 5'),
    'popular', 'plain ownership is the floor tier');
select ok((select array_position(array_agg(name order by ord), 'disc product 1') = 1
           from (select name, row_number() over () as ord from discover_for_user()) t),
    'taste outranks every population tier');

-- ── the rules ──────────────────────────────────────────────────────────────
select ok(not exists (select 1 from discover_for_user() where name = 'disc product 4'),
    'below min_n_faceoffs the RPC returns nothing — min-n is enforced here, not in the client');
select ok(not exists (select 1 from discover_for_user() where name = 'disc product 0'),
    'the caller''s own shelf is never recommended back to them');
select is((select count(*) from discover_for_user() where basis = 'exploration'),
    1::bigint, 'exactly one labeled exploration slot');
select ok((select basis_n = 0 from discover_for_user() where basis = 'exploration'),
    'the wander claims no evidence — basis_n is 0, and the client labels it as a wander');

-- ── the crosswalk ──────────────────────────────────────────────────────────
select is((select name from crosswalk_for_user() limit 1),
    'disc product 6', 'the co-worn partner surfaces, by its n');
select ok(not exists (select 1 from crosswalk_for_user() where name = 'disc product 7'),
    'an n=1 pair stays unrendered — thresholded at min_n_chip_claims');

-- ── the wall ───────────────────────────────────────────────────────────────
select set_config('role', 'anon', true);
select throws_ok('select * from discover_for_user()', '42501', null,
    'anon has no shelf, no anchor, no taste — and no discover');

select * from finish();
rollback;
