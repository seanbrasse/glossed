-- Grids A + B · can_view() directly. GLO-117, docs/tech/02 §9.2, §9.3.
--
-- These test the FUNCTION, not the table policies — privacy_surfaces (GLO-116)
-- covers the policies. Testing can_view directly is what makes a failure
-- readable: a red cell here names the rule that broke, not the table.
begin;
create extension if not exists pgtap with schema extensions;
select plan(41);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set maya          '00000000-0000-0000-0000-000000000001'
\set juli          '00000000-0000-0000-0000-000000000002'
\set follower_only '00000000-0000-0000-0000-0000000000a1'
\set followed_only '00000000-0000-0000-0000-0000000000a2'
\set stranger      '00000000-0000-0000-0000-0000000000a3'

-- 0058: a public scope needs a handle, so the two seeded owners claim one here.
-- seed.sql gives them none on purpose (handles.test claims Maya_K), and a local
-- database may already hold one from a drive — hence on conflict. Directly, as
-- postgres: the fixture is not the app, and claim_handle is the app's door.
select set_config('role', 'postgres', true);
insert into handles (user_id, handle) values (:'maya', 'tstmaya0058'), (:'juli', 'tstjuli0058')
    on conflict (user_id) do nothing;

-- The extra three actors need auth.users rows. Inside this transaction only —
-- seed.sql stays untouched, so no db reset, which three sessions would feel.
select set_config('role', 'postgres', true);
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
select u.id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       u.id::text || '@local.test', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''
from (values (:'follower_only'::uuid), (:'followed_only'::uuid), (:'stranger'::uuid)) as u(id);

-- Everyone needs a profile: is_minor_user() is coalesce(..., true), so a user
-- without one reads as a minor and can_view short-circuits on the minor lock —
-- every cell below would pass for entirely the wrong reason.
-- Upsert: maya and juli are seeded with profiles rows now (GLO-182).
insert into profiles (user_id, birth_year_month, domains)
values (:'maya', '1998-04', '{makeup}'), (:'juli', '1996-09', '{makeup}'),
       (:'follower_only', '1995-01', '{makeup}'), (:'followed_only', '1994-02', '{makeup}'),
       (:'stranger', '1993-03', '{makeup}')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month, domains = excluded.domains;

-- The graph: juli is mutual; follower_only follows maya one way; maya follows
-- followed_only one way; stranger has no edges.
insert into follows (follower_id, followed_id) values
    (:'maya', :'juli'), (:'juli', :'maya'),
    (:'follower_only', :'maya'),
    (:'maya', :'followed_only');

-- ---------------------------------------------------------------------------
-- GRID A · scope × viewer relation, on `shelf`. 6 relations × 4 scopes = 24.
--
-- The `friends` row is the reason this grid exists: follower_only is NOT a
-- friend. If that cell ever flips to visible, `friends` has silently become a
-- slower spelling of `public`.
-- ---------------------------------------------------------------------------

-- (a) NO ROW at all. Absence must read as a no, not as a gap.
select set_config('role', 'postgres', true);
select ok(can_view(:'maya', :'maya', 'shelf'),          'no row · owner → visible');
select ok(not can_view(:'juli', :'maya', 'shelf'),      'no row · mutual → invisible');
select ok(not can_view(:'follower_only', :'maya', 'shelf'), 'no row · follower-only → invisible');
select ok(not can_view(:'followed_only', :'maya', 'shelf'), 'no row · followed-only → invisible');
select ok(not can_view(:'stranger', :'maya', 'shelf'),  'no row · stranger → invisible');
select ok(not can_view(null, :'maya', 'shelf'),         'no row · anon → invisible');

-- (b) only_you
insert into privacy_scopes (user_id) values (:'maya');
select ok(can_view(:'maya', :'maya', 'shelf'),          'only_you · owner → visible');
select ok(not can_view(:'juli', :'maya', 'shelf'),      'only_you · mutual → invisible');
select ok(not can_view(:'follower_only', :'maya', 'shelf'), 'only_you · follower-only → invisible');
select ok(not can_view(:'followed_only', :'maya', 'shelf'), 'only_you · followed-only → invisible');
select ok(not can_view(:'stranger', :'maya', 'shelf'),  'only_you · stranger → invisible');
select ok(not can_view(null, :'maya', 'shelf'),         'only_you · anon → invisible');

