-- Grid E · the six real tables through their public policies (0021). GLO-116.
-- docs/tech/02 §9.6.
--
-- Fixtures live INSIDE this transaction. seed.sql is not touched: a seed change
-- means a db reset, and three sessions share this database.
begin;
create extension if not exists pgtap with schema extensions;
select plan(29);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- maya = owner, juli = the viewer we move around the grid.
\set maya '00000000-0000-0000-0000-000000000001'
\set juli '00000000-0000-0000-0000-000000000002'

-- 0058: a public scope needs a handle, so the two seeded owners claim one here.
-- seed.sql gives them none on purpose (handles.test claims Maya_K), and a local
-- database may already hold one from a drive — hence on conflict. Directly, as
-- postgres: the fixture is not the app, and claim_handle is the app's door.
select set_config('role', 'postgres', true);
insert into handles (user_id, handle) values (:'maya', 'tstmaya0058'), (:'juli', 'tstjuli0058')
    on conflict (user_id) do nothing;

-- Both need profiles or is_minor_user() reads them as minors (coalesce(...,true))
-- and can_view short-circuits on the minor lock — which would make every
-- assertion below pass for the wrong reason.
select test_as(:'maya');
-- Upserts: the seed writes both profiles rows now (GLO-182).
insert into profiles (user_id, birth_year_month, domains) values (:'maya', '1998-04', '{makeup}')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month, domains = excluded.domains;
insert into privacy_scopes (user_id) values (:'maya');
select test_as(:'juli');
insert into profiles (user_id, birth_year_month, domains) values (:'juli', '1996-09', '{makeup}')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month, domains = excluded.domains;

-- maya owns one shelf item (own) and one wishlist item (want_to_try).
select test_as(:'maya');
insert into user_items (id, user_id, variant_id, status, client_id) values
    ('50000000-0000-0000-0000-0000000000e1', :'maya', '40000000-0000-0000-0000-000000000002', 'own',         'bbbbbbbb-0000-0000-0000-0000000000e1'),
    ('50000000-0000-0000-0000-0000000000e2', :'maya', '40000000-0000-0000-0000-000000000001', 'want_to_try', 'bbbbbbbb-0000-0000-0000-0000000000e2');

-- ---------------------------------------------------------------------------
-- Default: only_you. Nothing of maya's is visible to juli.
-- ---------------------------------------------------------------------------
select test_as(:'juli');
select is((select count(*)::int from user_items where id in ('50000000-0000-0000-0000-0000000000e1','50000000-0000-0000-0000-0000000000e2')), 0, 'shelf invisible at only_you');
select is((select count(*)::int from rank_positions where user_id = :'maya'), 0, 'rankings invisible at only_you');
select is((select count(*)::int from routines where user_id = :'maya' and title = 'am routine'), 0, 'routines invisible at only_you');
select is((select count(*)::int from collections where user_id = :'maya' and title = 'holy grails'), 0, 'collections invisible at only_you');

-- ---------------------------------------------------------------------------
-- shelf = public. The owned item appears; the wishlist item never does.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
update privacy_scopes set shelf = 'public' where user_id = :'maya';
select test_as(:'juli');
select is((select count(*)::int from user_items where id in ('50000000-0000-0000-0000-0000000000e1','50000000-0000-0000-0000-0000000000e2')), 1,
    'at shelf=public a stranger sees exactly the owned item, not the wishlist one');
select ok(not exists(select 1 from user_items where id = '50000000-0000-0000-0000-0000000000e2'),
    'want_to_try is NEVER published, even at shelf=public (Sean, Aug 29 — for now)');

-- soft-deleted rows never surface
select test_as(:'maya');
update user_items set deleted_at = now() where id = '50000000-0000-0000-0000-0000000000e1';
select test_as(:'juli');
select is((select count(*)::int from user_items where id = '50000000-0000-0000-0000-0000000000e1'), 0,
    'a soft-deleted item is invisible even at shelf=public');
select test_as(:'maya');
update user_items set deleted_at = null where id = '50000000-0000-0000-0000-0000000000e1';

-- ---------------------------------------------------------------------------
-- friends: mutual only. A one-way follow buys nothing.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
update privacy_scopes set shelf = 'friends' where user_id = :'maya';
select test_as(:'juli');
insert into follows (follower_id, followed_id) values (:'juli', :'maya');
select is((select count(*)::int from user_items where id = '50000000-0000-0000-0000-0000000000e1'), 0,
    'a ONE-WAY follower sees nothing at friends — this is the cell that proves friends is not a slower public');
select test_as(:'maya');
insert into follows (follower_id, followed_id) values (:'maya', :'juli');
select test_as(:'juli');
select is((select count(*)::int from user_items where id = '50000000-0000-0000-0000-0000000000e1'), 1,
    'a MUTUAL follower sees the shelf at friends');

-- ---------------------------------------------------------------------------
-- Blocks beat everything, from either direction.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
update privacy_scopes set shelf = 'public' where user_id = :'maya';
insert into blocks (user_id, blocked_id) values (:'maya', :'juli');
select test_as(:'juli');
select is((select count(*)::int from user_items where id = '50000000-0000-0000-0000-0000000000e1'), 0,
    'a blocked viewer sees nothing even at shelf=public — a block beats public');
select test_as(:'maya');
delete from blocks where user_id = :'maya' and blocked_id = :'juli';
select test_as(:'juli');
insert into blocks (user_id, blocked_id) values (:'juli', :'maya');
select is((select count(*)::int from user_items where id = '50000000-0000-0000-0000-0000000000e1'), 0,
    'the BLOCKER also loses visibility — the block is symmetric in effect');
