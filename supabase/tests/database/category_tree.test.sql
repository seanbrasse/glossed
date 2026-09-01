-- 0057's tree invariants: two levels exactly, leaves inherit their parent's
-- domain, ranking's level is untouched, and the listing's groups all exist.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

-- 1 · two levels EXACTLY — a leaf with children would make "the rankable
-- level" ambiguous, and every picker keys on parent_id is null.
select is(
    (select count(*)::int from categories c
      join categories p on p.id = c.parent_id
      where p.parent_id is not null),
    0, 'no grandchildren — the tree is two levels, full stop');

-- 2 · a leaf's domain is its parent's. A "makeup" leaf under a skincare
-- group would put a product in two domains at once depending on the join.
select is(
    (select count(*)::int from categories c
      join categories p on p.id = c.parent_id
      where c.domain <> p.domain),
    0, 'every leaf inherits its parent''s domain');

-- 3 · the anchor set did not move: foundation, alone. Leaves are vocabulary,
-- never anchors — an anchor leaf would leak shade-evidence semantics onto a
-- level ranking never reads.
select results_eq(
    $$select slug from categories where is_anchor order by slug$$,
    $$values ('foundation')$$,
    'foundation is still the only anchor, and no leaf is one');

-- 4 · the listing's ten new groups exist at the TOP level.
select is(
    (select count(*)::int from categories where parent_id is null and slug in
        ('exfoliant','lipcare','body','device','primer','setting','lashes',
         'tools','haircolor','scalp')),
    10, 'the ten new rankable groups from the listing exist, parentless');

-- 5 · the four relabels wear the listing's headings.
select results_eq(
    $$select label from categories where slug in ('toner','sunscreen','treatment','bronzer')
      order by slug$$,
    $$values ('bronzer + contour'), ('sun'), ('toners + essences'), ('targeted treatments')$$,
    'the existing groups wear the listing''s headings');

-- 6 · leaves carry no ranking semantics of their own.
select is(
    (select count(*)::int from categories
      where parent_id is not null and (wear_in_days <> 0 or is_anchor)),
    0, 'wear-in and anchor stay the parent''s concern');

-- 7 · the vocabulary is actually comprehensive — spot-check one leaf from
-- every domain, including the deepest corners of the listing.
select is(
    (select count(*)::int from categories where slug in
        ('serum-snail-mucin','device-gua-sha','body-kp-treatment',
         'lip-lip-plumper','lashes-magnetic-lashes','styler-edge-control',
         'haircolor-color-depositing-conditioner','fragrance-eau-de-cologne')),
    8, 'the listing''s far corners all landed');

-- 8 · idempotent by slug — 0046's rule holds for the tree too.
create temp table tree_before as select count(*) c from categories;
insert into categories (id, domain, slug, label, wear_in_days, is_anchor, rank_unlock_min, parent_id)
values ('13000000-0000-0000-0000-000000000001', 'skincare', 'exfoliant-physical-scrub',
        'physical scrub', 0, false, 3, (select id from categories where slug = 'exfoliant'))
on conflict (slug) do update set label = excluded.label;
select is((select count(*) from categories), (select c from tree_before),
    're-running a leaf insert updates in place, never duplicates');

select * from finish();
rollback;
