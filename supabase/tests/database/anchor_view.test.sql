-- user_shade_anchor status filtering (0031). GLO-145 half 2.
--
-- The rule: a never-worn product is not shade evidence. The fit row is the
-- LOG and survives; the view is the EVIDENCE SURFACE and is what stops
-- counting it. Those two halves are asserted separately, because "it vanished
-- from the view" and "we destroyed the user's history" look identical if you
-- only check the view.
--
-- Assertions are scoped to fixture ids. The shared local database carries drive
-- state — including the original GLO-145 repro row — and absolute counts drift
-- under it.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set maya   '00000000-0000-0000-0000-000000000001'
\set juli   '00000000-0000-0000-0000-000000000002'
-- anchor = a foundation variant (is_anchor); plain = a blush (not).
-- psql \set takes the rest of the line VERBATIM, comment included, so these
-- annotations cannot ride on the same line as the value.
\set anchor '40000000-0000-0000-0000-000000000002'
\set plain  '40000000-0000-0000-0000-000000000004'
\set ui_a   '52000000-0000-0000-0000-0000000000a1'
\set ui_p   '52000000-0000-0000-0000-0000000000a2'

select test_as(:'maya');
insert into user_items (id, user_id, variant_id, status, client_id)
values (:'ui_a', :'maya', :'anchor', 'want_to_try', 'cccccccc-1000-0000-0000-0000000000a1');
insert into item_fits (user_id, user_item_id, fit) values (:'maya', :'ui_a', 'just_right');

-- ---------------------------------------------------------------------------
-- The bug, and its two halves.
-- ---------------------------------------------------------------------------

select is((select count(*)::int from user_shade_anchor
            where user_id = :'maya' and variant_id = :'anchor'), 0,
    'a want_to_try item with a fit is NOT anchor evidence — this is the whole of GLO-145');

select is((select count(*)::int from item_fits where user_item_id = :'ui_a'), 1,
    'and the fit row SURVIVES. The table is the log, the view is the evidence surface — GLO-145 answered this way because status is exactly the field a user flips by accident, and destroying true history to fix a display problem is the worse trade');

-- ---------------------------------------------------------------------------
-- Every worn status counts. Only want_to_try does not.
-- ---------------------------------------------------------------------------

update user_items set status = 'own' where id = :'ui_a';
select is((select count(*)::int from user_shade_anchor
            where user_id = :'maya' and variant_id = :'anchor'), 1,
    'promoting to own makes the SAME fit row count — nothing had to be re-entered');

update user_items set status = 'finished' where id = :'ui_a';
select is((select count(*)::int from user_shade_anchor
            where user_id = :'maya' and variant_id = :'anchor'), 1,
    'finished still counts: the shade was on their face, which is what makes it evidence');

update user_items set status = 'repurchased' where id = :'ui_a';
select is((select count(*)::int from user_shade_anchor
            where user_id = :'maya' and variant_id = :'anchor'), 1,
    'repurchased still counts, for the same reason');

-- The round trip. This is the case the app can actually produce.
update user_items set status = 'want_to_try' where id = :'ui_a';
select is((select count(*)::int from user_shade_anchor
            where user_id = :'maya' and variant_id = :'anchor'), 0,
    'moving BACK to want_to_try stops the evidence counting again');
select is((select count(*)::int from item_fits where user_item_id = :'ui_a'), 1,
    'and the fit row still survives the round trip — a mis-tap costs nothing');

-- ---------------------------------------------------------------------------
-- The filters that were already there, still there. 0031 replaced the whole
-- view definition, so these are regression cover, not new behaviour.
-- ---------------------------------------------------------------------------

update user_items set status = 'own' where id = :'ui_a';
update user_items set deleted_at = now() where id = :'ui_a';
select is((select count(*)::int from user_shade_anchor
            where user_id = :'maya' and variant_id = :'anchor'), 0,
    'a soft-deleted item is still excluded');
update user_items set deleted_at = null where id = :'ui_a';

insert into user_items (id, user_id, variant_id, status, client_id)
values (:'ui_p', :'maya', :'plain', 'own', 'cccccccc-1000-0000-0000-0000000000a2');
insert into item_fits (user_id, user_item_id, fit) values (:'maya', :'ui_p', 'just_right');
select is((select count(*)::int from user_shade_anchor
            where user_id = :'maya' and variant_id = :'plain'), 0,
    'a non-anchor category is still excluded — blush is not an anchor category, so a fit on it is not shade evidence');

-- ---------------------------------------------------------------------------
-- security_invoker. THE REGRESSION GUARD.
--
-- CREATE OR REPLACE VIEW does not inherit the original's options. Writing 0031
-- without restating `with (security_invoker = true)` silently reverted the view
-- to running as its OWNER, which bypasses RLS on user_items and exposes every
-- user's anchors to every other user. That happened while writing this
-- migration and was caught by shelf_isolation's cross-user assertion.
--
-- These two assert it directly rather than by consequence, so the next person
-- to replace this view is told what they broke instead of having to infer it
-- from an isolation failure three files away.
-- ---------------------------------------------------------------------------

select ok(
    (select reloptions from pg_class where relname = 'user_shade_anchor')
        @> array['security_invoker=true'],
    'the view is security_invoker — WITHOUT THIS IT RUNS AS ITS OWNER AND BYPASSES RLS. CREATE OR REPLACE VIEW does not carry the option over; any migration replacing this view must restate it.');

select test_as(:'juli');
select is((select count(*)::int from user_shade_anchor where user_id = :'maya'), 0,
    'and the consequence: another user reads none of maya''s anchors through the view');

-- ---------------------------------------------------------------------------
-- anchor_badge() inherits the rule instead of restating it.
-- ---------------------------------------------------------------------------

select test_as(:'maya');
update user_items set status = 'want_to_try' where id = :'ui_a';
-- anchor_badge is revoked from authenticated on purpose (0025): it is an
-- internal helper for public_profile, not a client-reachable function. Asserting
-- it therefore means stepping out of the impersonated role.
reset role;
-- NAME THE SHADE, do not assert null. anchor_badge returns one value for the
-- whole user, so `is null` silently depends on maya owning no other anchor
-- anywhere in the database — and the shared local DB grows those. Asserting
-- that THIS shade is not the badge tests the same property and cannot be
-- broken by an unrelated row (GLO-161).
select isnt(anchor_badge(:'maya'), 'fenty beauty 240',
    'anchor_badge ignores a want_to_try shade WITHOUT its own status filter — 0031 removed that workaround, so this passing proves the badge now inherits the view rather than duplicating it');

update user_items set status = 'own' where id = :'ui_a';
-- Newest fit wins (order by captured_at desc), so make this one newest rather
-- than assuming no other anchor exists.
update item_fits set captured_at = now() where user_item_id = :'ui_a';
select is(anchor_badge(:'maya'), 'fenty beauty 240',
    'and once it is owned, that same shade becomes the badge');

select finish();
rollback;
