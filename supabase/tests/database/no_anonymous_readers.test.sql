-- Nothing reads without an account (0060, GLO-258). Sean, Sept 3: "There
-- should be no anonymous callers though? Only public and private
-- profiles/posts." The anonymous key reads the catalog, which onboarding
-- needs before an account exists, and nothing about people.
begin;
create extension if not exists pgtap with schema extensions;
select plan(37);

-- user content: no SELECT for anon, table by table
select ok(not has_table_privilege('anon', 'public.' || t, 'select'), 'anon cannot read ' || t)
from unnest(array[
    'user_items', 'rank_positions', 'routines', 'routine_steps', 'collections', 'collection_items',
    'profiles', 'item_fits', 'item_chips', 'face_offs', 'swatches',
    'user_shelf_items', 'user_shade_anchor', 'scored_face_offs',
    'agg_rank_scores', 'agg_variant_stats', 'shade_cooccurrence',
    'failed_searches', 'audit_records', 'ingest_jobs', 'merge_candidates'
]) as t;

-- the catalog: SELECT and only SELECT
select ok(has_table_privilege('anon', 'public.' || t, 'select'), 'anon still reads the catalog: ' || t)
from unnest(array['brands', 'categories', 'products', 'variants', 'variant_images', 'product_attributes']) as t;
select ok(not has_table_privilege('anon', 'public.' || t, 'insert')
      and not has_table_privilege('anon', 'public.' || t, 'update')
      and not has_table_privilege('anon', 'public.' || t, 'delete'), 'anon writes nothing to ' || t)
from unnest(array['brands', 'categories', 'products', 'variants']) as t;

-- RPCs about people are for accounts; the catalog search is not
select ok(not has_function_privilege('anon', 'public_profile(text)', 'execute'), 'anon cannot call public_profile');
select ok(not has_function_privilege('anon', 'leaderboard(uuid,text,boolean,integer)', 'execute'), 'anon cannot call leaderboard');
select ok(not has_function_privilege('anon', 'can_view(uuid,visibility_surface)', 'execute'), 'anon cannot call can_view');
select ok(has_function_privilege('anon', 'search_catalog(text,domain_enum)', 'execute'), 'anon still searches the catalog — onboarding needs it');

-- the fence: a table made from now on grants anon nothing
create table public.zz_fence_probe (id int);
select ok(not has_table_privilege('anon', 'public.zz_fence_probe', 'select'), 'a new table grants anon nothing by default');
drop table public.zz_fence_probe;

-- the root functions fail closed for a viewer with no account
select ok(not can_view(null, '00000000-0000-0000-0000-000000000001', 'shelf'), 'can_view with no viewer is false, whatever the scope');

select * from finish();
rollback;
