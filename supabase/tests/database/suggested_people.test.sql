-- suggested_people() (0032). GLO-122, docs/tech/02 §3.5.
--
-- The function is SECURITY DEFINER, so RLS is not quietly doing half this work
-- — every exclusion is a WHERE clause and every one is knocked out on its own
-- from a fully-eligible baseline. A single "it returned nothing" test would
-- pass for eight different reasons here.
--
-- Fixtures use an anchor variant NEITHER user owns, so nothing depends on the
-- shared local database's drive state.
begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set maya    '00000000-0000-0000-0000-000000000001'
\set juli    '00000000-0000-0000-0000-000000000002'
\set shade   '40000000-0000-0000-0000-000000000001'
\set ui_maya '53000000-0000-0000-0000-0000000000b1'
\set ui_juli '53000000-0000-0000-0000-0000000000b2'

-- Both wear the same shade and agree it fits. That is the anchor reason.
insert into profiles (user_id, birth_year_month, domains, skin_type)
values (:'maya', '1998-04', '{makeup}', 'combo')
on conflict (user_id) do update set domains = '{makeup}', skin_type = 'combo', birth_year_month = '1998-04';
insert into profiles (user_id, birth_year_month, domains, skin_type)
values (:'juli', '1996-09', '{makeup}', 'combo')
on conflict (user_id) do update set domains = '{makeup}', skin_type = 'combo', birth_year_month = '1996-09';

insert into user_items (id, user_id, variant_id, status, client_id) values
    (:'ui_maya', :'maya', :'shade', 'own', 'bbbbbbbb-2000-0000-0000-0000000000b1'),
    (:'ui_juli', :'juli', :'shade', 'own', 'bbbbbbbb-2000-0000-0000-0000000000b2');
insert into item_fits (user_id, user_item_id, fit) values
    (:'maya', :'ui_maya', 'just_right'),
    (:'juli', :'ui_juli', 'just_right');

insert into handles (user_id, handle) values (:'maya', 'maya_k'), (:'juli', 'juli_r');
insert into privacy_scopes (user_id, discoverable) values (:'maya', true), (:'juli', true)
on conflict (user_id) do update set discoverable = true;
-- §3.4's opt-in, on for both. Without this there is no nameable reason at all.
insert into profile_badges (user_id, show_anchor, show_skin_type) values
    (:'maya', true, true), (:'juli', true, true);

-- ROLE DISCIPLINE, and it is load-bearing.
--
-- Every table this test mutates is owner-only under RLS: privacy_scopes,
-- blocks, mutes, follows, profile_badges. Mutating the CANDIDATE's rows while
-- impersonating the VIEWER updates zero rows and raises nothing — the first
-- draft of this file did exactly that and "not discoverable" appeared to fail
-- as a function bug when the setup had simply not happened. So fixtures run as
-- superuser and only the RPC calls run as maya.
create or replace function fixture() returns void language plpgsql as $$
begin perform set_config('role', 'postgres', true); end $$;

select test_as(:'maya');

-- ---------------------------------------------------------------------------
-- Baseline, and the contract of a row.
-- ---------------------------------------------------------------------------

select is((select count(*)::int from suggested_people() where user_id = :'juli'), 1,
    'BASELINE — someone who wears the same shade, agrees it fits, is discoverable and has opted in appears exactly once');

select is((select reason from suggested_people() where user_id = :'juli'),
    'wears fenty beauty 220',
    'the reason NAMES the shade — "one person with a reason", not a three-avatar grid');

select is((select reason_kind from suggested_people() where user_id = :'juli'), 'anchor',
    'and says which kind of reason it is, so the client never has to parse the sentence');

select ok((select n from suggested_people() where user_id = :'juli') is not null,
    'every row carries its n — the claim and its evidence arrive together (EvidenceLine)');

