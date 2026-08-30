-- 0046 · The reference data becomes production data. GLO-51.
--
-- The category tree and the whole launch chip vocabulary lived ONLY in
-- supabase/seed.sql — a file whose own header says "Local/staging only — never
-- prod", and which creates fake auth users with a known password. So the
-- hosted database has had zero categories and zero chips since it was created,
-- and every screen pointed at it is a working app over an empty table.
--
-- Verified rather than assumed, against the live hosted project: categories 0,
-- experience_chips 0, attribute_chips 0, brands 0, products 0, variants 0.
--
-- This migration moves the reference data — and only the reference data — into
-- a migration so it applies to every environment the same way. The dev seed
-- keeps the FIXTURES (users, a handful of products, shelf rows); it no longer
-- carries the vocabulary, so the two cannot drift.
--
-- IDEMPOTENT BY SLUG. All three tables carry unique(slug), so re-running
-- updates in place rather than duplicating — which is what lets the same file
-- be safe on a fresh database and on the local one that already has these rows.
-- Category ids stay the explicit literals the seed used, because seeded
-- products reference them and a generated id would orphan every fixture.
--
-- What this does NOT do: the catalog itself. 3,206 products and 9,019 variants
-- exist locally, loaded by scripts/obf_import.ts — which writes by shelling
-- `docker exec` into the local container and so cannot target hosted at all.
-- That is a separate piece of work and it is the remaining half of an empty
-- production database.

