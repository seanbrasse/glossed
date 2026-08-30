-- The seed's users are adults, and it is checkable. GLO-182.
--
-- Every gate in Phase 1.5 refuses a minor, and `is_minor_user` coalesces a
-- MISSING profiles row to minor (0020, deliberately). So a seed that creates
-- auth rows and no profiles rows locks the whole app — and locks it with
-- refusals that are each the documented-correct behaviour of a working gate.
-- Nothing distinguished the two states, which is why it took driving the app
-- to find. This file is that distinction: it fails loudly, before any surface
-- is driven, if the seed's users cannot pass the age gate.
--
-- The invariant is written over "every seeded user", not over two literal
-- ids, so a third seeded user added without a profile fails it too.
begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

-- Vacuity guard: the four assertions after this one are all "no rows are
-- wrong", which an unseeded database satisfies by having no rows at all.
select cmp_ok(
    (select count(*)::int from auth.users where email like '%@local.test'),
    '>=', 2, 'the seed''s local users are present');

select is(
    (select count(*)::int from auth.users u
      where u.email like '%@local.test'
        and not exists (select 1 from profiles p where p.user_id = u.id)),
    0, 'no seeded user is missing a profiles row');

select is(
    (select count(*)::int from auth.users u
      where u.email like '%@local.test' and is_minor_user(u.id)),
    0, 'and no seeded user reads as a minor');

-- The check above can only mean something if it CAN fail. A user id with no
-- profiles row is what a broken seed looks like, so assert the gate still
-- closes on one.
select ok(
    is_minor_user('00000000-0000-0000-0000-0000000000ff'),
    'a user with no profiles row still reads as a minor — the gate is not vacuous');

-- Two surfaces, both PHASE 1.5 (PRD §17) — public identity and the privacy
-- presets. Not can_follow and not swatches: friends are Phase 2, so a seeded
-- user failing those would be the phase, not this bug. Both of these refused
-- before the seed carried profiles, and both refused in words that read like
-- a working gate: "handles are a public identity", "minors are private by
-- construction".
delete from handles where user_id = '00000000-0000-0000-0000-000000000001';
delete from privacy_scopes where user_id = '00000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select set_config('role', 'authenticated', true);

select lives_ok(
    $$select claim_handle('seedgatecheck')$$,
    'maya can claim a handle');
select lives_ok(
    $$insert into privacy_scopes (user_id, rankings)
      values ('00000000-0000-0000-0000-000000000001', 'public')$$,
    'and can set a scope to something other than only_you');

select * from finish();
rollback;