select test_as(:'juli');
delete from blocks where user_id = :'juli' and blocked_id = :'maya';

-- ---------------------------------------------------------------------------
-- Bounded disclosure: an item not on a public shelf still surfaces when it is
-- in a published routine, list, or collection — and ONLY that item.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
update privacy_scopes set shelf = 'only_you' where user_id = :'maya';
insert into routines (id, user_id, title, slot, visibility) values
    ('60000000-0000-0000-0000-0000000000f1'::uuid, :'maya', 'am routine', 'am', 'public');
insert into routine_steps (routine_id, user_item_id, position) values
    ('60000000-0000-0000-0000-0000000000f1'::uuid, '50000000-0000-0000-0000-0000000000e1', 1);
select test_as(:'juli');
select is((select count(*)::int from routines where id = '60000000-0000-0000-0000-0000000000f1'::uuid), 1,
    'a public routine is visible');
select is((select count(*)::int from user_items where id = '50000000-0000-0000-0000-0000000000e1'), 1,
    'an item in a published routine surfaces even though the shelf is only_you — bounded disclosure');
select is((select count(*)::int from routine_steps where routine_id = '60000000-0000-0000-0000-0000000000f1'::uuid), 1,
    'the routine steps come with it');

-- ---------------------------------------------------------------------------
-- Collections publish per collection, not under a profile-level scope.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
insert into collections (id, user_id, title) values
    ('70000000-0000-0000-0000-0000000000c1'::uuid, :'maya', 'holy grails');
insert into collection_items (collection_id, user_item_id, position) values
    ('70000000-0000-0000-0000-0000000000c1'::uuid, '50000000-0000-0000-0000-0000000000e2', 1);
select test_as(:'juli');
select is((select count(*)::int from collections where id = '70000000-0000-0000-0000-0000000000c1'::uuid), 0,
    'a collection defaults to only_you and is invisible');
select test_as(:'maya');
update collections set visibility = 'public' where id = '70000000-0000-0000-0000-0000000000c1'::uuid;
select test_as(:'juli');
select is((select count(*)::int from collections where id = '70000000-0000-0000-0000-0000000000c1'::uuid), 1,
    'publishing ONE collection makes it visible while the shelf stays only_you');
select is((select count(*)::int from collection_items where collection_id = '70000000-0000-0000-0000-0000000000c1'::uuid), 1,
    'its items come with it');

-- ---------------------------------------------------------------------------
-- The tables that get NO public policy, in any scope, ever.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
update privacy_scopes set shelf = 'public', rankings = 'public' where user_id = :'maya';
update routines set visibility = 'public' where user_id = :'maya';
insert into item_fits (user_id, user_item_id, fit) values (:'maya', '50000000-0000-0000-0000-0000000000e1', 'just_right');
select test_as(:'juli');
select is((select count(*)::int from item_fits where user_item_id = '50000000-0000-0000-0000-0000000000e1'), 0,
    'item_fits is invisible at every scope — fit is Regulated');
select is((select count(*)::int from item_chips where user_id = :'maya'), 0,
    'item_chips is invisible at every scope');
select is((select count(*)::int from face_offs where user_id = :'maya'), 0,
    'face_offs is invisible at every scope — the pairwise history reveals more than the order');
select is((select count(*)::int from profiles where user_id = :'maya'), 0,
    'profiles never relaxes — the public profile is an RPC projection, not a policy');

-- ---------------------------------------------------------------------------
-- events_no_regulated_props
-- ---------------------------------------------------------------------------
select set_config('role', 'postgres', true);
select throws_ok($$
    insert into events (client_id, name, props, ts)
    values (gen_random_uuid(), 'x', '{"tone_band": 6}', now())
$$, '23514', null, 'tone_band is rejected');
select throws_ok($$
    insert into events (client_id, name, props, ts)
    values (gen_random_uuid(), 'x', '{"skin_type": "combo"}', now())
$$, '23514', null, 'skin_type is rejected');
select throws_ok($$
    insert into events (client_id, name, props, ts)
    values (gen_random_uuid(), 'x', '{"hair_pattern": "3b"}', now())
$$, '23514', null, 'hair_pattern is rejected');
select throws_ok($$
    insert into events (client_id, name, props, ts)
    values (gen_random_uuid(), 'x', '{"bio": "hi"}', now())
$$, '23514', null, 'bio is rejected');
select throws_ok($$
    insert into events (client_id, name, props, ts)
    values (gen_random_uuid(), 'x', '{"display_name": "maya"}', now())
$$, '23514', null, 'display_name is rejected');

-- The assertion that stops the ban list creeping back over Phase 1's own
-- events: Event.swift already declares these two and nothing calls them yet.
select lives_ok($$
    insert into events (client_id, name, props, ts)
    values (gen_random_uuid(), 'fit_captured', '{"fits": "just_right"}', now())
$$, 'fits is ACCEPTED — fit_captured already declares it and the boundary is egress, not our own Postgres');
select lives_ok($$
    insert into events (client_id, name, props, ts)
    values (gen_random_uuid(), 'onb_anchor_captured', '{"fit": "too_light"}', now())
$$, 'fit is ACCEPTED — same reason; banning it would fail later inside a Phase-1 ticket');

-- Identifiers remain the allowed currency.
select lives_ok($$
    insert into events (client_id, name, props, ts)
    values (gen_random_uuid(), 'item_logged', '{"variant_id": "40000000-0000-0000-0000-000000000002"}', now())
$$, 'identifiers are allowed — variant_id rides freely');

select * from finish();
rollback;
