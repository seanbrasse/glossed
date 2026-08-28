-- search_catalog respects personal scope; record_failed_search counts demand.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- maya finds canonical products and her own personal one
select test_as('00000000-0000-0000-0000-000000000001');
select ok((select count(*) from search_catalog('soft pinch')) >= 1, 'canonical product is findable');
select ok(exists(select 1 from search_catalog('flaxseed')), 'maya finds her own personal product');
select ok(not exists(select 1 from search_catalog('decanted')), 'maya cannot find juli''s personal product');

-- brand-name matching, since people search by brand first
select ok(exists(select 1 from search_catalog('rare beauty')), 'brand name matches');

-- failed searches count demand rather than duplicating rows
select test_as('00000000-0000-0000-0000-000000000002');
select lives_ok($$ select record_failed_search('glow recipe dew drops', 'skincare') $$, 'records a miss');
select record_failed_search('glow recipe dew drops', 'skincare');

-- users write the queue only through the definer function and cannot read it
-- back, so verification runs with privilege restored.
select is((select count(*)::int from failed_searches), 0, 'users cannot read the failed-search queue');
reset role;
select is(
    (select user_count from failed_searches where lower(query) = 'glow recipe dew drops'),
    2, 'a repeat search bumps the count instead of inserting again');

select * from finish();
rollback;
