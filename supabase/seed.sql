-- Deterministic seed (handbook §5.1): two users, four domains, every catalog
-- lifecycle state, including the ugly ones. Local/staging only — never prod.

-- Two local auth users (password: "password" — local only)
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
values
    ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'maya@local.test', extensions.crypt('password', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}'),
    ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'juli@local.test', extensions.crypt('password', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}');

-- Category tree slice: one per domain + wear-in variety (tech/01 §1.1)
insert into categories (id, domain, slug, label, wear_in_days, is_anchor, rank_unlock_min) values
    ('10000000-0000-0000-0000-000000000001', 'makeup',   'blush',      'blush',            0,  false, 3),
    ('10000000-0000-0000-0000-000000000002', 'makeup',   'foundation', 'foundation',       0,  true,  3),
    ('10000000-0000-0000-0000-000000000003', 'skincare', 'cleanser',   'cleanser',         0,  false, 3),
    ('10000000-0000-0000-0000-000000000004', 'skincare', 'serum',      'serums + actives', 56, false, 3),
    ('10000000-0000-0000-0000-000000000005', 'skincare', 'moisturizer','moisturizer',      14, false, 3),
    ('10000000-0000-0000-0000-000000000006', 'haircare', 'styler',     'stylers',          0,  false, 3),
    ('10000000-0000-0000-0000-000000000007', 'fragrance','fragrance',  'fragrance',        0,  false, 3);

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

-- Variants: shades with real n-worthy spread, sizes, a GTIN, real dimensions
insert into variants (id, product_id, kind, shade_code, shade_hex, size_ml, gtin, height_mm, price_cents) values
    ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'shade', '220', '#E0B891', 32, '0810086012340', 110, 4000),
    ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001', 'shade', '240', '#D9A87E', 32, '0810086012341', 110, 4000),
    ('40000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000001', 'shade', '330', '#8C5E3C', 32, '0810086012342', 110, 4000),
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
