-- browse_routines() (0029). GLO-126, docs/tech/02 §4.
--
-- Each exclusion is asserted SEPARATELY. A single "it returns nothing" test
-- would pass for any of four different reasons, which is no test at all.
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set maya '00000000-0000-0000-0000-000000000001'
\set juli '00000000-0000-0000-0000-000000000002'
\set rid  '80000000-0000-0000-0000-0000000000a1'

select test_as(:'maya');
-- Upserts: the seed writes both profiles rows now (GLO-182).
insert into profiles (user_id, birth_year_month, domains, skin_type, hair_pattern)
values (:'maya', '1998-04', '{skincare}', 'combo', '3b')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month,
    domains = excluded.domains, skin_type = excluded.skin_type, hair_pattern = excluded.hair_pattern;
select claim_handle('maya_k');
-- browse_routines selects FROM privacy_scopes, so a user with no row is not a
-- candidate at all. Without this the later `update privacy_scopes` hits zero
-- rows and every positive assertion fails for the wrong reason.
insert into privacy_scopes (user_id) values (:'maya');
insert into routines (id, user_id, title, slot, started_on)
values (:'rid', :'maya', 'am routine', 'am', current_date);
insert into user_items (id, user_id, variant_id, status, client_id)
values ('50000000-0000-0000-0000-0000000000c1', :'maya', '40000000-0000-0000-0000-000000000002', 'own', 'eeeeeeee-0000-0000-0000-0000000000c1');
insert into routine_steps (routine_id, user_item_id, position)
values (:'rid', '50000000-0000-0000-0000-0000000000c1', 1);

select test_as(:'juli');
insert into profiles (user_id, birth_year_month, domains) values (:'juli', '1996-09', '{skincare}')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month, domains = excluded.domains;

-- ---------------------------------------------------------------------------
-- Each of the four exclusions, one at a time, from a fully-eligible baseline.
-- ---------------------------------------------------------------------------

-- (1) scope. Nothing published yet: routines defaults only_you.
select is((select count(*)::int from browse_routines('am')), 0,
    'EXCLUSION 1 — an only_you routine does not appear');

select test_as(:'maya');
update routines set visibility = 'public' where user_id = :'maya';
select test_as(:'juli');
select is((select count(*)::int from browse_routines('am')), 0,
    'EXCLUSION 2 — scope is public but the owner is not discoverable, so it still does not appear. Browse is a SURFACING surface, and surfacing is opt-in.');

select test_as(:'maya');
update privacy_scopes set discoverable = true where user_id = :'maya';
select test_as(:'juli');
select is((select count(*)::int from browse_routines('am')), 0,
    'EXCLUSION 3 — discoverable and public, but the TITLE is not approved, so the whole routine is hidden. Unmoderated text never leaks by appearing next to moderated rows.');

-- approve the title and it finally appears
select set_config('role', 'postgres', true);
insert into public_texts (user_id, kind, subject_id, body, state)
values (:'maya', 'routine_title', :'rid', 'am routine', 'approved');
select test_as(:'juli');
select is((select count(*)::int from browse_routines('am')), 1,
    'with scope + discoverable + an approved title, the routine appears');

-- (4) the block, from a fully-eligible baseline
select test_as(:'maya');
insert into blocks (user_id, blocked_id) values (:'maya', :'juli');
select test_as(:'juli');
select is((select count(*)::int from browse_routines('am')), 0,
    'EXCLUSION 4 — a block removes it even when everything else is satisfied');
select test_as(:'maya');
delete from blocks where user_id = :'maya' and blocked_id = :'juli';

-- ---------------------------------------------------------------------------
-- What the row carries
-- ---------------------------------------------------------------------------
select test_as(:'juli');
select is((select owner_handle from browse_routines('am')), 'maya_k',
    'the row carries the owner handle');
select is((select step_n from browse_routines('am')), 1,
    'and its step count');
-- Drift-proof: maya carries drive-drift rows in the shared local DB, so assert
-- the DELTA. Adding a want_to_try item must not move owner_shelf_n at all.
create temporary table _shelf_before on commit drop as
    select owner_shelf_n from browse_routines('am');
select set_config('role', 'postgres', true);
insert into user_items (id, user_id, variant_id, status, client_id)
values ('50000000-0000-0000-0000-0000000000c2', :'maya', '40000000-0000-0000-0000-000000000001',
        'want_to_try', 'eeeeeeee-0000-0000-0000-0000000000c2');
select test_as(:'juli');
select is(
    (select b2.owner_shelf_n - b1.owner_shelf_n from browse_routines('am') b2, _shelf_before b1),
    0,
    'adding a want_to_try item moves owner_shelf_n by ZERO — the n behind the claim counts owned things only');
select is((select title from browse_routines('am')), 'am routine',
    'the title comes from public_texts, not from routines.title');

-- The approved title is what renders, even when routines.title differs. That is
-- the render rule: the moderated copy is the source of truth for what is shown.
select set_config('role', 'postgres', true);
update routines set title = 'UNMODERATED EDIT' where id = :'rid';
select test_as(:'juli');
select is((select title from browse_routines('am')), 'am routine',
    'editing routines.title does NOT change what browse shows — only the approved public_texts body renders');

-- ---------------------------------------------------------------------------
-- Filters and slots
-- ---------------------------------------------------------------------------
select is((select count(*)::int from browse_routines('pm')), 0,
    'a different slot does not return the am routine');
select is((select count(*)::int from browse_routines('am', 'combo')), 1,
    'the skin-type filter matches');
select is((select count(*)::int from browse_routines('am', 'dry')), 0,
    'and excludes when it does not match');
select is((select count(*)::int from browse_routines('am', null, '3b')), 1,
    'the curl-pattern filter matches — wash-day browse needs it');
select is((select count(*)::int from browse_routines('am', null, '4c')), 0,
    'and excludes when it does not');

-- ---------------------------------------------------------------------------
-- Minors never surface, belt and braces: can_view refuses them AND the 0020
-- trigger locks discoverable false, so there is no state in which they appear.
-- ---------------------------------------------------------------------------
-- NOT throws_ok. With RLS on, an UPDATE against another user's row filters to
-- ZERO ROWS and succeeds silently — it does not raise. The honest property is
-- "nothing changed". (Fourth time I have reached for throws_ok here; the shape
-- of an RLS denial on UPDATE is silence, not an error.)
select set_config('role', 'postgres', true);
insert into privacy_scopes (user_id) values (:'juli');
select test_as(:'maya');
select lives_ok($$
    update privacy_scopes set discoverable = true
     where user_id = '00000000-0000-0000-0000-000000000002'
$$, 'flipping someone else''s discoverable flag runs without error — RLS filters it to zero rows');
select set_config('role', 'postgres', true);
select is((select discoverable from privacy_scopes where user_id = :'juli'), false,
    'and it changed NOTHING — juli is still not discoverable');

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
select ok(has_function_privilege('authenticated','browse_routines(routine_slot,text,text,int,timestamptz)','execute'),
    'browse_routines IS executable by authenticated');
select ok(not has_function_privilege('anon','browse_routines(routine_slot,text,text,int,timestamptz)','execute'),
    'but NOT by anon — the filters default from the viewer''s own profile, and an anonymous browse has no viewer');

select * from finish();
rollback;
