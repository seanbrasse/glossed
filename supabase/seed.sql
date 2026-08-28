-- Deterministic seed (handbook §5.1): two users, four domains, every catalog
-- lifecycle state, including the ugly ones. Local/staging only — never prod.

-- Two local auth users (password: "password" — local only).
--
-- The token and timestamp columns are set to empty/now, not left NULL:
-- GoTrue scans them into non-nullable Go types, and a NULL there fails
-- every password grant with "Database error querying schema" — which reads
-- like a broken stack, not a broken seed. Found the day the first live
-- sign-in was attempted (GLO-23 debug entry). The identities rows are what
-- make an email user signable-in at all.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values
    ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'maya@local.test', extensions.crypt('password', extensions.gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', ''),
    ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'juli@local.test', extensions.crypt('password', extensions.gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', '');

insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id,
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       'email', u.id::text, now(), now(), now()
from auth.users u;

-- Category tree slice: one per domain + wear-in variety (tech/01 §1.1)
insert into categories (id, domain, slug, label, wear_in_days, is_anchor, rank_unlock_min) values
    ('10000000-0000-0000-0000-000000000001', 'makeup',   'blush',      'blush',            0,  false, 3),
    ('10000000-0000-0000-0000-000000000002', 'makeup',   'foundation', 'foundation',       0,  true,  3),
    ('10000000-0000-0000-0000-000000000003', 'skincare', 'cleanser',   'cleanser',         0,  false, 3),
    ('10000000-0000-0000-0000-000000000004', 'skincare', 'serum',      'serums + actives', 56, false, 3),
    ('10000000-0000-0000-0000-000000000005', 'skincare', 'moisturizer','moisturizer',      14, false, 3),
    ('10000000-0000-0000-0000-000000000006', 'haircare', 'styler',     'stylers',          0,  false, 3),
    ('10000000-0000-0000-0000-000000000007', 'fragrance','fragrance',  'fragrance',        0,  false, 3),
    -- GLO-81: the Shopify fill needs a home for lip products (rhode's whole
    -- flagship line) — the one addition to the tech/01 §1.1 slice, flagged
    -- for the tree workshop. Not an anchor: lip shades are preference, not
    -- skin-match evidence.
    ('10000000-0000-0000-0000-000000000008', 'makeup',   'lip',        'lip',              0,  false, 3);

insert into brands (id, name, normalized_name) values
    ('20000000-0000-0000-0000-000000000001', 'fenty beauty', 'fenty beauty'),
    ('20000000-0000-0000-0000-000000000002', 'rare beauty',  'rare beauty'),
    ('20000000-0000-0000-0000-000000000003', 'rhode',        'rhode'),
    ('20000000-0000-0000-0000-000000000004', 'the ordinary', 'the ordinary'),
    ('20000000-0000-0000-0000-000000000005', 'curlsmith',    'curlsmith'),
    ('20000000-0000-0000-0000-000000000006', 'glossier',     'glossier');

-- Canonical products across all four domains
insert into products (id, brand_id, category_id, domain, name, normalized_name, benefit_line, scope) values
    ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002',
     'makeup', 'pro filt''r soft matte', 'pro filtr soft matte', 'the anchor foundation', 'canonical'),
    ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001',
     'makeup', 'soft pinch liquid blush', 'soft pinch liquid blush', 'one dot, blends forever', 'canonical'),
    ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003',
     'skincare', 'pineapple refresh', 'pineapple refresh', 'gel-to-foam, no tightness', 'canonical'),
    ('30000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000004',
     'skincare', 'niacinamide 10% + zinc', 'niacinamide 10 zinc', 'purged then cleared', 'canonical'),
    ('30000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000006',
     'haircare', 'weightless curl cream', 'weightless curl cream', 'no crunch, 3b-3c', 'canonical'),
    ('30000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000007',
     'fragrance', 'you', 'you', 'skin-scent musk', 'canonical');

-- The ugly states: a delisted product, a fork pair, and per-user personal products
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope, delisted_at) values
    ('30000000-0000-0000-0000-000000000007', '20000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000001',
     'makeup', 'cloud paint (discontinued)', 'cloud paint discontinued', 'canonical', now());
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope, forked_from, inci_raw) values
    ('30000000-0000-0000-0000-000000000008', '20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003',
     'skincare', 'pineapple refresh (2027 formula)', 'pineapple refresh 2027', 'canonical',
     '30000000-0000-0000-0000-000000000003', 'aqua, new-surfactant');
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope, created_by) values
    ('30000000-0000-0000-0000-000000000009', '20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000006',
     'haircare', 'flaxseed curl gel', 'flaxseed curl gel', 'personal', '00000000-0000-0000-0000-000000000001'),
    ('30000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003',
     'skincare', 'juli''s decanted cleanser', 'julis decanted cleanser', 'personal', '00000000-0000-0000-0000-000000000002');

