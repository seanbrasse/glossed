-- trending() + refresh_trending() (0030). GLO-127, docs/tech/02 §4.
--
-- Two units, tested at their real boundary. refresh_trending() turns
-- user_items into an aggregate; trending() reads that aggregate and renders
-- min-n. Crafted agg rows exercise the read contract without fabricating six
-- auth users to cross a threshold, and the refresh half is asserted against
-- user_items where it belongs.
--
-- Every refresh exclusion is asserted SEPARATELY from a fully-eligible
-- baseline. "It returned nothing" passes for six different reasons here.
begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set maya '00000000-0000-0000-0000-000000000001'
\set juli '00000000-0000-0000-0000-000000000002'
\set pid  '31000000-0000-0000-0000-0000000000f1'
\set vid  '41000000-0000-0000-0000-0000000000f1'

-- A catalog row this test fully controls: scope, delisting and merges are
-- three of the exclusions below, and they cannot be toggled on seed rows
-- other tests depend on.
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope)
values (:'pid', '20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001',
        'makeup', 'trending fixture', 'trending fixture', 'canonical');
insert into variants (id, product_id, kind, shade_code) values (:'vid', :'pid', 'shade', 'f1');

-- Upserts: the seed writes both profiles rows now (GLO-182). juli's skin_type
-- is set to NULL explicitly rather than omitted — "deliberately no skin_type"
-- has to survive a pre-existing row, or the cohort split stops being a split.
insert into profiles (user_id, birth_year_month, domains, skin_type)
values (:'maya', '1998-04', '{makeup}', 'combo')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month,
    domains = excluded.domains, skin_type = excluded.skin_type;
insert into profiles (user_id, birth_year_month, domains, skin_type)
values (:'juli', '1996-09', '{makeup}', null)   -- deliberately no skin_type
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month,
    domains = excluded.domains, skin_type = excluded.skin_type;

-- ---------------------------------------------------------------------------
-- Shape and reach. agg_trending was created after 0024/0027 swept the tables
-- that existed then, so its grants are asserted rather than assumed.
-- ---------------------------------------------------------------------------
select has_table('agg_trending', 'agg_trending exists');

select ok((select relrowsecurity from pg_class where relname = 'agg_trending'),
    'RLS is enabled on agg_trending');

select is((select count(*)::int from information_schema.table_privileges
            where table_name = 'agg_trending' and grantee in ('anon', 'authenticated')), 0,
    'anon and authenticated hold NO table privileges on agg_trending — the aggregate is reachable only through the RPC. 0024 and 0027 swept the tables that existed at the time; this one arrived later and Supabase default privileges hand new tables to anon unless told otherwise.');

select ok(not has_function_privilege('anon', 'refresh_trending()', 'execute'),
    'anon cannot execute refresh_trending() — it reads user_items');
select ok(not has_function_privilege('authenticated', 'refresh_trending()', 'execute'),
    'authenticated cannot execute refresh_trending() either');
select ok(has_function_privilege('anon', 'trending(text, int)', 'execute'),
    'anon CAN execute trending() — trending is products, not people, so it is open to logged-out browse');

-- ---------------------------------------------------------------------------
-- The read contract, over crafted aggregate rows.
--
-- MIN-N IS RENDERED, NOT HIDDEN. This is the assertion the whole surface
-- turns on: a thin surface must look honest, not empty.
-- ---------------------------------------------------------------------------
delete from agg_trending;
insert into agg_trending (variant_id, skin_type, n_logs, window_days) values
    (:'vid', null, min_n_trending() - 1, trending_window_days());

select is((select count(*)::int from trending()), 1,
    'a BELOW-threshold row is still returned — min-n is rendered, not hidden (tech/02 §4, matching the leaderboard in tech/01 §3)');
select is((select n_logs from trending()), min_n_trending() - 1,
    'and it carries its own n, so the client can say "not enough yet · k of N"');
select is((select min_n from trending()), min_n_trending(),
    'and the threshold beside it, so the claim carries its n without the client hard-coding one');
select ok(not (select meets_min_n from trending()),
    'meets_min_n is false below the threshold');

update agg_trending set n_logs = min_n_trending() where variant_id = :'vid';
select ok((select meets_min_n from trending()),
    'meets_min_n flips true AT the threshold, not one past it');

select is((select window_days from trending()), trending_window_days(),
    'the window travels with the row — a claim about velocity is meaningless without the period it is over');

-- Cohort routing. The default argument must select the all-skin-types cohort,
-- not "every row regardless of cohort" — otherwise every variant appears twice.
insert into agg_trending (variant_id, skin_type, n_logs, window_days)
values (:'vid', 'combo', 99, trending_window_days());

select is((select count(*)::int from trending()), 1,
    'trending() with no skin type returns the all-skin-types cohort ONLY — not both cohorts of the same variant');
select is((select n_logs from trending('combo')), 99,
    'trending(skin_type) selects that cohort');
select is((select count(*)::int from trending('dry')), 0,
    'a cohort with no rows is empty, not a silent fallback to overall');

-- Ordering, and the cap. A caller asking for 10000 rows gets 100.
insert into agg_trending (variant_id, skin_type, n_logs, window_days)
values ('40000000-0000-0000-0000-000000000003', null, 1, trending_window_days());
select is((select variant_id from trending() limit 1), :'vid'::uuid,
    'higher n sorts first, so below-threshold rows fall under every qualifying row for free');
