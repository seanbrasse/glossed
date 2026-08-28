-- Suite · multi-axis fit (0009). GLO-67.
-- The rule under test is the kit's own: one answer per axis, `just right`
-- exclusive, and the capture replaces the whole answer.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

select is(fit_axis('too_light'), 'depth', 'light is a depth answer');
select is(fit_axis('too_dark'), 'depth', 'dark is a depth answer');
select is(fit_axis('too_pink'), 'undertone', 'pink is an undertone answer');
select is(fit_axis('just_right'), 'just_right', 'just right is its own axis');

-- maya logs her foundation, then says it misses on both axes.
select test_as('00000000-0000-0000-0000-000000000001');
insert into user_items (id, user_id, variant_id, client_id)
values ('50000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000002', 'dddddddd-0000-0000-0000-000000000001');

select lives_ok($$ select capture_fit('50000000-0000-0000-0000-000000000021',
    array['too_light','too_pink']::fit_enum[]) $$,
    'a shade can miss on depth and undertone at once');
select is((select count(*)::int from item_fits where user_item_id = '50000000-0000-0000-0000-000000000021'),
    2, 'two axes are two rows');

-- The anchor view carries both bounds.
select is((select count(*)::int from user_shade_anchor
           where user_id = '00000000-0000-0000-0000-000000000001'
             and variant_id = '40000000-0000-0000-0000-000000000002'),
    2, 'the anchor view carries one bound per axis');

-- The set rules, by name.
select throws_ok($$ select capture_fit('50000000-0000-0000-0000-000000000021',
    array['just_right','too_pink']::fit_enum[]) $$,
    '23514', 'just right stands alone', 'just right does not compose');
select throws_ok($$ select capture_fit('50000000-0000-0000-0000-000000000021',
    array['too_light','too_dark']::fit_enum[]) $$,
    '23514', 'one answer per axis', 'two depth answers are not a statement');

-- A re-capture replaces the whole answer: cleared axes go.
select capture_fit('50000000-0000-0000-0000-000000000021', array['just_right']::fit_enum[]);
select results_eq($$
    select fit::text from item_fits where user_item_id = '50000000-0000-0000-0000-000000000021'
$$, $$ values ('just_right') $$,
   'a re-capture clears what the user cleared');

-- juli cannot write fits onto maya's item — RLS, not the function, is the wall.
select test_as('00000000-0000-0000-0000-000000000002');
select throws_ok($$ select capture_fit('50000000-0000-0000-0000-000000000021',
    array['too_dark']::fit_enum[]) $$,
    '42501', 'new row violates row-level security policy for table "item_fits"',
    'the capture is invoker — RLS still owns ownership');

select * from finish();
rollback;