-- The V1 category tree. wear_in_days and is_anchor are product decisions;
-- they are carried across verbatim rather than restated here.
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
    ('10000000-0000-0000-0000-000000000008', 'makeup',   'lip',        'lip',              0,  false, 3),
    -- GLO-102 (Sean's ruling, Aug 29): the tree grows to fit what the
    -- storefronts actually sell. Wear-ins follow the existing precedent
    -- values — treatment gets serum's 56 because retinol needs weeks.
    ('10000000-0000-0000-0000-000000000009', 'skincare', 'sunscreen',   'sunscreen',       0,  false, 3),
    ('10000000-0000-0000-0000-000000000010', 'skincare', 'toner',       'toner',           14, false, 3),
    ('10000000-0000-0000-0000-000000000011', 'skincare', 'mask',        'mask',            0,  false, 3),
    ('10000000-0000-0000-0000-000000000012', 'skincare', 'treatment',   'treatment',       56, false, 3),
    ('10000000-0000-0000-0000-000000000013', 'skincare', 'eye',         'eye care',        14, false, 3),
    ('10000000-0000-0000-0000-000000000014', 'haircare', 'shampoo',     'shampoo',         0,  false, 3),
    ('10000000-0000-0000-0000-000000000015', 'haircare', 'conditioner', 'conditioner',     0,  false, 3),
    -- GLO-81, the makeup half — the same "fit most product types" ruling,
    -- driven by the skip tallies (eyeshadow ~154, concealer ~65…). Concealer
    -- stays non-anchor pending Sean's call: it IS shade-matched like
    -- foundation, but anchor status changes the fit-prompt surface and that
    -- is his decision, not a seed row's.
    ('10000000-0000-0000-0000-000000000016', 'makeup',   'eyeshadow',   'eyeshadow',       0,  false, 3),
    ('10000000-0000-0000-0000-000000000017', 'makeup',   'concealer',   'concealer',       0,  false, 3),
    ('10000000-0000-0000-0000-000000000018', 'makeup',   'mascara',     'mascara',         0,  false, 3),
    ('10000000-0000-0000-0000-000000000019', 'makeup',   'eyeliner',    'eyeliner',        0,  false, 3),
    ('10000000-0000-0000-0000-000000000020', 'makeup',   'brow',        'brow',            0,  false, 3),
    ('10000000-0000-0000-0000-000000000021', 'makeup',   'bronzer',     'bronzer',         0,  false, 3),
    ('10000000-0000-0000-0000-000000000022', 'makeup',   'highlighter', 'highlighter',     0,  false, 3)
on conflict (slug) do update
    set domain = excluded.domain,
        label = excluded.label,
        wear_in_days = excluded.wear_in_days,
        is_anchor = excluded.is_anchor,
        rank_unlock_min = excluded.rank_unlock_min;

-- Baseline attribute chips: what a product IS, not how it went.
insert into attribute_chips (slug, label, domain) values
    ('fragrance-free', 'fragrance-free', null),
    ('silicone-free', 'silicone-free', null),
    ('dewy-finish', 'dewy finish', 'makeup'),
    ('spf-40', 'spf 40', 'skincare')
on conflict (slug) do update
    set label = excluded.label,
        domain = excluded.domain;

-- The five experience chips that are genuinely true of every category in
-- their domain (GLO-154) — the rest are category-scoped below.
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
    ('fragrance','fades-fast',         'fades fast',         'dislike')
on conflict (slug) do update
    set domain = excluded.domain,
        label = excluded.label,
        valence = excluded.valence;

-- The category-scoped vocabulary: 7-8 chips per category, so a mascara is
-- never offered "oxidized on me" and a sunscreen can say "white cast"
-- (GLO-154, docs/research/chip-vocabulary.md).
insert into experience_chips (domain, category_id, slug, label, valence)
select c.domain, c.id, v.slug, v.label, v.valence::chip_valence
from (values
    -- makeup ────────────────────────────────────────────────────────────────
    -- foundation is deliberately dislike-heavy: it succeeds by being
    -- unremarkable and fails in five specific, nameable ways.
    ('foundation',  'foundation-looked-like-skin',      'looked like skin',              'like'),
    ('foundation',  'foundation-no-powder-needed',      'didn''t need powder',           'like'),
    ('foundation',  'foundation-buildable',             'buildable without cake',        'like'),
    ('foundation',  'foundation-separated-over-oil',    'separated over my oil',         'dislike'),
    ('foundation',  'foundation-clung-to-dry-patches',  'clung to dry patches',          'dislike'),
    ('foundation',  'foundation-flashback',             'flashback in photos',           'dislike'),
    ('foundation',  'foundation-transferred',           'transferred onto everything',   'dislike'),

    ('concealer',   'concealer-covered-without-cake',   'covered without cake',          'like'),
    ('concealer',   'concealer-brightened',             'brightened under my eyes',      'like'),
    ('concealer',   'concealer-no-setting-needed',      'stayed without setting powder', 'like'),
    ('concealer',   'concealer-oxidized',               'oxidized on me',                'dislike'),
    ('concealer',   'concealer-dragged',                'dragged on my skin',            'dislike'),
    ('concealer',   'concealer-set-too-fast',           'set before I could blend',      'dislike'),
    ('concealer',   'concealer-didnt-cover',            'didn''t cover my circles',      'dislike'),

    ('blush',       'blush-blended-easily',             'blended easily',                'like'),
    ('blush',       'blush-true-to-pan',                'true to the pan',               'like'),
    ('blush',       'blush-buildable',                  'hard to overdo',                'like'),
    ('blush',       'blush-patchy-over-foundation',     'patchy over foundation',        'dislike'),
    ('blush',       'blush-too-pigmented',              'one tap was too much',          'dislike'),
    ('blush',       'blush-faded-by-noon',              'faded by noon',                 'dislike'),
    ('blush',       'blush-moved-my-base',              'moved the foundation under it', 'dislike'),

    ('bronzer',     'bronzer-warmth-not-mud',           'warmth, not mud',               'like'),
    ('bronzer',     'bronzer-blended-seamlessly',       'blended seamlessly',            'like'),
    ('bronzer',     'bronzer-buildable-depth',          'built up without going muddy',  'like'),
    ('bronzer',     'bronzer-went-orange',              'went orange on me',             'dislike'),
    ('bronzer',     'bronzer-read-grey',                'read grey on me',               'dislike'),
    ('bronzer',     'bronzer-patchy',                   'grabbed in patches',            'dislike'),
    ('bronzer',     'bronzer-chalky',                   'chalky in the pan',             'dislike'),

    ('highlighter', 'highlighter-glow-not-glitter',     'glow, not glitter',             'like'),
    ('highlighter', 'highlighter-smooth-over-texture',  'sat smooth over texture',       'like'),
    ('highlighter', 'highlighter-photographed-well',    'photographed well',             'like'),
    ('highlighter', 'highlighter-glittery',             'more glitter than glow',        'dislike'),
    ('highlighter', 'highlighter-emphasized-pores',     'emphasized my pores',           'dislike'),
    ('highlighter', 'highlighter-patchy-over-base',     'patchy over my base',           'dislike'),
    ('highlighter', 'highlighter-disappeared',          'disappeared by lunch',          'dislike'),

    ('eyeshadow',   'eyeshadow-blended-easily',         'blended with no effort',        'like'),
    ('eyeshadow',   'eyeshadow-one-swipe-payoff',       'one swipe payoff',              'like'),
    ('eyeshadow',   'eyeshadow-no-primer-needed',       'held without primer',           'like'),
    ('eyeshadow',   'eyeshadow-creased',                'creased on my lids',            'dislike'),
    ('eyeshadow',   'eyeshadow-patchy-without-primer',  'patchy without primer',         'dislike'),
    ('eyeshadow',   'eyeshadow-fallout',                'fallout under my eyes',         'dislike'),
    ('eyeshadow',   'eyeshadow-went-muddy',             'went muddy when I blended',     'dislike'),
    ('eyeshadow',   'eyeshadow-sheer-payoff',           'barely showed up',              'dislike'),

    ('eyeliner',    'eyeliner-sharp-line',              'sharp line, first try',         'like'),
    ('eyeliner',    'eyeliner-didnt-budge',             'didn''t budge',                 'like'),
    ('eyeliner',    'eyeliner-stayed-on-waterline',     'stayed on my waterline',        'like'),
    ('eyeliner',    'eyeliner-transferred-to-lid',      'transferred to my upper lid',   'dislike'),
    ('eyeliner',    'eyeliner-dragged',                 'dragged on my lid',             'dislike'),
    ('eyeliner',    'eyeliner-skipped',                 'skipped and dried out',         'dislike'),
    ('eyeliner',    'eyeliner-left-my-waterline',       'gone from my waterline by noon','dislike'),

    ('mascara',     'mascara-held-a-curl',              'held my curl all day',          'like'),
    ('mascara',     'mascara-separated-lashes',         'separated, no clumps',          'like'),
    ('mascara',     'mascara-came-off-easily',          'came off without scrubbing',    'like'),
    ('mascara',     'mascara-flaked',                   'flaked onto my cheeks',         'dislike'),
    ('mascara',     'mascara-smudged-under-eyes',       'smudged under my eyes',         'dislike'),
    ('mascara',     'mascara-clumped',                  'clumped on the second coat',    'dislike'),
    ('mascara',     'mascara-dropped-my-curl',          'dropped my curl',               'dislike'),
    ('mascara',     'mascara-dried-out-fast',           'dried out within a month',      'dislike'),

    ('brow',        'brow-matched-my-hair',             'matched my hair',               'like'),
    ('brow',        'brow-hairlike-strokes',            'hairlike, not drawn on',        'like'),
    ('brow',        'brow-stayed-all-day',              'still there at the end of day', 'like'),
    ('brow',        'brow-too-warm',                    'too red on me',                 'dislike'),
    ('brow',        'brow-too-grey',                    'too grey on me',                'dislike'),
    ('brow',        'brow-wore-off',                    'wore off by afternoon',         'dislike'),
    ('brow',        'brow-hard-to-control',             'too much product, too fast',    'dislike'),

    ('lip',         'lip-comfortable-all-day',          'comfortable all day',           'like'),
    ('lip',         'lip-faded-evenly',                 'faded evenly',                  'like'),
    ('lip',         'lip-one-coat-opaque',              'opaque in one coat',            'like'),
    ('lip',         'lip-dried-me-out',                 'dried my lips out',             'dislike'),
    ('lip',         'lip-feathered',                    'feathered past my lip line',    'dislike'),
    ('lip',         'lip-transferred',                  'transferred onto everything',   'dislike'),
    ('lip',         'lip-sticky',                       'sticky — hair stuck to it',     'dislike'),
    ('lip',         'lip-patchy-on-dry-lips',           'patchy on dry lips',            'dislike'),

    -- skincare ──────────────────────────────────────────────────────────────
    ('cleanser',    'cleanser-clean-not-tight',         'clean, not tight',              'like'),
    ('cleanser',    'cleanser-took-off-spf',            'took off spf in one pass',      'like'),
    ('cleanser',    'cleanser-gentle-enough-daily',     'gentle enough twice a day',     'like'),
    ('cleanser',    'cleanser-stripped-me',             'left my skin tight',            'dislike'),
    ('cleanser',    'cleanser-stung-my-eyes',           'stung my eyes',                 'dislike'),
    ('cleanser',    'cleanser-left-a-film',             'left a film',                   'dislike'),
    ('cleanser',    'cleanser-didnt-remove-makeup',     'didn''t get my makeup off',     'dislike'),

    -- serum carries the 56-day wear-in, so "nothing after 8 weeks" is a fact
    -- the gate makes sayable — and it is the most useful thing an active can
    -- tell a stranger.
    ('serum',       'serum-faded-my-marks',             'faded my dark marks',           'like'),
    ('serum',       'serum-smoothed-texture',           'my texture smoothed out',       'like'),
    ('serum',       'serum-layered-clean',              'layered clean under everything','like'),
    ('serum',       'serum-stung',                      'stung going on',                'dislike'),
    ('serum',       'serum-pilled',                     'pilled under everything else',  'dislike'),
    ('serum',       'serum-never-absorbed',             'tacky, never absorbed',         'dislike'),
    ('serum',       'serum-nothing-after-8-weeks',      'nothing after 8 weeks',         'dislike'),

    ('moisturizer', 'moisturizer-absorbed-fast',        'absorbed fast',                 'like'),
    ('moisturizer', 'moisturizer-held-all-day',         'still hydrated at bedtime',     'like'),
    ('moisturizer', 'moisturizer-layered-clean',        'sat well under makeup',         'like'),
    ('moisturizer', 'moisturizer-too-heavy',            'too heavy, sat on top',         'dislike'),
    ('moisturizer', 'moisturizer-not-enough-in-winter', 'not enough in winter',          'dislike'),
    ('moisturizer', 'moisturizer-clogged-me',           'clogged my pores',              'dislike'),

    -- the white-cast pair is the clearest case for splitting an axis rather
    -- than reaching for a neutral: the same product casts on one person and
    -- not another, so the valence carries the personal half.
    ('sunscreen',   'sunscreen-no-white-cast',          'no white cast on me',           'like'),
    ('sunscreen',   'sunscreen-invisible-under-makeup', 'invisible under makeup',        'like'),
    ('sunscreen',   'sunscreen-reapplied-easily',       'reapplied over makeup fine',    'like'),
    ('sunscreen',   'sunscreen-white-cast',             'white cast on me',              'dislike'),
    ('sunscreen',   'sunscreen-stung-my-eyes',          'stung my eyes',                 'dislike'),
    ('sunscreen',   'sunscreen-pilled',                 'pilled under makeup',           'dislike'),
    ('sunscreen',   'sunscreen-greasy',                 'greasy all day',                'dislike'),
    ('sunscreen',   'sunscreen-smelled-bad',            'smelled like sunscreen',        'dislike'),

    ('toner',       'toner-calmed-redness',             'calmed my redness',             'like'),
    ('toner',       'toner-smoothed-texture',           'smoothed my texture',           'like'),
    ('toner',       'toner-absorbed-fast',              'absorbed instantly',            'like'),
    ('toner',       'toner-stung',                      'stung going on',                'dislike'),
    ('toner',       'toner-dried-me-out',               'dried me out',                  'dislike'),
    ('toner',       'toner-sticky',                     'left my skin sticky',           'dislike'),
    ('toner',       'toner-no-difference',              'no difference either way',      'dislike'),

    ('mask',        'mask-instant-glow',                'glowy right after',             'like'),
    ('mask',        'mask-calmed-a-flare',              'calmed a flare-up',             'like'),
    ('mask',        'mask-drew-out-congestion',         'drew out congestion',           'like'),
    ('mask',        'mask-stung',                       'stung the whole time',          'dislike'),
    ('mask',        'mask-left-me-red',                 'left me red for hours',         'dislike'),
    ('mask',        'mask-dried-tight',                 'dried down painfully tight',    'dislike'),
    ('mask',        'mask-hard-to-remove',              'a fight to rinse off',          'dislike'),

    -- the arc pair: "purged then cleared" (narrowed to serum above, duplicated
    -- here) has an opposite that is not "did not purge".
    ('treatment',   'treatment-purged-then-cleared',    'purged then cleared',           'like'),
    ('treatment',   'treatment-faded-my-marks',         'faded my dark marks',           'like'),
    ('treatment',   'treatment-worth-the-retinization', 'worth the retinization',        'like'),
    ('treatment',   'treatment-texture-smoothed',       'my texture smoothed out',       'like'),
    ('treatment',   'treatment-purge-never-cleared',    'purged and never cleared',      'dislike'),
    ('treatment',   'treatment-peeled-for-weeks',       'peeled for weeks',              'dislike'),
    ('treatment',   'treatment-burned',                 'burned going on',               'dislike'),
    ('treatment',   'treatment-sun-sensitive',          'made me sun-sensitive',         'dislike'),

    ('eye',         'eye-depuffed',                     'depuffed in the morning',       'like'),
    ('eye',         'eye-smoothed-concealer',           'concealer sat better over it',  'like'),
    ('eye',         'eye-absorbed-fast',                'absorbed fast',                 'like'),
    ('eye',         'eye-milia',                        'gave me milia',                 'dislike'),
    ('eye',         'eye-pilled-under-concealer',       'pilled under concealer',        'dislike'),
    ('eye',         'eye-stung-my-eyes',                'stung my eyes',                 'dislike'),
    ('eye',         'eye-too-heavy',                    'too heavy for daytime',         'dislike'),
    ('eye',         'eye-no-difference',                'no difference in a month',      'dislike'),

    -- haircare ──────────────────────────────────────────────────────────────
    ('shampoo',     'shampoo-clean-not-stripped',       'clean, not stripped',           'like'),
    ('shampoo',     'shampoo-calmed-my-scalp',          'calmed my scalp',               'like'),
    ('shampoo',     'shampoo-lathered-well',            'lathered with barely any',      'like'),
    ('shampoo',     'shampoo-color-held',               'my color held',                 'like'),
    ('shampoo',     'shampoo-stripped-my-hair',         'stripped my hair',              'dislike'),
    ('shampoo',     'shampoo-scalp-itch',               'scalp itched after',            'dislike'),
    ('shampoo',     'shampoo-faded-my-color-fast',      'faded my color fast',           'dislike'),
    ('shampoo',     'shampoo-tangled-my-hair',          'tangled it into knots',         'dislike'),

    ('conditioner', 'conditioner-detangled-easily',     'detangled in one pass',         'like'),
    ('conditioner', 'conditioner-soft-not-greasy',      'soft, not greasy',              'like'),
    ('conditioner', 'conditioner-slip-in-the-shower',   'real slip in the shower',       'like'),
    ('conditioner', 'conditioner-greasy-roots',         'greasy roots by day two',       'dislike'),
    ('conditioner', 'conditioner-no-slip',              'not enough slip to detangle',   'dislike'),
    ('conditioner', 'conditioner-did-nothing',          'rinsed out to nothing',         'dislike'),
    ('conditioner', 'conditioner-built-up',             'built up over a week',          'dislike'),

    ('styler',      'styler-held-in-humidity',          'held in humidity',              'like'),
    ('styler',      'styler-defined-without-stiffness', 'defined, not stiff',            'like'),
    ('styler',      'styler-second-day-hair',           'second-day hair still good',    'like'),
    ('styler',      'styler-crunchy-cast',              'crunchy cast',                  'dislike'),
    ('styler',      'styler-flaked',                    'flaked white',                  'dislike'),
    ('styler',      'styler-frizz-by-hour-3',           'frizz by hour 3',               'dislike'),
    ('styler',      'styler-sticky',                    'sticky to the touch',           'dislike'),

    -- fragrance ─────────────────────────────────────────────────────────────
    -- longevity (the two domain-wide chips) and projection are independent
    -- axes: a scent can last nine hours and never leave a two-inch radius.
    -- "turned on my skin" is the most personal fact in the domain, and so the
    -- one a stranger most needs cohort-matched.
    ('fragrance',   'fragrance-projected',              'projected across the room',     'like'),
    ('fragrance',   'fragrance-drydown-beat-the-open',  'the drydown beat the opening',  'like'),
    ('fragrance',   'fragrance-got-compliments',        'got compliments',               'like'),
    ('fragrance',   'fragrance-smells-like-nothing-else','smells like nothing else I own','like'),
    ('fragrance',   'fragrance-skin-scent-only',        'stayed a skin scent',           'dislike'),
    ('fragrance',   'fragrance-turned-on-my-skin',      'turned on my skin',             'dislike'),
    ('fragrance',   'fragrance-gave-me-a-headache',     'gave me a headache',            'dislike'),
    ('fragrance',   'fragrance-smells-generic',         'smells like everything else',   'dislike')
) as v(category, slug, label, valence)
join categories c on c.slug = v.category
on conflict (slug) do update
    set domain = excluded.domain,
        category_id = excluded.category_id,
        label = excluded.label,
        valence = excluded.valence;
