-- Grid G · swatches (0026). GLO-130, docs/tech/02 §9.8.
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

create or replace function test_as(uid uuid) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
end $$;

\set maya '00000000-0000-0000-0000-000000000001'
\set juli '00000000-0000-0000-0000-000000000002'
\set kid  '00000000-0000-0000-0000-0000000000d1'
\set onshelf  '40000000-0000-0000-0000-000000000002'
-- A variant NOBODY owns, minted here. Do not reuse a seeded id: the shared
-- local DB carries drive-drift rows and maya turns out to own
-- 40000000-...-0003, which made "a variant she does not own" quietly false.
\set offshelf '40000000-0000-0000-0000-0000000000ff'

select set_config('role', 'postgres', true);
insert into variants (id, product_id, kind, shade_code)
select :'offshelf', v.product_id, v.kind, 'nobody-owns-this'
  from variants v where v.id = :'onshelf';
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change_token_new,
                        email_change_token_current, email_change, phone_change, phone_change_token,
                        reauthentication_token)
values (:'kid', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'kid2@local.test', '', now(), '{}', '{}', now(), now(), '', '', '', '', '', '', '', '');

select test_as(:'maya');
-- Upserts: the seed writes both profiles rows now (GLO-182), without a band.
insert into profiles (user_id, birth_year_month, domains, tone_band)
values (:'maya', '1998-04', '{makeup}', 6)
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month,
    domains = excluded.domains, tone_band = excluded.tone_band;
select test_as(:'juli');
insert into profiles (user_id, birth_year_month, domains) values (:'juli', '1996-09', '{makeup}')
on conflict (user_id) do update set birth_year_month = excluded.birth_year_month, domains = excluded.domains;
select set_config('role', 'postgres', true);
insert into profiles (user_id, birth_year_month, domains)
values (:'kid', to_char(current_date - interval '15 years', 'YYYY-MM'), '{makeup}');

-- maya has ONE of the two variants on her shelf.
select test_as(:'maya');
insert into user_items (id, user_id, variant_id, status, client_id)
values ('50000000-0000-0000-0000-0000000000a1', :'maya', :'onshelf', 'own', 'dddddddd-0000-0000-0000-0000000000a1');

-- ---------------------------------------------------------------------------
-- The write gates live in the policy, not the button.
-- ---------------------------------------------------------------------------
select ok(can_post_swatch(:'onshelf'),      'maya may post for a variant on her shelf');
select ok(not can_post_swatch(:'offshelf'), 'she may NOT post for a variant she does not own');

select lives_ok($$
    insert into swatches (id, user_id, variant_id, r2_key, tone_band_at_capture)
    values ('60000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001',
            '40000000-0000-0000-0000-000000000002', 'maya/sw1.jpg', 6)
$$, 'posting for an owned variant succeeds');

select throws_ok($$
    insert into swatches (user_id, variant_id, r2_key, tone_band_at_capture)
    values ('00000000-0000-0000-0000-000000000001',
            '40000000-0000-0000-0000-0000000000ff', 'maya/sw2.jpg', 6)
$$, '42501', 'new row violates row-level security policy for table "swatches"',
    'posting for a variant NOT on the shelf is refused by the policy, not the app');

-- minors cannot post, and it is the DATABASE that says so
select test_as(:'kid');
select ok(not can_post_swatch(:'onshelf'), 'a minor may not post, even for a variant they own');
select throws_ok($$
    insert into swatches (user_id, variant_id, r2_key)
    values ('00000000-0000-0000-0000-0000000000d1', '40000000-0000-0000-0000-000000000002', 'kid/sw.jpg')
$$, '42501', 'new row violates row-level security policy for table "swatches"',
    'a minor''s insert is refused by the with-check — no photo posting under 18');

-- ---------------------------------------------------------------------------
-- pending_review is invisible to everyone but the owner.
-- ---------------------------------------------------------------------------
select is((select state::text from swatches where id = '60000000-0000-0000-0000-0000000000a1'), null,
    'a minor cannot see a pending swatch either');
select test_as(:'juli');
select is((select count(*)::int from swatches where id = '60000000-0000-0000-0000-0000000000a1'), 0,
    'a STRANGER cannot see a pending_review swatch');

-- make them mutual: still invisible while pending, because posting is a
-- per-act publish and pending is not a publish
select test_as(:'maya');
insert into follows (follower_id, followed_id) values (:'maya', :'juli');
select test_as(:'juli');
insert into follows (follower_id, followed_id) values (:'juli', :'maya');
select is((select count(*)::int from swatches where id = '60000000-0000-0000-0000-0000000000a1'), 0,
    'a MUTUAL follower cannot see it either — pending is not a publish, and no scope makes it one');

