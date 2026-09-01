-- The under-13 account floor. GLO-23, migration 0055.
--
-- Companion to `seed_age_gate.test.sql`, which asserts the seed's users are
-- adults. This one asserts the database REFUSES a child — a different claim,
-- and the one that was previously made only by Swift.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

-- ---------------------------------------------------------------- the maths

-- Fixed dates throughout: an age test that reads `current_date` passes today
-- and fails on a birthday, which is the worst kind of red.
select ok(
    is_under_13('2020-01', date '2026-09-01'),
    'a six-year-old is under 13');

select ok(
    not is_under_13('1998-04', date '2026-09-01'),
    'an adult is not');

-- The boundary, both sides. Born some day in August 2013: the earliest turns
-- 13 on 2026-08-01, the latest on 2026-08-31. So 2026-09-01 is the first day
-- the WHOLE month has certainly turned 13, and that is where the floor sits.
select ok(
    not is_under_13('2013-08', date '2026-09-01'),
    'the first certainly-13 day passes the floor');

select ok(
    is_under_13('2013-08', date '2026-08-31'),
    'and the day before it does not');

-- The deliberate month of conservatism, mid-window. On 2026-08-15 someone born
-- in August 2013 has turned 13 if born on the 1st and not if born on the 31st.
-- Only year-month is stored (domain.md §6), so the database cannot tell which
-- — and refuses rather than guesses.
select ok(
    is_under_13('2013-08', date '2026-08-15'),
    'an ambiguous day is refused, not admitted');

-- ------------------------------------------------------------- the trigger

-- `profiles.user_id` references `auth.users`, so the fixtures are real auth
-- rows — the same shape every other suite here uses.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values
    ('a9000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'agefloor-adult@test.local', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''),
    ('a9000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'agefloor-child@test.local', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''),
    ('a9000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'agefloor-nobirthday@test.local', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');

-- Vacuity guard: the refusals below are only meaningful if an ADULT insert
-- succeeds against this same table. Without this, a trigger that rejected
-- everything would pass every assertion after it.
select lives_ok(
    $$insert into profiles (user_id, birth_year_month)
      values ('a9000000-0000-0000-0000-0000000000a1', '1998-04')$$,
    'an adult profile still inserts');

select throws_ok(
    $$insert into profiles (user_id, birth_year_month)
      values ('a9000000-0000-0000-0000-0000000000a2', '2020-01')$$,
    'under the minimum age',
    'a child profile is refused on insert');

-- The UPDATE arm: a row that entered legitimately cannot be walked backwards
-- into a child. Reuses the adult row inserted above.
select throws_ok(
    $$update profiles set birth_year_month = '2020-01'
       where user_id = 'a9000000-0000-0000-0000-0000000000a1'$$,
    'under the minimum age',
    'and cannot be edited into one afterwards');

-- Pinned because the trigger's null branch reads as if it could fire, and it
-- cannot: there is no birthday-less profile to admit or refuse. If this ever
-- goes red, that branch stops being redundant and starts being load-bearing —
-- read it again before relaxing the column.
select col_not_null('public', 'profiles', 'birth_year_month',
    'birth_year_month is NOT NULL, so the trigger never sees a null');

select * from finish();
rollback;
