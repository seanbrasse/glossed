-- Grid C · blocks. GLO-118, docs/tech/02 §9.4.
--
-- The property under test: a block beats every scope, from either direction.
-- Every cell below the "no block" row is invisible.
begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set maya '00000000-0000-0000-0000-000000000001'
\set juli '00000000-0000-0000-0000-000000000002'

-- Both need profiles, or is_minor_user() reads them as minors and can_view
-- short-circuits on the minor lock — every assertion would pass for the wrong
-- reason. seed.sql has no profiles rows; this is not hypothetical.
select test_as(:'maya');
-- Upserts: the seed writes both profiles rows now (GLO-182).
insert into profiles (user_id, birth_year_month, domains) values (:'maya', '1998-04', '{makeup}')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month, domains = excluded.domains;
insert into privacy_scopes (user_id) values (:'maya');
select test_as(:'juli');
insert into profiles (user_id, birth_year_month, domains) values (:'juli', '1996-09', '{makeup}')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month, domains = excluded.domains;

-- Mutual follow, so the `friends` cells are reachable at all.
select test_as(:'maya');
insert into follows (follower_id, followed_id) values (:'maya', :'juli');
select test_as(:'juli');
insert into follows (follower_id, followed_id) values (:'juli', :'maya');

-- ---------------------------------------------------------------------------
-- Row 1: no block. The control — these are the only visible cells in the grid.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
update privacy_scopes set shelf = 'friends' where user_id = :'maya';
select test_as(:'juli');
select ok(can_view(:'maya', 'shelf'), 'no block · friends · mutual → visible');
select test_as(:'maya');
update privacy_scopes set shelf = 'public' where user_id = :'maya';
select test_as(:'juli');
select ok(can_view(:'maya', 'shelf'), 'no block · public · mutual → visible');

-- a non-mutual stranger at friends is invisible even with no block
select test_as('00000000-0000-0000-0000-00000000beef');
select ok(can_view(:'maya', 'shelf'),
    'no block · public · stranger → VISIBLE. The control: every invisible cell below fails because of the block, not the scope.');

-- ---------------------------------------------------------------------------
-- Row 2: owner → viewer. maya blocks juli.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
insert into blocks (user_id, blocked_id) values (:'maya', :'juli');
update privacy_scopes set shelf = 'friends' where user_id = :'maya';
select test_as(:'juli');
select ok(not can_view(:'maya', 'shelf'), 'owner→viewer block · friends · mutual → invisible');
select test_as(:'maya');
update privacy_scopes set shelf = 'public' where user_id = :'maya';
select test_as(:'juli');
select ok(not can_view(:'maya', 'shelf'),
    'owner→viewer block · PUBLIC · mutual → invisible — a block beats public');

-- and the reverse direction of the same block: maya looking at juli
select test_as(:'juli');
insert into privacy_scopes (user_id, shelf) values (:'juli', 'public');
select test_as(:'maya');
select ok(not can_view(:'juli', 'shelf'),
    'the BLOCKER also loses visibility — the block is symmetric in effect, not just in policy');

select test_as(:'maya');
delete from blocks where user_id = :'maya' and blocked_id = :'juli';

-- ---------------------------------------------------------------------------
-- Row 3: viewer → owner. juli blocks maya.
-- ---------------------------------------------------------------------------
select test_as(:'juli');
insert into blocks (user_id, blocked_id) values (:'juli', :'maya');
select test_as(:'maya');
update privacy_scopes set shelf = 'public' where user_id = :'maya';
select test_as(:'juli');
select ok(not can_view(:'maya', 'shelf'),
    'viewer→owner block · public → invisible; the direction of the block does not matter');
select test_as(:'maya');
select ok(not can_view(:'juli', 'shelf'),
    'viewer→owner block · the owner cannot see the blocker either');

-- ---------------------------------------------------------------------------
-- Row 4: both directions.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
insert into blocks (user_id, blocked_id) values (:'maya', :'juli');
select test_as(:'juli');
select ok(not can_view(:'maya', 'shelf'), 'blocks in BOTH directions · public → invisible');
select test_as(:'maya');
select ok(not can_view(:'juli', 'shelf'), 'blocks in BOTH directions · the other way too');

-- every surface, not just shelf
select test_as(:'maya');
update privacy_scopes set rankings = 'public', routines = 'public', looks = 'public' where user_id = :'maya';
select test_as(:'juli');
select ok(not can_view(:'maya', 'rankings'), 'a block covers rankings');
select ok(not can_view(:'maya', 'routines'), 'a block covers routines');
select ok(not can_view(:'maya', 'looks'),    'a block covers looks');

-- the owner still sees their own everything, block or not
select test_as(:'maya');
select ok(can_view(:'maya', 'shelf'),
    'the owner short-circuit runs BEFORE the block check — blocking someone does not blind you to yourself');

-- ---------------------------------------------------------------------------
-- Behavioural
-- ---------------------------------------------------------------------------
select test_as(:'juli');
delete from blocks where user_id = :'juli' and blocked_id = :'maya';
select test_as(:'maya');
delete from blocks where user_id = :'maya' and blocked_id = :'juli';

-- re-establish the mutual follow, then block and watch the trigger sever it
select test_as(:'maya');
insert into follows (follower_id, followed_id) values (:'maya', :'juli') on conflict do nothing;
select test_as(:'juli');
insert into follows (follower_id, followed_id) values (:'juli', :'maya') on conflict do nothing;
select is((select count(*)::int from follows
            where (follower_id = :'maya' and followed_id = :'juli')
               or (follower_id = :'juli' and followed_id = :'maya')), 2,
    'the mutual follow is in place before the block');

select test_as(:'maya');
insert into blocks (user_id, blocked_id) values (:'maya', :'juli');
select is((select count(*)::int from follows
            where (follower_id = :'maya' and followed_id = :'juli')
               or (follower_id = :'juli' and followed_id = :'maya')), 0,
    'inserting the block severed BOTH follow edges — a block that leaves an edge standing is a bug that reads as a feature');

-- the blocked party cannot read the blocks table
select test_as(:'juli');
select is((select count(*)::int from blocks where blocked_id = :'juli'), 0,
    'the blocked party cannot see the block — blocks has no read policy for blocked_id, on purpose');

-- re-following after a block is refused
select throws_ok($$
    insert into follows (follower_id, followed_id)
    values ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001')
$$, '42501', 'new row violates row-level security policy for table "follows"',
    'a blocked user cannot re-follow — can_follow() consults is_blocked in both directions');

-- and the blocker cannot follow them back either
select test_as(:'maya');
select throws_ok($$
    insert into follows (follower_id, followed_id)
    values ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002')
$$, '42501', 'new row violates row-level security policy for table "follows"',
    'the blocker cannot follow the blocked user either');

-- unblocking restores visibility but NOT the follow edges
select test_as(:'maya');
delete from blocks where user_id = :'maya' and blocked_id = :'juli';
select test_as(:'juli');
select ok(can_view(:'maya', 'shelf'),
    'unblocking restores visibility at public');
select is((select count(*)::int from follows
            where (follower_id = :'maya' and followed_id = :'juli')
               or (follower_id = :'juli' and followed_id = :'maya')), 0,
    'unblocking does NOT restore the follow edges — the relationship is gone, only the ability to see is back');

select * from finish();
rollback;
