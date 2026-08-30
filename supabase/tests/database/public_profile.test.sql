-- Grid F · public_profile() and the badge opt-ins (0025). GLO-121.
-- docs/tech/02 §9.7.
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set maya '00000000-0000-0000-0000-000000000001'
\set juli '00000000-0000-0000-0000-000000000002'
\set kid  '00000000-0000-0000-0000-0000000000c1'

select set_config('role', 'postgres', true);
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values (:'kid', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'kid@local.test', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');

-- maya publishes; juli is the viewer; kid is a minor who also claims a handle
-- (by writing past claim_handle, since that function correctly refuses minors —
-- the point is to prove the READ path refuses too, not just the write path).
select test_as(:'maya');
-- Upserts: the seed writes both profiles rows now (GLO-182).
insert into profiles (user_id, birth_year_month, domains, skin_type, hair_pattern, display_name, avatar_seed)
values (:'maya', '1998-04', '{makeup}', 'combo', '3b', 'maya k.', 'seed-maya')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month,
    domains = excluded.domains, skin_type = excluded.skin_type, hair_pattern = excluded.hair_pattern,
    display_name = excluded.display_name, avatar_seed = excluded.avatar_seed;
select test_as(:'juli');
insert into profiles (user_id, birth_year_month, domains) values (:'juli', '1996-09', '{makeup}')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month, domains = excluded.domains;
select set_config('role', 'postgres', true);
insert into profiles (user_id, birth_year_month, domains)
values (:'kid', to_char(current_date - interval '15 years', 'YYYY-MM'), '{makeup}');
insert into handles (user_id, handle) values (:'kid', 'kid_h');

select test_as(:'maya');
select claim_handle('maya_k');

-- ---------------------------------------------------------------------------
-- The three zero-row cases, which must be INDISTINGUISHABLE.
-- ---------------------------------------------------------------------------
select test_as(:'juli');
select is((select count(*)::int from public_profile('nobody_here')), 0,
    'an UNCLAIMED handle returns zero rows');
select is((select count(*)::int from public_profile('kid_h')), 0,
    'a MINOR owner returns zero rows — the read path refuses even though a handle row exists');

select test_as(:'maya');
insert into blocks (user_id, blocked_id) values (:'maya', :'juli');
select test_as(:'juli');
select is((select count(*)::int from public_profile('maya_k')), 0,
    'a BLOCKED viewer returns zero rows — identical to not-found, so there is no private-account oracle');
select test_as(:'maya');
delete from blocks where user_id = :'maya' and blocked_id = :'juli';

-- and the reverse block direction
select test_as(:'juli');
insert into blocks (user_id, blocked_id) values (:'juli', :'maya');
select is((select count(*)::int from public_profile('maya_k')), 0,
    'blocking the OWNER also returns zero rows — the direction does not matter');
delete from blocks where user_id = :'juli' and blocked_id = :'maya';

-- ---------------------------------------------------------------------------
-- The happy path, and what it does NOT carry.
-- ---------------------------------------------------------------------------
select is((select count(*)::int from public_profile('maya_k')), 1,
    'a claimed adult handle returns one row');
select is((select display_name from public_profile('maya_k')), 'maya k.',
    'display_name renders');
select is((select handle from public_profile('MAYA_K')), 'maya_k',
    'lookup is case-insensitive — the handle is stored and returned lowercase');

-- Regulated fields must be absent from the RETURN TYPE, not merely null.
select is(
    (select count(*)::int from information_schema.routines r
       join information_schema.parameters p on p.specific_name = r.specific_name
      where r.routine_name = 'public_profile'
        and p.parameter_name in ('birth_year_month','tone_band','phone','skin_type','hair_pattern')),
    0,
    'the return type carries no birth_year_month, tone_band, phone, or raw skin_type/hair_pattern columns');

-- ---------------------------------------------------------------------------
-- Badges: off by default, and each appears only when its own flag is on.
-- ---------------------------------------------------------------------------
select is((select badge_skin_type from public_profile('maya_k')), null,
    'no badge row means no skin-type badge');
select test_as(:'maya');
insert into profile_badges (user_id) values (:'maya');
select test_as(:'juli');
select is((select badge_skin_type from public_profile('maya_k')), null,
    'a badge row with the flag OFF still shows nothing — the default is off');
select is((select badge_hair_pattern from public_profile('maya_k')), null,
    'hair pattern likewise');

-- 0044, GLO-205 (Sean, Aug 30): the opt-in no longer publishes the VALUE.
-- The assertion below used to read 'combo'. That was the specification until
-- Sean ruled that a badge never names a body fact, so it is re-specified here
-- rather than deleted to keep a suite green — the behaviour it described is
-- the behaviour that was overruled.
--
-- A badge is now a match between two people, so every case below turns on who
-- is LOOKING, not on the flag alone.
select test_as(:'maya');
update profile_badges set show_skin_type = true where user_id = :'maya';

-- juli's fixture profile carries no skin_type at all.
select test_as(:'juli');
select is((select badge_skin_type from public_profile('maya_k')), null,
    'the flag is ON, but a viewer with no skin type of their own is told nothing — there is no match to report');

select test_as(:'juli');
update profiles set skin_type = 'combo' where user_id = :'juli';
select is((select badge_skin_type from public_profile('maya_k')), 'similar skin to yours',
    'a viewer whose own skin type matches is told THAT it matches, never what it is');
select is((select badge_hair_pattern from public_profile('maya_k')), null,
    'and only that one — the flags stay independent');

select test_as(:'juli');
update profiles set skin_type = 'oily' where user_id = :'juli';
select is((select badge_skin_type from public_profile('maya_k')), null,
    'a viewer who does NOT match sees nothing — silence is what stops the badge being a value in disguise');

-- The case that keeps StrangerPreview (GLO-190) honest. It builds "what a
-- stranger sees" from public_profile called on YOURSELF, so an owner who
-- trivially matches themselves would put a badge on that screen that no
-- stranger can see — the exact lie it exists to catch.
select test_as(:'maya');
select is((select badge_skin_type from public_profile('maya_k')), null,
    'the OWNER sees no badge on their own profile — you cannot be similar to yourself, and the stranger preview reads this call');

select test_as(:'maya');
update profile_badges set show_hair_pattern = true where user_id = :'maya';
select test_as(:'juli');
update profiles set hair_pattern = '3b' where user_id = :'juli';
select is((select badge_hair_pattern from public_profile('maya_k')), 'similar hair to yours',
    'hair pattern behaves identically — one rule for both body facts, which is what the ruling asked for');

-- Anonymous: no uid, so no profile, so no match, so nothing. This is the
-- viewer a public profile is most exposed to.
select set_config('request.jwt.claims', null, true);
select set_config('role', 'anon', true);
select is((select badge_hair_pattern from public_profile('maya_k')), null,
    'a SIGNED-OUT viewer is told no body fact at all');
select isnt((select handle from public_profile('maya_k')), null,
    'the profile itself still resolves for them — the badges went quiet, the profile did not');

-- ---------------------------------------------------------------------------
-- The bio: only approved text ever renders.
-- ---------------------------------------------------------------------------
-- 0045, GLO-207 (Sean, Aug 30): bios are approved on write while the cohort
-- is the beta. The two assertions below used to prove the opposite — that a
-- freshly written bio does NOT render, and that editing one takes it back to
-- pending. Both described the behaviour Sean has now changed, so they are
-- re-specified rather than dropped.
--
-- The rule that did NOT change is the one still asserted here: public_profile
-- renders `approved` and nothing else. What moved is when a bio becomes
-- approved, not what the reader trusts.
select test_as(:'maya');
select set_public_text('bio', null, 'tone 6 · combo');
select test_as(:'juli');
select is((select bio from public_profile('maya_k')), 'tone 6 · combo',
    'a bio renders as soon as it is written — nothing reviews it, so a pending bio would never render at all');

select test_as(:'maya');
select set_public_text('bio', null, 'edited while nobody is reviewing');
select test_as(:'juli');
select is((select bio from public_profile('maya_k')), 'edited while nobody is reviewing',
    'and an edit lands the same way — 0023''s "an edit re-enters review, always" is no longer true while there is no review to re-enter');

-- The gate itself is untouched: only the trigger for passing it moved.
select set_config('role', 'postgres', true);
update public_texts set state = 'pending' where user_id = :'maya' and kind = 'bio';
select test_as(:'juli');
select is((select bio from public_profile('maya_k')), null,
    'a bio that is pending for any reason still does not render — the reader trusts state, not the writer');

-- ---------------------------------------------------------------------------
-- Counts: the n behind every claim.
-- ---------------------------------------------------------------------------
-- shelf_n counts the WHOLE user, so it cannot be scoped to fixture ids the way
-- grid E's assertions are — and the shared local DB carries drive-drift rows
-- (HANDOFF §2). Assert the DELTA instead: adding one `own` and one
-- `want_to_try` must move the count by exactly one. That is drift-proof and it
-- tests the actual property rather than a number that depends on DB history.
select test_as(:'juli');
create temporary table _before on commit drop as select shelf_n from public_profile('maya_k');

select test_as(:'maya');
insert into user_items (id, user_id, variant_id, status, client_id) values
    ('50000000-0000-0000-0000-0000000000f1', :'maya', '40000000-0000-0000-0000-000000000002', 'own',         'cccccccc-0000-0000-0000-0000000000f1'),
    ('50000000-0000-0000-0000-0000000000f2', :'maya', '40000000-0000-0000-0000-000000000001', 'want_to_try', 'cccccccc-0000-0000-0000-0000000000f2');
select test_as(:'juli');
select is(
    (select p.shelf_n - b.shelf_n from public_profile('maya_k') p, _before b),
    1,
    'adding one own + one want_to_try moved shelf_n by exactly ONE — want_to_try is excluded, the same rule that keeps it unpublished');

-- Anti-scraping: the point is not that juli cannot see an edge she is PART OF
-- (follows_read_own deliberately shows you your own edges). It is that she
-- cannot see edges she is not party to. So a third party follows maya too.
select test_as(:'juli');
insert into follows (follower_id, followed_id) values (:'juli', :'maya');
select test_as(:'kid');
select set_config('role', 'postgres', true);
-- kid is a minor so can_follow refuses; insert directly to create the edge we
-- are proving juli cannot see. The point under test is juli's read, not kid's write.
insert into follows (follower_id, followed_id) values (:'kid', :'maya');

select test_as(:'juli');
select is((select followers from public_profile('maya_k')), 2,
    'followers comes from the definer count and sees BOTH edges');
select is((select count(*)::int from follows where followed_id = :'maya'), 1,
    'but juli selecting follows sees only the edge SHE is party to — one, not two. That gap is the anti-scraping mechanism.');

-- ---------------------------------------------------------------------------
-- The anchor badge works around GLO-145 rather than inheriting it.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
update profile_badges set show_anchor = true where user_id = :'maya';
-- a fit on the NEVER-WORN item: exactly GLO-145's shape
insert into item_fits (user_id, user_item_id, fit)
values (:'maya', '50000000-0000-0000-0000-0000000000f2', 'too_light');
select test_as(:'juli');
-- Names the shade rather than asserting null: badge_anchor is a single value
-- for the whole user, so `is null` depends on maya owning no other anchor
-- anywhere (GLO-161). The message is also updated — since 0031, anchor_badge
-- no longer filters status itself; it inherits the fix from user_shade_anchor.
select isnt((select badge_anchor from public_profile('maya_k')), 'fenty beauty 220',
    'a fit on a NEVER-WORN item does not become a public anchor badge — since 0031 anchor_badge inherits this from user_shade_anchor instead of filtering status itself');

select * from finish();
rollback;