select ok((select bool_and(reason is not null and reason <> '') from suggested_people()),
    'NO ROW EVER CARRIES AN EMPTY REASON. Both reason branches inner-join onto their evidence, so a person with nothing to say about them produces no row rather than a blank card — enforced by the RPC, not by a client checking for nil');

-- ---------------------------------------------------------------------------
-- The six exclusions, one at a time.
-- ---------------------------------------------------------------------------

-- (1) yourself
select is((select count(*)::int from suggested_people() where user_id = :'maya'), 0,
    'EXCLUSION 1 — you are never suggested to yourself, even though you match yourself perfectly');

-- (2) not discoverable
select fixture();
update privacy_scopes set discoverable = false where user_id = :'juli';
select test_as(:'maya');
select is((select count(*)::int from suggested_people() where user_id = :'juli'), 0,
    'EXCLUSION 2 — a candidate who is not discoverable does not appear. Being visible is not the same as wanting to be surfaced (§1.3)');
select fixture();
update privacy_scopes set discoverable = true where user_id = :'juli';
select test_as(:'maya');

-- (3) already followed
select fixture();
insert into follows (follower_id, followed_id) values (:'maya', :'juli');
select test_as(:'maya');
select is((select count(*)::int from suggested_people() where user_id = :'juli'), 0,
    'EXCLUSION 3 — someone you already follow is not a suggestion');
select fixture();
delete from follows where follower_id = :'maya' and followed_id = :'juli';
select test_as(:'maya');

-- (4) muted
select fixture();
insert into mutes (user_id, muted_id) values (:'maya', :'juli');
select test_as(:'maya');
select is((select count(*)::int from suggested_people() where user_id = :'juli'), 0,
    'EXCLUSION 4 — a muted person is not suggested. Mute changes no visibility, but it does mean stop showing me this person');
select fixture();
delete from mutes where user_id = :'maya' and muted_id = :'juli';
select test_as(:'maya');

-- (5) blocked, BOTH directions, asserted separately
select fixture();
insert into blocks (user_id, blocked_id) values (:'maya', :'juli');
select test_as(:'maya');
select is((select count(*)::int from suggested_people() where user_id = :'juli'), 0,
    'EXCLUSION 5a — someone you blocked is not suggested');
select fixture();
delete from blocks where user_id = :'maya' and blocked_id = :'juli';
select test_as(:'maya');

select fixture();
insert into blocks (user_id, blocked_id) values (:'juli', :'maya');
select test_as(:'maya');
select is((select count(*)::int from suggested_people() where user_id = :'juli'), 0,
    'EXCLUSION 5b — and someone who blocked YOU is not suggested either. The blocked party must not be able to detect the block, so this refusal has to look like every other absence');
select fixture();
delete from blocks where user_id = :'juli' and blocked_id = :'maya';
select test_as(:'maya');

-- (6) minors. Never suggested, whatever else is true of them.
select fixture();
update profiles set birth_year_month = to_char(current_date - interval '15 years', 'YYYY-MM')
 where user_id = :'juli';
select test_as(:'maya');
select is((select count(*)::int from suggested_people() where user_id = :'juli'), 0,
    'EXCLUSION 6 — a minor is never suggested, even discoverable, badged and matching. Minors are private by construction');
select fixture();
update profiles set birth_year_month = '1996-09' where user_id = :'juli';
select test_as(:'maya');

select is((select count(*)::int from suggested_people() where user_id = :'juli'), 1,
    'RESTORED — with every exclusion undone the baseline returns, so each zero above was caused by the thing under test and not by the fixture quietly breaking');

-- ---------------------------------------------------------------------------
-- §3.4's opt-in. THIS RPC IS NOT A SECOND PATH.
--
-- "The badges are the only path by which skin_type, the anchor variant, and
-- hair_pattern reach another human" (§3.4). §3.5 as written would have been a
-- second path with no opt-in at all, publishing a stranger's shade to everyone.
-- ---------------------------------------------------------------------------

