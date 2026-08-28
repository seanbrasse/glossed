-- Isolation suite · catalog (handbook §10.1 / CLAUDE.md rule):
-- two seeded users; assert personal-scope rows never cross users, by any verb.
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

-- helper: impersonate a seeded user through PostgREST's auth path
create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- 1-2 · both users see the canonical catalog
select test_as('00000000-0000-0000-0000-000000000001');
select ok((select count(*) from products where scope = 'canonical') > 0, 'maya sees canonical products');
select ok(exists(select 1 from variants where id = '40000000-0000-0000-0000-000000000002'), 'maya sees canonical variants');

-- 3-4 · maya sees her own personal product, and not juli''s
select ok(exists(select 1 from products where id = '30000000-0000-0000-0000-000000000009'), 'maya sees her personal product');
select ok(not exists(select 1 from products where id = '30000000-0000-0000-0000-00000000000a'),
    'maya cannot see juli''s personal product by id');

-- 5 · nor its variants
select ok(exists(select 1 from variants where id = '40000000-0000-0000-0000-000000000008'), 'maya sees her personal variant');

-- 6-7 · juli, symmetric
select test_as('00000000-0000-0000-0000-000000000002');
select ok(not exists(select 1 from products where id = '30000000-0000-0000-0000-000000000009'),
    'juli cannot see maya''s personal product by id');
select ok(not exists(select 1 from variants where id = '40000000-0000-0000-0000-000000000008'),
    'juli cannot see maya''s personal variant by id');

-- 8 · cross-user update is a no-op (RLS filters the row before the write)
select lives_ok($$ update products set name = 'hijacked' where id = '30000000-0000-0000-0000-000000000009' $$,
    'cross-user update executes');
select test_as('00000000-0000-0000-0000-000000000001');
select is((select name from products where id = '30000000-0000-0000-0000-000000000009'), 'flaxseed curl gel',
    'cross-user update changed nothing');

-- 10 · users cannot insert canonical products
select test_as('00000000-0000-0000-0000-000000000002');
select throws_ok($$
    insert into products (brand_id, category_id, domain, name, normalized_name, scope, created_by)
    values ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000003',
            'skincare', 'sneaky canonical', 'sneaky canonical', 'canonical', '00000000-0000-0000-0000-000000000002')
$$, '42501', 'new row violates row-level security policy for table "products"',
    'user cannot insert a canonical product');

select * from finish();
rollback;