select test_as(:'maya');
select is((select count(*)::int from swatches where id = '60000000-0000-0000-0000-0000000000a1'), 1,
    'the owner sees their own pending swatch');

-- ---------------------------------------------------------------------------
-- public is readable; removed is not. The state is what gates, not the absence
-- of a state.
-- ---------------------------------------------------------------------------
select set_config('role', 'postgres', true);
update swatches set state = 'public', posted_at = now() where id = '60000000-0000-0000-0000-0000000000a1';
select test_as(:'juli');
select is((select count(*)::int from swatches where id = '60000000-0000-0000-0000-0000000000a1'), 1,
    'a public swatch is readable by another user');

select set_config('role', 'postgres', true);
update swatches set state = 'removed', removed_at = now() where id = '60000000-0000-0000-0000-0000000000a1';
select test_as(:'juli');
select is((select count(*)::int from swatches where id = '60000000-0000-0000-0000-0000000000a1'), 0,
    'a REMOVED swatch is not readable');

-- The policy tests state = 'public' rather than state <> 'removed', so a state
-- added later fails CLOSED. Prove it with a value that is neither.
select set_config('role', 'postgres', true);
update swatches set state = 'pending_review' where id = '60000000-0000-0000-0000-0000000000a1';
select test_as(:'juli');
select is((select count(*)::int from swatches where id = '60000000-0000-0000-0000-0000000000a1'), 0,
    'any non-public state is invisible — the policy allowlists `public` rather than denylisting `removed`, so future states fail closed');

-- ---------------------------------------------------------------------------
-- A block severs a public swatch. Posting is a per-act publish, but a block
-- still beats it.
-- ---------------------------------------------------------------------------
select set_config('role', 'postgres', true);
update swatches set state = 'public' where id = '60000000-0000-0000-0000-0000000000a1';
select test_as(:'maya');
insert into blocks (user_id, blocked_id) values (:'maya', :'juli');
select test_as(:'juli');
select is((select count(*)::int from swatches where id = '60000000-0000-0000-0000-0000000000a1'), 0,
    'a blocked viewer cannot see a PUBLIC swatch — per-act publish does not outrank a block');
select test_as(:'maya');
delete from blocks where user_id = :'maya' and blocked_id = :'juli';
select test_as(:'juli');
insert into blocks (user_id, blocked_id) values (:'juli', :'maya');
select is((select count(*)::int from swatches where id = '60000000-0000-0000-0000-0000000000a1'), 0,
    'and it works from the other direction too');
select test_as(:'juli');
delete from blocks where user_id = :'juli' and blocked_id = :'maya';

-- ---------------------------------------------------------------------------
-- The snapshot. This is the assertion the whole column exists for.
-- ---------------------------------------------------------------------------
select test_as(:'maya');
update profiles set tone_band = 9 where user_id = :'maya';
select is((select tone_band_at_capture from swatches where id = '60000000-0000-0000-0000-0000000000a1'), 6,
    'changing the profile tone band does NOT move an existing swatch — the band is snapshotted at capture, so July tan stays filed correctly');

-- ---------------------------------------------------------------------------
-- Grants, both directions.
-- ---------------------------------------------------------------------------
select ok(has_function_privilege('authenticated','can_post_swatch(uuid)','execute'),
    'can_post_swatch IS executable by authenticated — the insert policy names it and policies run as the invoker');
select ok(not has_function_privilege('anon','can_post_swatch(uuid)','execute'),
    'but NOT by anon — anon never posts');
select ok(not has_function_privilege('anon','viewer_blocked_by(uuid)','execute'),
    'viewer_blocked_by is NOT executable by anon — nothing reads without an account (0060)');
select ok(not has_function_privilege('anon','is_blocked(uuid,uuid)','execute'),
    'while the raw is_blocked stays revoked — the wrapper answers only about auth.uid()');

-- Privilege and policy agree (the 0024 rule, applied to a table added after it).
-- SELECT stays because swatches_public_read is `to anon`; the write verbs go.
select ok(not has_table_privilege('anon','public.swatches','select'),
    'anon has NO select on swatches — public is for signed-in viewers (0060, Sean Sept 3)');
select ok(not has_table_privilege('anon','public.swatches','insert'),
    'anon has no INSERT privilege — RLS is the second layer, not the only one');
select ok(not has_table_privilege('anon','public.swatches','update'),
    'nor UPDATE');
select ok(not has_table_privilege('anon','public.swatches','delete'),
    'nor DELETE');

select * from finish();
rollback;
