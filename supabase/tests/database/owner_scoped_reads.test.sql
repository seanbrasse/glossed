-- GLO-258 · what RLS does NOT do: make a read "mine".
--
-- Ten tables carry a PERMISSIVE `*_own` + public-read pair. Postgres OR's
-- policies for the same command, so an unfiltered `select` returns your rows
-- PLUS every row the public predicate admits. Two repositories have already
-- shipped that defect — `RoutinesRepository.mine()` (#376, fixed #387) and
-- `ShelfRepository.shelf()` / `.items()` (fixed with this file) — and both
-- carried a doc comment asserting RLS had scoped them.
--
-- `privacy_policy_shape.test.sql` proves no public policy hand-rolls its own
-- predicate. This file proves the consequence of those policies EXISTING: it
-- demonstrates the leak against a genuinely public owner, then demonstrates
-- that pinning `user_id` is what closes it. A client read that does not pin is
-- wrong even when a Swift suite is green, because a Swift suite cannot see a
-- policy.
--
-- **The fixture is made genuinely public FIRST, and the leak arm is asserted
-- before the clean arm.** An isolation test against private rows is a ceremony:
-- RLS alone would hide them, so it passes while proving nothing. That is how
-- #376's leak survived review.
--
-- `routines` is deliberately absent: its `cadence` column is NOT NULL with no
-- default and arrives in a migration still open at the time of writing, so an
-- insert here would pass on a local DB that is ahead of the repo and fail in
-- CI, which is exactly the drift §0 of the handoff warns about. Its predicate
-- is #387's and is covered where it was fixed.
--
-- All fixtures are created inside this transaction and rolled back — nothing
-- here depends on, or disturbs, seeded state.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

-- ── fixtures: one owner who has published everything, one viewer ────────────
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values
    ('05c07ed0-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'scoped-owner@test.local', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', ''),
    ('05c07ed0-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'scoped-viewer@test.local', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');

-- Both need a profiles row: `is_minor_user` returns TRUE for a user with no
-- profile, and a minor is invisible at every scope — which would make every
-- assertion below pass for the wrong reason.
insert into profiles (user_id, birth_year_month, domains) values
    ('05c07ed0-0000-0000-0000-000000000001', '1990-01', '{makeup}'),
    ('05c07ed0-0000-0000-0000-000000000002', '1991-02', '{makeup}');

insert into privacy_scopes (user_id, shelf, rankings) values
    ('05c07ed0-0000-0000-0000-000000000001', 'public', 'public');
-- routines and looks open on their rows since 0053; this fixture's inserts
-- below carry visibility where the scenario needs it.

insert into brands (id, name, normalized_name) values
    ('05c07ed0-0000-0000-0000-0000000000b1', 'scoped test brand', 'scoped test brand');
insert into categories (id, domain, slug, label) values
    ('05c07ed0-0000-0000-0000-0000000000c1', 'makeup', 'scoped-cat', 'scoped cat');
insert into products (id, brand_id, category_id, domain, name, normalized_name, scope) values
    ('05c07ed0-0000-0000-0000-0000000000d1', '05c07ed0-0000-0000-0000-0000000000b1',
     '05c07ed0-0000-0000-0000-0000000000c1', 'makeup', 'scoped product', 'scoped product', 'canonical');
insert into variants (id, product_id, kind) values
    ('05c07ed0-0000-0000-0000-0000000000e1', '05c07ed0-0000-0000-0000-0000000000d1', 'default');

insert into user_items (id, user_id, variant_id, status, client_id) values
    ('05c07ed0-0000-0000-0000-0000000000f1', '05c07ed0-0000-0000-0000-000000000001',
     '05c07ed0-0000-0000-0000-0000000000e1', 'own', '05c07ed0-0000-0000-0000-0000000000f1');
insert into collections (id, user_id, title, visibility) values
    ('05c07ed0-0000-0000-0000-0000000000a1', '05c07ed0-0000-0000-0000-000000000001',
     'the owner''s published kit', 'public');
insert into looks (id, user_id, caption, state, posted_at, visibility) values
    ('05c07ed0-0000-0000-0000-0000000000a2', '05c07ed0-0000-0000-0000-000000000001',
     'a published look', 'public', now(), 'public');

-- ── the same owner's ladder, routine, and look photo — the five child tables ─
--
-- GLO-258's remaining five: `rank_positions`, `routine_steps`, `collection_items`
-- (17–18, with `CollectionsRepository.items()`'s fix), `look_photos`,
-- `look_tags`. Every one of them carries the same `*_own` + public pair, keyed
-- through its parent's visibility. The rankings scope above is `public`, the
-- routine and look below are `public` on their own rows (0053).
insert into rank_positions (user_id, category_id, scope_key, user_item_id, position) values
    ('05c07ed0-0000-0000-0000-000000000001', '05c07ed0-0000-0000-0000-0000000000c1',
     'default', '05c07ed0-0000-0000-0000-0000000000f1', 1);
insert into routines (id, user_id, title, slot, cadence, visibility) values
    ('05c07ed0-0000-0000-0000-0000000000a4', '05c07ed0-0000-0000-0000-000000000001',
     'a public routine', 'am', 'daily', 'public');
insert into routine_steps (routine_id, user_item_id, position) values
    ('05c07ed0-0000-0000-0000-0000000000a4', '05c07ed0-0000-0000-0000-0000000000f1', 0);
insert into look_photos (id, look_id, r2_key, position) values
    ('05c07ed0-0000-0000-0000-0000000000a5', '05c07ed0-0000-0000-0000-0000000000a2',
     'looks/05c07ed0-0000-0000-0000-000000000001/scoped.jpg', 0);
insert into look_tags (id, look_photo_id, x, y) values
    ('05c07ed0-0000-0000-0000-0000000000a6', '05c07ed0-0000-0000-0000-0000000000a5', 0.5, 0.5);

-- ── a SECOND owner, private in every surface, with one public collection ───
--
-- Separate from the first on purpose. Assertions 17–18 are about bounded
-- disclosure — a public collection revealing its own members — and against an
-- owner whose shelf is already `public` they would pass through the shelf
-- scope instead and prove nothing about collections at all.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values
    ('05c07ed0-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'scoped-collector@test.local', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');
insert into profiles (user_id, birth_year_month, domains) values
    ('05c07ed0-0000-0000-0000-000000000003', '1989-03', '{makeup}');
-- every surface shut. The ONLY thing public about this user is the collection.
insert into privacy_scopes (user_id, shelf, rankings) values
    ('05c07ed0-0000-0000-0000-000000000003', 'only_you', 'only_you');
insert into user_items (id, user_id, variant_id, status, client_id) values
    ('05c07ed0-0000-0000-0000-0000000000f3', '05c07ed0-0000-0000-0000-000000000003',
     '05c07ed0-0000-0000-0000-0000000000e1', 'own', '05c07ed0-0000-0000-0000-0000000000f3');
insert into collections (id, user_id, title, visibility) values
    ('05c07ed0-0000-0000-0000-0000000000a3', '05c07ed0-0000-0000-0000-000000000003',
     'a public collection, a private shelf', 'public');
insert into collection_items (collection_id, user_item_id, position) values
    ('05c07ed0-0000-0000-0000-0000000000a3', '05c07ed0-0000-0000-0000-0000000000f3', 0);

-- ── the viewer. Not a follower, not blocked: a stranger with an account. ────
select test_as('05c07ed0-0000-0000-0000-000000000002');

-- 1–2. user_items. The leak arm first: if this ever goes red the fixture stopped
-- being public and every clean arm below became a ceremony.
select ok(exists(select 1 from user_items
                  where id = '05c07ed0-0000-0000-0000-0000000000f1'),
    'UNFILTERED read of user_items returns the owner''s row — RLS admits it, so RLS is not what scopes a mine() read');
select ok(not exists(select 1 from user_items
                      where id = '05c07ed0-0000-0000-0000-0000000000f1'
                        and user_id = (select auth.uid())),
    'the same read with user_id pinned returns nothing — the predicate is what makes mine() mine');

-- 3–4. user_shelf_items, the view the shelf and the profile's shelf tab draw.
-- `security_invoker`, so it inherits user_items' OR'd policies wholesale.
select ok(exists(select 1 from user_shelf_items
                  where user_item_id = '05c07ed0-0000-0000-0000-0000000000f1'),
    'UNFILTERED read of user_shelf_items returns the owner''s row — a security_invoker view inherits the leak, it does not close it');
select ok(not exists(select 1 from user_shelf_items
                      where user_item_id = '05c07ed0-0000-0000-0000-0000000000f1'
                        and user_id = (select auth.uid())),
    'user_shelf_items with user_id pinned returns nothing');

-- 5–6. collections.
select ok(exists(select 1 from collections
                  where id = '05c07ed0-0000-0000-0000-0000000000a1' and deleted_at is null),
    'UNFILTERED read of collections returns the owner''s public collection');
select ok(not exists(select 1 from collections
                      where id = '05c07ed0-0000-0000-0000-0000000000a1' and deleted_at is null
                        and user_id = (select auth.uid())),
    'collections with user_id pinned returns nothing');

-- 7–8. looks. Its public policy is named `looks_public_read`, so the `%_public`
-- filter in privacy_policy_shape.test.sql does not see it — the pair is real
-- regardless of what the policy is called, which is the point of testing the
-- behaviour rather than the name.
select ok(exists(select 1 from looks where id = '05c07ed0-0000-0000-0000-0000000000a2'),
    'UNFILTERED read of looks returns the owner''s published look');
select ok(not exists(select 1 from looks
                      where id = '05c07ed0-0000-0000-0000-0000000000a2'
                        and user_id = (select auth.uid())),
    'looks with user_id pinned returns nothing');

-- 9–10. rank_positions — the one of the five with its OWN user_id column, and
-- the one read that is still unpinned: `RankingRepository.positions()` filters
-- on `category_id` + `scope_key` only. Against a category where any public
-- ranker has a ladder, that read returns THEIR positions interleaved with
-- yours — two rows claiming position 1. `face_offs` is `read_own` only, so
-- `scored_face_offs` (security_invoker over it) does not share the defect.
select ok(exists(select 1 from rank_positions
                  where category_id = '05c07ed0-0000-0000-0000-0000000000c1'
                    and scope_key = 'default'),
    'UNFILTERED read of rank_positions by category returns the owner''s public ladder — the exact shape RankingRepository.positions() issues');
select ok(not exists(select 1 from rank_positions
                      where category_id = '05c07ed0-0000-0000-0000-0000000000c1'
                        and scope_key = 'default'
                        and user_id = (select auth.uid())),
    'rank_positions with user_id pinned returns nothing');

-- 11–16. The four child tables with NO user_id column: routine_steps,
-- look_photos, look_tags (collection_items is 9–10 of #430). Their `*_own`
-- policies reach the owner through the parent, and so must the read: the pin
-- is the PARENT id list, already scoped by `user_id`, which is what
-- `RoutinesRepository.mine()` and `LooksRepository.mine()` do. A read handed a
-- parent id from anywhere else inherits nothing.
select ok(exists(select 1 from routine_steps
                  where routine_id = '05c07ed0-0000-0000-0000-0000000000a4'),
    'UNFILTERED read of routine_steps by routine returns the owner''s public routine''s steps');
select ok(not exists(select 1 from routine_steps
                      where routine_id in (select id from routines
                                            where user_id = (select auth.uid()))),
    'routine_steps keyed to routines pinned on user_id returns nothing — the parent list is the scope');

select ok(exists(select 1 from look_photos
                  where look_id = '05c07ed0-0000-0000-0000-0000000000a2'),
    'UNFILTERED read of look_photos by look returns the owner''s public look''s photo');
select ok(not exists(select 1 from look_photos
                      where look_id in (select id from looks
                                         where user_id = (select auth.uid()))),
    'look_photos keyed to looks pinned on user_id returns nothing');

select ok(exists(select 1 from look_tags
                  where look_photo_id = '05c07ed0-0000-0000-0000-0000000000a5'),
    'UNFILTERED read of look_tags by photo returns the spot on the owner''s public photo');
select ok(not exists(select 1 from look_tags
                      where look_photo_id in (
                            select id from look_photos
                             where look_id in (select id from looks
                                                where user_id = (select auth.uid())))),
    'look_tags keyed through photos and looks pinned on user_id returns nothing');

-- 17–18. `collection_items` → `user_shelf_items`, the two-read shape
-- `CollectionsRepository.items()` uses. This one is subtler than the rest and
-- is why it survived: the owner's SHELF scope is `only_you` throughout, so
-- nothing here is leaking a shelf. `collection_items_public` admits the
-- membership rows of a PUBLIC collection, and `item_is_published()` then
-- admits exactly those items — 0021 calls that "the BOUNDED disclosure" and
-- means it.
--
-- The database is right. What was wrong was a comment claiming the second read
-- "answers only for YOUR shelf" because the view is `security_invoker`, which
-- is the inverse of what `security_invoker` does. `items()` is owner-side, so
-- it now pins `user_id` and the claim is enforced rather than asserted.
select ok(exists(select 1 from user_shelf_items
                  where user_item_id in (
                            select user_item_id from collection_items
                             where collection_id = '05c07ed0-0000-0000-0000-0000000000a3')),
    'the members of a PUBLIC collection are readable even though the owner''s shelf scope is only_you — bounded disclosure, working as designed');
select ok(not exists(select 1 from user_shelf_items
                      where user_id = (select auth.uid())
                        and user_item_id in (
                                select user_item_id from collection_items
                                 where collection_id = '05c07ed0-0000-0000-0000-0000000000a3')),
    'the same read with user_id pinned returns nothing — what makes items() owner-side (GLO-258)');

select * from finish();
rollback;
