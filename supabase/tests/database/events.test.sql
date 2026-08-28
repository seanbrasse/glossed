-- Suite · analytics tables (0011). GLO-21 PR 1.
-- The posture under test: no user can touch analytics by any verb, retries
-- dedupe, the bracket never leaks a birthday, and the refresh jobs work.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- The wall: an authenticated user cannot read or write analytics at all.
select test_as('00000000-0000-0000-0000-000000000001');
select throws_ok($$ select count(*) from events $$, '42501', null,
    'a user cannot read raw events');
select throws_ok($$ insert into events (client_id, name, ts)
    values (gen_random_uuid(), 'shelf_viewed', now()) $$, '42501', null,
    'a user cannot write events directly — only the ingest can');
select throws_ok($$ select count(*) from user_facts $$, '42501', null,
    'a user cannot read the facts snapshot');
select throws_ok($$ select count(*) from event_rollups_daily $$, '42501', null,
    'a user cannot read rollups');

reset role;

-- Retries dedupe: the same client id at the same ts inserts once.
insert into events (client_id, user_id, name, props, ts)
values ('eeeeeeee-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
        'item_logged', '{"scope":"canonical"}', now())
on conflict (client_id, ts) do nothing;
insert into events (client_id, user_id, name, props, ts)
select client_id, user_id, name, props, ts from events
where client_id = 'eeeeeeee-0000-0000-0000-000000000001'
on conflict (client_id, ts) do nothing;
select is((select count(*)::int from events where client_id = 'eeeeeeee-0000-0000-0000-000000000001'),
    1, 'a retried event is a no-op, not a duplicate');

-- Rollups aggregate yesterday-shaped data.
insert into events (client_id, user_id, name, ts)
values ('eeeeeeee-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
        'shelf_viewed', current_date - interval '12 hours'),
       ('eeeeeeee-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002',
        'shelf_viewed', current_date - interval '13 hours');
select refresh_event_rollups(current_date - 1);
select is((select users from event_rollups_daily
           where day = current_date - 1 and name = 'shelf_viewed'),
    2, 'the rollup counts distinct users, not rows');

-- The bracket, not the birthday.
select is(age_bracket('2010-06', '2026-08-28'::date), '13-17', 'a sixteen-year-old lands in 13-17');
select is(age_bracket('1998-04', '2026-08-28'::date), '25-34', 'maya lands in 25-34');

-- user_facts snapshots the profile without copying regulated raw values
-- beyond what tech/06 §4 names.
select test_as('00000000-0000-0000-0000-000000000001');
insert into profiles (user_id, birth_year_month, domains, skin_type, tone_band)
values ('00000000-0000-0000-0000-000000000001', '1998-04', '{makeup,skincare}', 'combo', 6);
insert into user_items (id, user_id, variant_id, client_id)
values ('50000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000004', 'ffffffff-0000-0000-0000-000000000001');
reset role;
select refresh_user_facts();
-- shelf_size is compared to the live count rather than a literal: the seed
-- owns how many items maya starts with, and this test owns only that the
-- snapshot counts them correctly.
select results_eq($$
    select age_bracket, shelf_size, two_domain, minor from user_facts
    where user_id = '00000000-0000-0000-0000-000000000001'
$$, $$ select '25-34',
              (select count(*)::int from user_items
                where user_id = '00000000-0000-0000-0000-000000000001' and deleted_at is null),
              true, false $$,
   'the snapshot derives brackets and counts, never raw dates');

-- Partitions: this month and next exist; a far month does not until ensured.
select ok(exists(select 1 from pg_class where relname = 'events_' || to_char(current_date, 'YYYY_MM')),
    'the current month has a partition');
select ok(exists(select 1 from pg_class
    where relname = 'events_' || to_char(current_date + interval '1 month', 'YYYY_MM')),
    'next month is already there — midnight on the 1st cannot lose events');

-- The clock is scheduled.
select is((select count(*)::int from cron.job where jobname in
    ('events-partition-ahead', 'events-retention', 'event-rollups-nightly', 'user-facts-nightly')),
    4, 'all four jobs are on the clock');

select * from finish();
rollback;
