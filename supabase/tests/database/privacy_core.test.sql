-- Smoke suite · privacy core (0020): the objects exist, the defaults are right,
-- the grants are right, and the two triggers fire. GLO-115.
--
-- The viewer-pair grids live in GLO-117 (A/B/H) and GLO-118 (C/D). This file
-- deliberately does NOT re-test can_view's matrix — it proves the migration
-- landed the shape those grids will then exercise.
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- ---------------------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------------------
select has_table('privacy_scopes', 'privacy_scopes exists');
select has_table('follows', 'follows exists');
select has_table('blocks', 'blocks exists');
select has_table('mutes', 'mutes exists');

select is(
    (select array_agg(e.enumlabel::text order by e.enumsortorder)
       from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typname = 'scope_enum'),
    array['only_you', 'friends', 'public'],
    'scope_enum is only_you/friends/public — NOT just_you, NOT private (Sean, Aug 29)');

-- ---------------------------------------------------------------------------
-- Fixtures. BOTH users need a profiles row before anything below is meaningful:
-- is_minor_user() is coalesce(..., true), so a user without one reads as a minor
-- and can_view short-circuits to false on the minor lock — which would make the
-- scope assertions below pass for entirely the wrong reason. The seeded DB has
-- no profiles rows, so this is not hypothetical.
-- ---------------------------------------------------------------------------
select test_as('00000000-0000-0000-0000-000000000001');
select lives_ok($$
    insert into profiles (user_id, birth_year_month, domains)
    values ('00000000-0000-0000-0000-000000000001', '1998-04', '{makeup}')
$$, 'maya has a profile, so she is not treated as a minor');
select test_as('00000000-0000-0000-0000-000000000002');
select lives_ok($$
    insert into profiles (user_id, birth_year_month, domains)
    values ('00000000-0000-0000-0000-000000000002', '1996-09', '{makeup}')
$$, 'juli has a profile too');

-- ---------------------------------------------------------------------------
-- Defaults. Asserted, not assumed: default-deny is the gate's whole premise.
-- ---------------------------------------------------------------------------
select test_as('00000000-0000-0000-0000-000000000001');
select lives_ok($$
    insert into privacy_scopes (user_id) values ('00000000-0000-0000-0000-000000000001')
$$, 'maya gets a scopes row with every column defaulted');

select results_eq($$
    select shelf::text, rankings::text, routines::text, looks::text, discoverable
      from privacy_scopes where user_id = '00000000-0000-0000-0000-000000000001'
$$, $$ values ('only_you', 'only_you', 'only_you', 'only_you', false) $$,
    'all four surfaces default only_you and discoverable defaults false');

-- ---------------------------------------------------------------------------
-- can_view: owner short-circuit, and the missing-row default.
-- ---------------------------------------------------------------------------
select ok(can_view('00000000-0000-0000-0000-000000000001', 'shelf'),
    'the owner always sees their own shelf');

select test_as('00000000-0000-0000-0000-000000000002');
select ok(not can_view('00000000-0000-0000-0000-000000000001', 'shelf'),
    'a stranger sees nothing at the only_you default');

-- juli has no privacy_scopes row at all — absence must read as a no, not a gap
-- juli has a profile (so the minor lock does NOT fire) but no privacy_scopes
-- row at all. This is the assertion that proves absence reads as a no.
select test_as('00000000-0000-0000-0000-000000000001');
select ok(not can_view('00000000-0000-0000-0000-000000000002', 'shelf'),
    'a user with a profile but NO scopes row is invisible — no row is a no, not a missing answer');

-- ---------------------------------------------------------------------------
-- Grants. The 3-arg core must not be reachable by clients.
-- ---------------------------------------------------------------------------
select ok(not has_function_privilege('authenticated',
        'can_view(uuid,uuid,visibility_surface)', 'execute'),
    'the 3-arg can_view is NOT executable by authenticated — it would let a client probe any pair');
select ok(has_function_privilege('authenticated',
        'can_view(uuid,visibility_surface)', 'execute'),
    'the 2-arg wrapper IS executable by authenticated');
select ok(has_function_privilege('anon',
        'can_view(uuid,visibility_surface)', 'execute'),
    'the 2-arg wrapper is executable by anon — link cards and web pages need it');
select ok(not has_function_privilege('authenticated', 'is_blocked(uuid,uuid)', 'execute'),
    'is_blocked is not executable by authenticated');
select ok(not has_function_privilege('authenticated', 'is_minor_user(uuid)', 'execute'),
    'is_minor_user is not executable by authenticated');
select ok(not has_function_privilege('authenticated', 'is_mutual_follow(uuid,uuid)', 'execute'),
    'is_mutual_follow is not executable by authenticated');

-- ---------------------------------------------------------------------------
-- is_minor: the conservative flip, and the no-profile-row default.
--
-- Drop out of `authenticated` first: is_minor_user is revoked from it on
-- purpose, so calling it here as a client role is denied — which is the revoke
-- working, not a bug. These assertions test the function's logic, and the
-- grant tests above already covered who may reach it.
-- ---------------------------------------------------------------------------
select set_config('role', 'postgres', true);
select ok(is_minor(to_char(current_date - interval '17 years', 'YYYY-MM')),
    'a 17-year-old is a minor');
select ok(not is_minor(to_char(current_date - interval '19 years', 'YYYY-MM')),
    'a 19-year-old is not');
-- born exactly 18 years ago this month: the birthday MIGHT not have happened
-- yet, so the conservative answer is still "minor" until the month turns.
select ok(is_minor(to_char(current_date - interval '18 years', 'YYYY-MM')),
    'exactly-18-this-month still reads as a minor — conservative by up to one month, deliberately');
select ok(is_minor_user('00000000-0000-0000-0000-00000000dead'),
    'a user with no profiles row is treated as a minor — default-deny on the age gate');

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
-- maya follows juli, juli follows maya, then maya blocks juli.
select test_as('00000000-0000-0000-0000-000000000001');
select lives_ok($$
    insert into follows (follower_id, followed_id)
    values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002')
$$, 'maya follows juli');
select test_as('00000000-0000-0000-0000-000000000002');
select lives_ok($$
    insert into follows (follower_id, followed_id)
    values ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001')
$$, 'juli follows maya back');

select test_as('00000000-0000-0000-0000-000000000001');
select lives_ok($$
    insert into blocks (user_id, blocked_id)
    values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002')
$$, 'maya blocks juli');

-- The trigger runs as definer, so it removes BOTH edges even though maya's own
-- RLS would only let her delete rows she is party to.
select is(
    (select count(*)::int from follows
      where (follower_id = '00000000-0000-0000-0000-000000000001'
             and followed_id = '00000000-0000-0000-0000-000000000002')
         or (follower_id = '00000000-0000-0000-0000-000000000002'
             and followed_id = '00000000-0000-0000-0000-000000000001')),
    0, 'blocking severed the follow edges in BOTH directions');

-- can_follow must actually GATE, not just permit. A user with no profiles row
-- reads as a minor (default-deny), and minors cannot be followed.
select test_as('00000000-0000-0000-0000-000000000002');
select throws_ok($$
    insert into follows (follower_id, followed_id)
    values ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000dead')
$$, '42501', 'new row violates row-level security policy for table "follows"',
    'nobody can follow a user who reads as a minor — can_follow gates, it does not merely permit');

select * from finish();
rollback;