select fixture();
update profile_badges set show_anchor = false where user_id = :'juli';
select test_as(:'maya');
select is((select count(*)::int from suggested_people()
            where user_id = :'juli' and reason_kind = 'anchor'), 0,
    'a candidate who has NOT published their anchor gets no anchor reason — the suggestion card cannot publish what the profile would not');

select is((select reason_kind from suggested_people() where user_id = :'juli'), 'skin_type',
    'and falls back to the weaker skin-type reason, which they DID opt into');

-- Sean's ruling (GLO-167): consent AND non-disclosure, not one traded for the
-- other. The badge is why the row exists at all; this is why the sentence does
-- not quote their profile back at a stranger.
select is((select reason from suggested_people() where user_id = :'juli'),
    'similar skin to yours',
    'the skin reason says SIMILAR, never the value');

-- Runs as superuser: this joins `profiles`, and under maya's own RLS the
-- candidate's profile row is invisible, so the join would be empty and
-- bool_and would return null — an assertion that passes nothing and fails
-- confusingly. auth.uid() still reads the JWT claim, so the RPC still answers
-- as maya.
select fixture();
select ok(
    (select bool_and(position(pr.skin_type in sp.reason) = 0)
       from suggested_people() sp
       join profiles pr on pr.user_id = sp.user_id
      where pr.skin_type is not null),
    'NO reason string contains any candidate''s skin-type value. Asserted against the profile row rather than against the literal "combo", so re-interpolating skin_type into the sentence fails here whatever value a fixture happens to use');
select test_as(:'maya');

select fixture();
update profile_badges set show_skin_type = false where user_id = :'juli';
select test_as(:'maya');
select is((select count(*)::int from suggested_people() where user_id = :'juli'), 0,
    'with neither badge on there is no nameable reason, so there is no row at all — an opted-out person is not suggested rather than suggested anonymously');
select fixture();
update profile_badges set show_anchor = true, show_skin_type = true where user_id = :'juli';
select test_as(:'maya');

-- ---------------------------------------------------------------------------
-- The fit has to agree, not merely exist.
-- ---------------------------------------------------------------------------

select fixture();
update item_fits set fit = 'too_dark' where user_item_id = :'ui_juli';
select test_as(:'maya');
select is((select count(*)::int from suggested_people()
            where user_id = :'juli' and reason_kind = 'anchor'), 0,
    'two people who wear the same shade and DISAGREE about whether it fits are not evidence for each other — the anchor reason requires an agreeing fit');
select fixture();
update item_fits set fit = 'just_right' where user_item_id = :'ui_juli';
select test_as(:'maya');

-- A never-worn shade is not evidence. This is 0031 doing its job through the
-- view; the RPC deliberately does NOT re-filter status, so this assertion is
-- what proves the RPC inherits the fix rather than duplicating it.
select fixture();
update user_items set status = 'want_to_try' where id = :'ui_juli';
select test_as(:'maya');
select is((select count(*)::int from suggested_people()
            where user_id = :'juli' and reason_kind = 'anchor'), 0,
    'a candidate whose "anchor" is a never-worn product produces no anchor reason — the RPC inherits 0031 through the view instead of restating the filter');
select fixture();
update user_items set status = 'own' where id = :'ui_juli';
select test_as(:'maya');

-- ---------------------------------------------------------------------------
-- Reach, and the vocabulary rule.
-- ---------------------------------------------------------------------------

select ok(not has_function_privilege('anon', 'suggested_people(int)', 'execute'),
    'anon cannot call this — suggestions are about who YOU are, so there is no logged-out answer');
select ok(has_function_privilege('authenticated', 'suggested_people(int)', 'execute'),
    'authenticated can');

select ok(
    (select not bool_or(pg_get_functiondef(oid) ilike '%twin%')
       from pg_proc where proname = 'suggested_people'),
    'the word "twin" appears nowhere in the function — shade twins were removed in design review and the Phase-2 frame that still shows them is not the reference for this card');

select finish();
rollback;
