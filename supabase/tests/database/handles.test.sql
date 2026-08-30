-- Handles, moderated public text, badge opt-ins (0023). GLO-120.
begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set maya '00000000-0000-0000-0000-000000000001'
\set juli '00000000-0000-0000-0000-000000000002'

-- maya is an adult; juli is a minor. Both need profiles or is_minor_user()
-- reads them BOTH as minors and half these assertions pass for the wrong reason.
-- Upserts, because the seed now writes both rows as adults (GLO-182) and this
-- suite's juli must be fifteen — the override is the point, so it is stated.
select test_as(:'maya');
insert into profiles (user_id, birth_year_month, domains) values (:'maya', '1998-04', '{makeup}')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month, domains = excluded.domains;
select test_as(:'juli');
insert into profiles (user_id, birth_year_month, domains)
values (:'juli', to_char(current_date - interval '15 years', 'YYYY-MM'), '{makeup}')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month, domains = excluded.domains;

-- ---------------------------------------------------------------------------
-- Claiming
-- ---------------------------------------------------------------------------
select test_as(:'maya');
select is(claim_handle('Maya_K'), 'maya_k', 'claim_handle lowercases and trims');
select is((select handle from handles where user_id = :'maya'), 'maya_k', 'the row landed lowercase');

-- A handle is an identifier, not moderated text (GLO-191). This assertion is
-- inverted rather than deleted: it used to require the `pending` row, and its
-- own message claimed "nothing renders it yet", which was never true —
-- public_profile selects h.handle unfiltered by state (GLO-187). Claiming now
-- writes no moderation record at all, and this fails if one comes back.
select is((select count(*)::int from public_texts where user_id = :'maya' and kind = 'handle'),
    0, 'claiming writes no moderation row — the handle is checked at claim time, not after');

-- Uniqueness is case-insensitive because storage is lowercase. This needs a
-- third ADULT: juli is a minor, so claim_handle refuses her on the minor gate
-- before it ever reaches the unique index, and the test would be measuring the
-- wrong refusal.
select set_config('role', 'postgres', true);
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values ('00000000-0000-0000-0000-0000000000ad', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'adult2@local.test', '', now(), '{}', '{}', now(), now(),
        '', '', '', '', '', '', '', '');
select test_as('00000000-0000-0000-0000-0000000000ad');
insert into profiles (user_id, birth_year_month, domains)
values ('00000000-0000-0000-0000-0000000000ad', '1990-01', '{makeup}');
select throws_ok($$ select claim_handle('MAYA_K') $$, '23505', null,
    'a differently-cased duplicate collides — the unique index does the race, not the availability check');

-- ---------------------------------------------------------------------------
-- Refusals, each distinguishable so the UI can say something useful
-- ---------------------------------------------------------------------------
select test_as(:'maya');
select throws_ok($$ select claim_handle('c') $$, '23514', null,
    'a reserved ROUTE is refused — /c/<slug> must not collide with @c');
select throws_ok($$ select claim_handle('glossed') $$, '23514', null,
    'a reserved SAFETY word is refused');

select set_config('role', 'postgres', true);
insert into brands (name, normalized_name) values ('Rhode', 'rhode') on conflict do nothing;
select test_as(:'maya');
select throws_ok($$ select claim_handle('rhode') $$, '23514', null,
    'a brand name is refused — impersonation checked against data we already have');

-- minors have no public identity to claim
select test_as(:'juli');
select throws_ok($$ select claim_handle('juli_b') $$, '23514', null,
    'a minor cannot claim a handle');

-- ---------------------------------------------------------------------------
-- handle_available answers only what a caller learns by trying
-- ---------------------------------------------------------------------------
select test_as(:'maya');
select ok(not handle_available('maya_k'), 'a taken handle is not available');
select ok(not handle_available('c'),      'a reserved route is not available');
select ok(not handle_available('rhode'),  'a brand name is not available');
select ok(not handle_available('a'),      'too short fails the shape check');
select ok(not handle_available('a..b'),   'a double dot fails the shape check');
select ok(handle_available('a_free_one'), 'a free, well-shaped handle is available');

-- ---------------------------------------------------------------------------
-- public_texts: the render-rule invariant
-- ---------------------------------------------------------------------------
-- 0045 (GLO-207, Sean Aug 30) changed WHEN a bio passes the gate, not what
-- the gate is. The two assertions below described the old timing — a bio
-- landing pending, and an edit returning it to pending — and are re-specified
-- rather than removed. The invariant further down, that approval cannot be
-- self-declared, is untouched, but it needed a new vehicle: it used to run
-- against the handle row, and 0047 (GLO-191) stops writing one. It now runs
-- against a `linked_social`, which is the remaining kind that genuinely lands
-- pending — testing it against a bio would be testing a gate that is already
-- open, which is no test at all.
select isnt(set_public_text('bio', null, 'tone 6 · combo'), null, 'set_public_text returns an id');
select is((select state::text from public_texts where user_id = :'maya' and kind = 'bio'),
    'approved', 'a bio lands approved while bios_auto_approve() is on — nothing reviews it, so pending would mean never rendering at all');

