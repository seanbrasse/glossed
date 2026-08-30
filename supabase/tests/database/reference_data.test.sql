-- The reference data ships as a migration, not as a dev seed (0046). GLO-51.
--
-- What this guards is the failure it was written for: the category tree and the
-- chip vocabulary lived only in supabase/seed.sql, which is dev-only, so the
-- hosted database had none of it and every screen pointed at production was a
-- working app over an empty table. A test that only ran locally — where the
-- seed had already run — would have passed throughout.
--
-- So these assertions are about the DATA being present in a plain migrated
-- database, and about re-application being safe. CI's db job migrates without
-- seeding, which is exactly the environment that used to be empty.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

-- ---------------------------------------------------------------------------
-- Present at all, which is the whole point.
-- ---------------------------------------------------------------------------
select cmp_ok((select count(*) from categories), '>=', 22::bigint,
    'the category tree is in the database without the dev seed having run');
select cmp_ok((select count(*) from experience_chips), '>=', 171::bigint,
    'the experience-chip vocabulary is too — 171 rows, not the 10 domain-wide ones');
-- Four, not the sixteen a local database shows. The other twelve are
-- INCI-derived (niacinamide, retinoid, bha…) and belong to
-- scripts/inci_enrich.ts, which upserts them alongside the ingredient regex
-- each slug is matched by. Copying them here would put the slug in a migration
-- and its pattern in a script — two owners for one fact, which is the drift
-- this ticket exists to end.
select cmp_ok((select count(*) from attribute_chips), '>=', 4::bigint,
    'the baseline attribute chips ship with the tree; the INCI-derived ones stay with the enricher that defines their patterns');

-- ---------------------------------------------------------------------------
-- The shape the app depends on.
-- ---------------------------------------------------------------------------
-- One per domain, not a threshold: the tree is deliberately lopsided —
-- makeup 10, skincare 8, haircare 3, fragrance 1 — because fragrance has no
-- matching axis to split on and rides taste instead (PRD §04). A count-based
-- assertion would encode today's shape as a rule; an empty domain is the
-- actual defect, because it is a tab that opens on nothing.
select is((select count(distinct domain)::int from categories), 4,
    'all four domains have at least one category');

select ok((select count(*) > 0 from categories where is_anchor),
    'at least one anchor category exists, or onboarding has no anchor question to ask');

-- GLO-154's point: a category with no vocabulary of its own can only offer the
-- domain-wide chips, which is what made a mascara offer "oxidized on me".
select cmp_ok((select count(distinct category_id) from experience_chips where category_id is not null),
    '>=', 22::bigint,
    'every category has chips scoped to it, not just its domain');

-- ---------------------------------------------------------------------------
-- Re-application is safe. This is what makes it a migration rather than a
-- one-shot import: it runs on a fresh database and on one that already has
-- these rows, with the same result.
-- ---------------------------------------------------------------------------
select set_config('role', 'postgres', true);
create temporary table ref_before as
    select (select count(*) from categories) c,
           (select count(*) from experience_chips) e,
           (select count(*) from attribute_chips) a;

insert into categories (id, domain, slug, label, wear_in_days, is_anchor, rank_unlock_min)
values ('10000000-0000-0000-0000-000000000001', 'makeup', 'blush', 'blush', 0, false, 3)
on conflict (slug) do update set label = excluded.label;

select is((select count(*) from categories), (select c from ref_before),
    're-inserting a category by slug updates rather than duplicating');
select is((select label from categories where slug = 'blush'), 'blush',
    'and the row is intact afterwards, not half-written');

select finish();
rollback;