-- Variants: shades with real n-worthy spread, sizes, a GTIN, real dimensions.
-- The GTINs carry valid GS1 mod-10 check digits, because the barcode rung
-- rejects codes that fail one as misreads — a seed that cannot be scanned
-- would fail the scan journey for a reason that has nothing to do with the code.
insert into variants (id, product_id, kind, shade_code, shade_hex, size_ml, gtin, height_mm, price_cents) values
    ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'shade', '220', '#E0B891', 32, '0810086012343', 110, 4000),
    ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001', 'shade', '240', '#D9A87E', 32, '0810086012350', 110, 4000),
    ('40000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000001', 'shade', '330', '#8C5E3C', 32, '0810086012367', 110, 4000),
    ('40000000-0000-0000-0000-000000000004', '30000000-0000-0000-0000-000000000002', 'shade', 'joy', '#D4788C', 7.5, null, 70, 2300);
insert into variants (id, product_id, kind, size_ml, height_mm, price_cents) values
    ('40000000-0000-0000-0000-000000000005', '30000000-0000-0000-0000-000000000003', 'formulation', 150, 160, 3000),
    ('40000000-0000-0000-0000-000000000006', '30000000-0000-0000-0000-000000000005', 'formulation', 237, 180, 2600),
    ('40000000-0000-0000-0000-000000000007', '30000000-0000-0000-0000-000000000006', 'concentration', 50, 95, 6800),
    ('40000000-0000-0000-0000-000000000008', '30000000-0000-0000-0000-000000000009', 'default', 250, 190, null);
insert into variants (id, product_id, kind, strength_pct, size_ml, height_mm) values
    ('40000000-0000-0000-0000-000000000009', '30000000-0000-0000-0000-000000000004', 'formulation', 10, 30, 90);

-- Attribute + experience chip vocabulary slices
insert into attribute_chips (slug, label, domain) values
    ('fragrance-free', 'fragrance-free', null),
    ('silicone-free', 'silicone-free', null),
    ('dewy-finish', 'dewy finish', 'makeup'),
    ('spf-40', 'spf 40', 'skincare');
insert into product_attributes (product_id, attribute_chip_id, source)
select '30000000-0000-0000-0000-000000000004', id, 'inci' from attribute_chips where slug = 'fragrance-free';

insert into experience_chips (domain, slug, label, valence) values
    ('makeup',   'lasted-all-day',     'lasted all day',     'like'),
    ('makeup',   'oxidized-on-me',     'oxidized on me',     'dislike'),
    ('makeup',   'creased-by-2pm',     'creased by 2pm',     'dislike'),
    ('skincare', 'purged-then-cleared','purged then cleared','like'),
    ('skincare', 'broke-me-out',       'broke me out',       'dislike'),
    ('skincare', 'pilled-under-makeup','pilled under makeup','dislike'),
    ('haircare', 'no-crunch',          'no crunch',          'like'),
    ('haircare', 'weighed-hair-down',  'weighed my hair down','dislike'),
    ('fragrance','lasts-6h',           'lasts 6h',           'like'),
    ('fragrance','fades-fast',         'fades fast',         'dislike');

-- maya's starting shelf: enough for the LIVE picker state to draw something
-- real after a reset — four domains, a rank, and two wear-ins. Deliberately
-- only variants the pgTAP suites do not themselves log for maya (01/02/04/08
-- are theirs), so a suite run against a seeded database cannot collide with
-- the unique (user_id, variant_id).
insert into user_items (user_id, variant_id, status, started_on, client_id) values
    ('00000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000003', 'own', null, '11111111-aaaa-4aaa-8aaa-000000000001'),
    ('00000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000005', 'own', current_date - 14, '11111111-aaaa-4aaa-8aaa-000000000002'),
    ('00000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000006', 'own', null, '11111111-aaaa-4aaa-8aaa-000000000003'),
    ('00000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000007', 'own', null, '11111111-aaaa-4aaa-8aaa-000000000004'),
    ('00000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000009', 'own', current_date - 27, '11111111-aaaa-4aaa-8aaa-000000000005');

insert into rank_positions (user_id, category_id, user_item_id, position)
select '00000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000002', id, 1
from user_items where client_id = '11111111-aaaa-4aaa-8aaa-000000000001';