select test_as(:'maya');
select isnt(set_public_text('bio', null, 'edited'), null, 'the bio can be edited');
select is((select state::text from public_texts where user_id = :'maya' and kind = 'bio'),
    'approved', 'and an edit lands approved too — there is no review to re-enter while the switch is on');
select is((select body from public_texts where user_id = :'maya' and kind = 'bio'),
    'edited', 'and the new body is stored, so the reviewer sees what was written');
select is((select count(*)::int from public_texts where user_id = :'maya' and kind = 'bio'), 1,
    'one bio per user — nulls not distinct makes the unique constraint bite on a null subject_id');

-- The client cannot write this table AT ALL, which is what makes the RPC
-- mandatory rather than merely tidy (GLO-216). public_texts has a SELECT
-- policy and no insert policy, so a direct insert is refused — and the app
-- attempted exactly that for months, which meant no bio, and no moderation
-- record for any handle, collection or routine, could be written.
--
-- Asserted here so that a future "fix" which adds an insert policy fails
-- loudly: that policy would hand `state` back to the client and undo the
-- reason set_public_text exists.
select throws_ok(
    $$ insert into public_texts (user_id, kind, body, state)
       values ('00000000-0000-0000-0000-000000000001','bio','written directly','pending') $$,
    '42501',
    'new row violates row-level security policy for table "public_texts"',
    'a direct client insert is REFUSED — the RPC is the only door'
);

-- The client cannot self-approve. Note the SHAPE of this assertion: with RLS
-- enabled and NO update policy, the UPDATE filters to zero rows and succeeds
-- SILENTLY rather than raising — the shelf_isolation precedent. So the honest
-- property is not "it throws", it is "nothing changed". A throws_ok here would
-- have been a test that only passes when something else is wrong.
select isnt(set_public_text('linked_social', null, '@maya on instagram'), null,
    'a linked_social is written through the RPC and lands pending — bios_auto_approve() covers bios only');
select lives_ok($$ update public_texts set state = 'approved' where user_id = '00000000-0000-0000-0000-000000000001' $$,
    'the self-approve update runs without error — RLS filters it to zero rows rather than raising');
select is((select state::text from public_texts where user_id = :'maya' and kind = 'linked_social'),
    'pending', 'and it changed NOTHING — still pending, so approval cannot be self-declared');

-- ---------------------------------------------------------------------------
-- Isolation
-- ---------------------------------------------------------------------------
select test_as(:'juli');
select is((select count(*)::int from handles where user_id = :'maya'), 0,
    'juli cannot read maya''s handle row directly — the public path is GLO-121''s RPC');
select is((select count(*)::int from public_texts where user_id = :'maya'), 0,
    'juli cannot read maya''s text');
-- Before 0024 this was a count returning 0 (privilege held, RLS filtered it
-- away). After 0024 authenticated holds NO privilege, so it RAISES instead.
-- That is a strictly better failure mode — denied at the privilege layer rather
-- than the policy layer — and the assertion has to match reality, not the
-- reverse. Asserting a count here would now be asserting the weaker guarantee.
select throws_ok($$ select count(*) from reserved_handles $$, '42501', null,
    'reserved_handles is DENIED to clients at the privilege layer, not merely filtered by RLS — enumerating it is a gift to squatters');

-- ---------------------------------------------------------------------------
-- Badges default off. They are the only path Regulated data reaches a human.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
select lives_ok($$ insert into profile_badges (user_id) values ('00000000-0000-0000-0000-000000000001') $$,
    'a badge row can be created');
select results_eq($$ select show_skin_type, show_anchor, show_hair_pattern from profile_badges
                      where user_id = '00000000-0000-0000-0000-000000000001' $$,
    $$ values (false, false, false) $$,
    'all three badges default OFF — publishing Regulated data is an explicit act');

-- ---------------------------------------------------------------------------
-- Grants, both directions (the rule 0020/0022 taught)
-- ---------------------------------------------------------------------------
select ok(has_function_privilege('authenticated','claim_handle(text)','execute'),
    'claim_handle IS executable by authenticated');
select ok(not has_function_privilege('anon','claim_handle(text)','execute'),
    'claim_handle is NOT executable by anon');
select ok(not has_function_privilege('anon','set_public_text(public_text_kind,uuid,text)','execute'),
    'set_public_text is NOT executable by anon');
select ok(not has_function_privilege('anon','handle_available(text)','execute'),
    'handle_available is NOT executable by anon');

select * from finish();
rollback;
