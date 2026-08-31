-- Routine cadence (0051): the two axes, the discriminated union that stops a
-- routine from being every-3-days AND on-Tuesdays AND a wash day, wash day
-- staying an EVENT rather than a frequency, and the reconciliation that keeps
-- the legacy `slot` projection from ever disagreeing with the cadence.
-- GLO-265. Fixtures in-txn, rolled back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
select id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       email, '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''
from (values
    ('ab000000-0000-0000-0000-000000000001'::uuid, 'cadence-owner@test.local'),
    ('ab000000-0000-0000-0000-000000000002'::uuid, 'cadence-stranger@test.local')
) as u (id, email);

insert into profiles (user_id, birth_year_month, domains) values
    ('ab000000-0000-0000-0000-000000000001', '1990-01', '{makeup}'),
    ('ab000000-0000-0000-0000-000000000002', '1992-06', '{makeup}');

select test_as('ab000000-0000-0000-0000-000000000001');

-- 1-3 · the legacy writer: a client that knows only `slot` still works, and the
-- cadence columns are seeded from it rather than left null
select lives_ok(
    $$insert into routines (id, user_id, title, slot)
      values ('4b000000-0000-0000-0000-000000000001', 'ab000000-0000-0000-0000-000000000001', 'morning', 'am')$$,
    'a slot-only writer — today''s RoutinesRepository — still inserts');
select is((select cadence::text from routines where id = '4b000000-0000-0000-0000-000000000001'),
    'daily', 'and its cadence is seeded, not left null');
select is((select time_of_day::text from routines where id = '4b000000-0000-0000-0000-000000000001'),
    'am', 'and the time-of-day axis is carried across');

-- 4-5 · `weekly` always meant every_n_weeks with n = 1; now it can say so
select lives_ok(
    $$insert into routines (id, user_id, title, slot)
      values ('4b000000-0000-0000-0000-000000000002', 'ab000000-0000-0000-0000-000000000001', 'weekly one', 'weekly')$$,
    'a weekly routine inserts');
select is(
    (select cadence::text || ' n=' || interval_n::text from routines
      where id = '4b000000-0000-0000-0000-000000000002'),
    'every_n_weeks n=1', 'weekly becomes every_n_weeks with n = 1');

-- 6-7 · wash day is an EVENT, and it keeps saying so
select lives_ok(
    $$insert into routines (id, user_id, title, slot)
      values ('4b000000-0000-0000-0000-000000000003', 'ab000000-0000-0000-0000-000000000001', 'wash', 'wash_day')$$,
    'a wash-day routine inserts');
select is(
    (select cadence::text || '/' || event_key from routines
      where id = '4b000000-0000-0000-0000-000000000003'),
    'event/wash_day', 'wash day is an event with an event_key — not a frequency');

-- 8-10 · the thing the old enum could not say at all
select lives_ok(
    $$insert into routines (id, user_id, title, cadence, interval_n, time_of_day)
      values ('4b000000-0000-0000-0000-000000000004', 'ab000000-0000-0000-0000-000000000001',
              'every three days', 'every_n_days', 3, 'pm')$$,
    'every 3 days — inexpressible before this migration');
select lives_ok(
    $$insert into routines (id, user_id, title, cadence, interval_n, time_of_day)
      values ('4b000000-0000-0000-0000-000000000005', 'ab000000-0000-0000-0000-000000000001',
              'bi-weekly', 'every_n_weeks', 2, 'both')$$,
    'bi-weekly, at both ends of the day — also inexpressible before');
select lives_ok(
    $$insert into routines (id, user_id, title, cadence, weekdays)
      values ('4b000000-0000-0000-0000-000000000006', 'ab000000-0000-0000-0000-000000000001',
              'mon wed fri', 'weekdays', array[1,3,5]::smallint[])$$,
    'specific weekdays, ISO 1-7 so they match extract(isodow)');

-- 11-13 · the discriminated union: each cadence permits exactly its own operand
select throws_ok(
    $$insert into routines (user_id, title, cadence, interval_n, weekdays)
      values ('ab000000-0000-0000-0000-000000000001', 'incoherent', 'every_n_days', 3, array[1,2]::smallint[])$$,
    '23514', null, 'every_n_days cannot also carry weekdays');
select throws_ok(
    $$insert into routines (user_id, title, cadence)
      values ('ab000000-0000-0000-0000-000000000001', 'eventless', 'event')$$,
    '23514', null, 'an event cadence without an event_key is refused');
select throws_ok(
    $$insert into routines (user_id, title, cadence, weekdays)
      values ('ab000000-0000-0000-0000-000000000001', 'day zero', 'weekdays', array[0,8]::smallint[])$$,
    '23514', null, 'weekday 0 and 8 do not exist under ISO numbering');

-- 14-15 · `slot` is a PROJECTION and cannot disagree with the cadence, whichever
-- side of the seam the write came from
select is((select slot::text from routines where id = '4b000000-0000-0000-0000-000000000004'),
    'pm', 'a cadence-authored routine still projects a slot for browse_routines');
select is((select slot::text from routines where id = '4b000000-0000-0000-0000-000000000006'),
    'weekly', 'a weekdays cadence buckets as weekly — lossy, but never contradictory');

-- 16-17 · the legacy writer can still change its mind: a slot-only UPDATE
-- re-seeds the cadence rather than being silently reverted by the projection
select lives_ok(
    $$update routines set slot = 'pm' where id = '4b000000-0000-0000-0000-000000000001'$$,
    'a slot-only update is honoured, not overruled by the derived column');
select is((select time_of_day::text || '/' || slot::text from routines
            where id = '4b000000-0000-0000-0000-000000000001'),
    'pm/pm', 'and the cadence followed it');

-- 18 · the event vocabulary is data, and it is not client-writable
select throws_ok(
    $$insert into routine_events (key, label) values ('gym_day', 'gym day')$$,
    '42501', null, 'a client cannot invent an event — reference data stays read-only');

select * from finish();
rollback;