-- (c) friends — the row that matters
update privacy_scopes set shelf = 'friends' where user_id = :'maya';
select ok(can_view(:'maya', :'maya', 'shelf'),          'friends · owner → visible');
select ok(can_view(:'juli', :'maya', 'shelf'),          'friends · MUTUAL → visible');
select ok(not can_view(:'follower_only', :'maya', 'shelf'),
    'friends · FOLLOWER-ONLY → INVISIBLE. One-way follow buys nothing; if this flips, friends has become a slower public.');
select ok(not can_view(:'followed_only', :'maya', 'shelf'),
    'friends · FOLLOWED-ONLY → invisible. Being followed by the owner is not friendship either.');
select ok(not can_view(:'stranger', :'maya', 'shelf'),  'friends · stranger → invisible');
select ok(not can_view(null, :'maya', 'shelf'),         'friends · anon → invisible');

-- (d) public
update privacy_scopes set shelf = 'public' where user_id = :'maya';
select ok(can_view(:'maya', :'maya', 'shelf'),          'public · owner → visible');
select ok(can_view(:'juli', :'maya', 'shelf'),          'public · mutual → visible');
select ok(can_view(:'follower_only', :'maya', 'shelf'), 'public · follower-only → visible');
select ok(can_view(:'followed_only', :'maya', 'shelf'), 'public · followed-only → visible');
select ok(can_view(:'stranger', :'maya', 'shelf'),      'public · stranger → visible');
select ok(can_view(null, :'maya', 'shelf'),             'public · ANON → visible — link cards and web share pages depend on this');

-- ---------------------------------------------------------------------------
-- GRID B · the surface switch. 4 surfaces × 2 scopes × 2 viewers = 16.
--
-- Two properties: the surfaces are INDEPENDENT (setting one does not move
-- another), and `looks` behaves like the rest even though nothing reads it in
-- 1.5 — so Phase 2 inherits a tested column rather than a new one.
-- ---------------------------------------------------------------------------
update privacy_scopes set shelf = 'only_you', rankings = 'only_you' where user_id = :'maya';

update privacy_scopes set shelf = 'friends' where user_id = :'maya';
select ok(can_view(:'juli', :'maya', 'shelf'),          'friends · shelf · mutual → visible');
select ok(not can_view(:'stranger', :'maya', 'shelf'),  'friends · shelf · stranger → invisible');
select ok(not can_view(:'juli', :'maya', 'rankings'),
    'setting shelf did NOT move rankings — the surfaces are independent');

update privacy_scopes set rankings = 'friends' where user_id = :'maya';
select ok(can_view(:'juli', :'maya', 'rankings'),       'friends · rankings · mutual → visible');
select ok(not can_view(:'stranger', :'maya', 'rankings'), 'friends · rankings · stranger → invisible');

-- routines and looks are PER ITEM since 0053. The surface arms fail closed
-- for every viewer — an old caller can never open something — and the same
-- friends/stranger behavior now lives in can_view_item, seat-based.
select ok(not can_view(:'juli', :'maya', 'routines'),
    'the routines surface arm fails CLOSED — even for a mutual (0053)');
select ok(not can_view(:'juli', :'maya', 'looks'),
    'the looks surface arm fails CLOSED — even for a mutual (0053)');
select test_as(:'juli');
select ok(can_view_item(:'maya', 'friends'),  'can_view_item · friends · mutual → visible');
select test_as(:'stranger');
select ok(not can_view_item(:'maya', 'friends'), 'can_view_item · friends · stranger → invisible');
reset role;

update privacy_scopes set shelf = 'public', rankings = 'public' where user_id = :'maya';
select ok(can_view(:'stranger', :'maya', 'shelf'),      'public · shelf · stranger → visible');
select ok(can_view(:'stranger', :'maya', 'rankings'),   'public · rankings · stranger → visible');
select test_as(:'stranger');
select ok(can_view_item(:'maya', 'public'),   'can_view_item · public · stranger → visible');
select ok(not can_view_item(:'maya', 'only_you'), 'can_view_item · only_you · stranger → invisible');
reset role;
select ok(can_view(:'juli', :'maya', 'shelf'),          'public · shelf · mutual → visible');
select ok(can_view(:'juli', :'maya', 'rankings'),       'public · rankings · mutual → visible');
select test_as(:'juli');
select ok(can_view_item(:'maya', 'public'),   'can_view_item · public · mutual → visible');
select ok(can_view_item(:'maya', 'only_you') = false, 'can_view_item · only_you · mutual → invisible — friends is not a skeleton key');
reset role;

select * from finish();
rollback;
