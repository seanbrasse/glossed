-- Grid D · the minors lock. GLO-118, docs/tech/02 §9.5.
--
-- The claim under test is "minors are locked private BY CONSTRUCTION", and the
-- only way to test that honestly is to write the illegal state and prove the
-- READ path still refuses it. A suite that only exercises the write trigger
-- proves half the claim — and it is the half that does not survive a bug, a
-- service_role write, or a future migration.
--
-- So the 12 core cells below insert non-only_you scopes for a minor by
-- DISABLING the trigger, not by going through it.
begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set maya  '00000000-0000-0000-0000-000000000001'
\set juli  '00000000-0000-0000-0000-000000000002'

-- maya is an adult and the viewer. juli is our minor owner: born 15 years ago,
-- so is_minor() is unambiguous regardless of when this runs.
select test_as(:'maya');
insert into profiles (user_id, birth_year_month, domains) values (:'maya', '1998-04', '{makeup}');
select test_as(:'juli');
insert into profiles (user_id, birth_year_month, domains)
values (:'juli', to_char(current_date - interval '15 years', 'YYYY-MM'), '{makeup}');

-- is_minor_user is revoked from authenticated on purpose (0020), so these two
-- run as postgres. Who may reach it is asserted in privacy_core.test.sql.
select set_config('role', 'postgres', true);
select ok(is_minor_user(:'juli'), 'juli reads as a minor');
select ok(not is_minor_user(:'maya'), 'maya does not');

-- ---------------------------------------------------------------------------
-- The 12 cells that matter: an ILLEGAL row, written past the trigger, is still
-- invisible on the read path.
-- ---------------------------------------------------------------------------
select set_config('role', 'postgres', true);
alter table privacy_scopes disable trigger privacy_scopes_minor_lock;
insert into privacy_scopes (user_id, shelf, rankings, routines, looks, discoverable)
values (:'juli', 'public', 'public', 'public', 'public', true);
alter table privacy_scopes enable trigger privacy_scopes_minor_lock;

-- a mutual follow, so `friends` would otherwise be reachable
insert into follows (follower_id, followed_id) values (:'maya', :'juli'), (:'juli', :'maya');

select test_as(:'maya');
select ok(not can_view(:'juli', 'shelf'),    'minor · shelf=public · mutual viewer → invisible');
select ok(not can_view(:'juli', 'rankings'), 'minor · rankings=public · mutual viewer → invisible');
select ok(not can_view(:'juli', 'routines'), 'minor · routines=public · mutual viewer → invisible');
select ok(not can_view(:'juli', 'looks'),    'minor · looks=public · mutual viewer → invisible');

select test_as('00000000-0000-0000-0000-00000000beef');
select ok(not can_view(:'juli', 'shelf'),    'minor · shelf=public · stranger → invisible');
select ok(not can_view(:'juli', 'rankings'), 'minor · rankings=public · stranger → invisible');
select ok(not can_view(:'juli', 'routines'), 'minor · routines=public · stranger → invisible');
select ok(not can_view(:'juli', 'looks'),    'minor · looks=public · stranger → invisible');

-- anon: no JWT at all, the link-card and web-page path
select set_config('role', 'postgres', true);
select set_config('request.jwt.claims', null, true);
select ok(not can_view(null, :'juli', 'shelf'),    'minor · shelf=public · ANON → invisible');
select ok(not can_view(null, :'juli', 'rankings'), 'minor · rankings=public · ANON → invisible');
select ok(not can_view(null, :'juli', 'routines'), 'minor · routines=public · ANON → invisible');
select ok(not can_view(null, :'juli', 'looks'),    'minor · looks=public · ANON → invisible');

-- ---------------------------------------------------------------------------
-- The minor still sees their own everything. The lock is about other people.
-- ---------------------------------------------------------------------------
select test_as(:'juli');
select ok(can_view(:'juli', 'shelf'),    'the minor sees their own shelf');
select ok(can_view(:'juli', 'rankings'), 'the minor sees their own rankings');
select ok(can_view(:'juli', 'routines'), 'the minor sees their own routines');
select ok(can_view(:'juli', 'looks'),    'the minor sees their own looks');

-- ---------------------------------------------------------------------------
-- The write trigger — the polite half.
-- ---------------------------------------------------------------------------
select set_config('role', 'postgres', true);
delete from privacy_scopes where user_id = :'juli';

select test_as(:'juli');
select throws_ok($$
    insert into privacy_scopes (user_id, shelf) values ('00000000-0000-0000-0000-000000000002', 'public')
$$, '23514', null, 'the trigger refuses a minor setting shelf');
select throws_ok($$
    insert into privacy_scopes (user_id, rankings) values ('00000000-0000-0000-0000-000000000002', 'friends')
$$, '23514', null, 'the trigger refuses a minor setting rankings');
select throws_ok($$
    insert into privacy_scopes (user_id, routines) values ('00000000-0000-0000-0000-000000000002', 'public')
$$, '23514', null, 'the trigger refuses a minor setting routines');
select throws_ok($$
    insert into privacy_scopes (user_id, discoverable) values ('00000000-0000-0000-0000-000000000002', true)
$$, '23514', null, 'the trigger refuses a minor setting discoverable');
select lives_ok($$
    insert into privacy_scopes (user_id) values ('00000000-0000-0000-0000-000000000002')
$$, 'a minor CAN have an all-only_you row — the lock restricts the values, not the row');

-- ---------------------------------------------------------------------------
-- The graph: minors cannot be followed.
-- ---------------------------------------------------------------------------
select set_config('role', 'postgres', true);
delete from follows where followed_id = :'juli' or follower_id = :'juli';

select test_as(:'maya');
select throws_ok($$
    insert into follows (follower_id, followed_id)
    values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002')
$$, '42501', 'new row violates row-level security policy for table "follows"',
    'nobody can follow a minor — the edge grants nothing, but it would let an adult assemble a list of minors');

-- a minor may still follow outward
select test_as(:'juli');
select lives_ok($$
    insert into follows (follower_id, followed_id)
    values ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001')
$$, 'a minor CAN follow an adult — domain.md §4 allows it, and it discloses nothing about them');

select * from finish();
rollback;