select ok((select count(*)::int from trending(null, 10000)) <= 100,
    'p_limit is capped at 100 — an unbounded aggregate read is a denial-of-service surface');

-- ---------------------------------------------------------------------------
-- refresh_trending(): each exclusion, one at a time, from an eligible
-- baseline. Assertions are scoped to the fixture variant — the seed carries
-- its own logs and absolute counts would drift under them.
-- ---------------------------------------------------------------------------
insert into user_items (id, user_id, variant_id, status, client_id) values
    ('51000000-0000-0000-0000-0000000000f1', :'maya', :'vid', 'own', 'eeeeeeee-1000-0000-0000-0000000000f1'),
    ('51000000-0000-0000-0000-0000000000f2', :'juli', :'vid', 'own', 'eeeeeeee-1000-0000-0000-0000000000f2');

select refresh_trending();
select is((select n_logs from agg_trending where variant_id = :'vid' and cohort_key = '-'), 2,
    'BASELINE — two own logs inside the window on a canonical product are counted');

-- The per-skin-type half, and the collision guard that makes it safe.
select is((select n_logs from agg_trending where variant_id = :'vid' and cohort_key = 'combo'), 1,
    'the combo cohort counts only the combo-skinned logger');
select is((select count(*)::int from agg_trending where variant_id = :'vid'), 2,
    'a logger with NO skin_type produces no second `-` row: the overall and per-cohort inserts would collide on the primary key without the `skin_type is not null` filter');
select ok((select n_logs from agg_trending where variant_id = :'vid' and cohort_key = '-')
        > (select n_logs from agg_trending where variant_id = :'vid' and cohort_key = 'combo'),
    'the overall cohort counts people with no skin type, so it is not merely the sum of the typed cohorts');

-- (1) want_to_try. Sean's Aug 29 ruling keeps it unpublished, and §4 asks for
-- ownership velocity — a wishlist surface would be a different feature.
update user_items set status = 'want_to_try' where id = '51000000-0000-0000-0000-0000000000f1';
select refresh_trending();
select is((select n_logs from agg_trending where variant_id = :'vid' and cohort_key = '-'), 1,
    'EXCLUSION 1 — a want_to_try log is not ownership velocity');
update user_items set status = 'own' where id = '51000000-0000-0000-0000-0000000000f1';

-- (2) soft deletion.
update user_items set deleted_at = now() where id = '51000000-0000-0000-0000-0000000000f1';
select refresh_trending();
select is((select n_logs from agg_trending where variant_id = :'vid' and cohort_key = '-'), 1,
    'EXCLUSION 2 — a soft-deleted item stops contributing');
update user_items set deleted_at = null where id = '51000000-0000-0000-0000-0000000000f1';

-- (3) the window itself. Without this the surface is a lifetime leaderboard
-- wearing the word "trending".
update user_items set created_at = now() - make_interval(days => trending_window_days() + 1)
 where id = '51000000-0000-0000-0000-0000000000f1';
select refresh_trending();
select is((select n_logs from agg_trending where variant_id = :'vid' and cohort_key = '-'), 1,
    'EXCLUSION 3 — a log older than the window does not count');
update user_items set created_at = now() where id = '51000000-0000-0000-0000-0000000000f1';

-- (4) personal-scope products never aggregate (domain.md §3.1).
update products set scope = 'personal', created_by = :'maya' where id = :'pid';
select refresh_trending();
select is((select count(*)::int from agg_trending where variant_id = :'vid'), 0,
    'EXCLUSION 4 — a personal-scope product never aggregates, so it cannot trend');
update products set scope = 'canonical', created_by = null where id = :'pid';

-- (5) delisted. Trending is a discovery surface; sending people at something
-- they cannot buy is worse than showing them nothing.
update products set delisted_at = now() where id = :'pid';
select refresh_trending();
select is((select count(*)::int from agg_trending where variant_id = :'vid'), 0,
    'EXCLUSION 5 — a delisted SKU does not trend');
update products set delisted_at = null where id = :'pid';

-- (6) merged away. The survivor carries the shelves; the loser is an alias.
update products set merged_into = '30000000-0000-0000-0000-000000000001' where id = :'pid';
select refresh_trending();
select is((select count(*)::int from agg_trending where variant_id = :'vid'), 0,
    'EXCLUSION 6 — a merged-away product does not trend under its own id');
update products set merged_into = null where id = :'pid';

-- And back to eligible, so the six exclusions are proven to be the reason
-- rather than the fixture having quietly broken somewhere above.
select refresh_trending();
select is((select n_logs from agg_trending where variant_id = :'vid' and cohort_key = '-'), 2,
    'RESTORED — with every exclusion undone the baseline returns, so each zero above was caused by the thing under test');

-- Refresh is a full rebuild: a variant that has left the window must leave the
-- table, not linger at its last count.
delete from user_items where id in ('51000000-0000-0000-0000-0000000000f1', '51000000-0000-0000-0000-0000000000f2');
select refresh_trending();
select is((select count(*)::int from agg_trending where variant_id = :'vid'), 0,
    'refresh is a REBUILD, not an upsert — a variant with no logs left in the window disappears rather than freezing at its last value');

select finish();
rollback;
