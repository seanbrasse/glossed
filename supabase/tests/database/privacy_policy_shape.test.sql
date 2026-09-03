-- Grid H · the shape of the thing. GLO-117, docs/tech/02 §9.9.
--
-- This file tests the SCHEMA, not the data, and it is the one that makes "the
-- logic cannot fork" an enforced property rather than an intention. Every other
-- grid proves can_view behaves correctly; this one proves nothing bypasses it.
--
-- If someone adds a 1.5 public read policy with a hand-rolled predicate, or
-- quietly grants a helper to clients, this file goes red. That is its whole job.
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

-- ---------------------------------------------------------------------------
-- 1. Every public read policy routes through can_view (or its per-collection
--    sibling). The single assertion that stops the fork.
-- ---------------------------------------------------------------------------
select is(
    (select count(*)::int from pg_policies
      where schemaname = 'public'
        and policyname like '%\_public'
        and coalesce(qual, '') !~ 'can_view|collection_is_visible|item_is_published'),
    0,
    'EVERY *_public policy routes through can_view / collection_is_visible / item_is_published — none hand-rolls its own predicate');

-- and there are exactly the six we expect, so a SEVENTH cannot appear unnoticed
select is(
    (select array_agg(tablename::text order by tablename) from pg_policies
      where schemaname = 'public' and policyname like '%\_public'),
    array['collection_items','collections','rank_positions','routine_steps','routines','user_items'],
    'exactly six tables carry a public read policy — a seventh would have to be added here deliberately');

-- ---------------------------------------------------------------------------
-- 2. The tables that must NEVER get a public policy.
-- ---------------------------------------------------------------------------
select is((select count(*)::int from pg_policies
            where schemaname='public' and tablename='profiles' and roles::text[] && array['anon','authenticated']
              and cmd in ('SELECT','ALL') and coalesce(qual,'') ~ 'can_view'), 0,
    'profiles has no can_view policy — the public profile is an RPC projection, never relaxed RLS');
select is((select count(*)::int from pg_policies where schemaname='public' and tablename='item_fits'  and policyname like '%\_public'), 0,
    'item_fits has no public policy — fit is Regulated');
select is((select count(*)::int from pg_policies where schemaname='public' and tablename='item_chips' and policyname like '%\_public'), 0,
    'item_chips has no public policy');
select is((select count(*)::int from pg_policies where schemaname='public' and tablename='face_offs'  and policyname like '%\_public'), 0,
    'face_offs has no public policy — the pairwise history reveals more than the order does');

-- ---------------------------------------------------------------------------
-- 3. Grants. Both directions, per the rule that a grant does not imply a
--    revoke and silence is a grant under Supabase default privileges.
-- ---------------------------------------------------------------------------
select ok(not has_function_privilege('authenticated','can_view(uuid,uuid,visibility_surface)','execute'),
    'the 3-arg can_view is not executable by authenticated — it takes an arbitrary viewer');
select ok(not has_function_privilege('anon','can_view(uuid,uuid,visibility_surface)','execute'),
    'nor by anon');
select ok(not has_function_privilege('authenticated','is_blocked(uuid,uuid)','execute'),
    'is_blocked is not executable by authenticated — it would expose arbitrary block relationships');
select ok(not has_function_privilege('anon','is_blocked(uuid,uuid)','execute'), 'nor by anon');
select ok(not has_function_privilege('authenticated','is_minor_user(uuid)','execute'),
    'is_minor_user is not executable by authenticated — it would expose anyone''s minor status');
select ok(not has_function_privilege('anon','is_minor_user(uuid)','execute'), 'nor by anon');
select ok(not has_function_privilege('authenticated','is_mutual_follow(uuid,uuid)','execute'),
    'is_mutual_follow is not executable by authenticated');
select ok(not has_function_privilege('anon','can_follow(uuid)','execute'),
    'can_follow is not executable by anon — 0020 granted without revoking; 0022 fixed it');

-- the client-facing surface IS reachable, or the policies break
select ok(not has_function_privilege('anon','can_view(uuid,visibility_surface)','execute'),
    'the 2-arg wrapper is NOT executable by anon — nothing reads without an account (0060)');
select ok(not has_function_privilege('anon','collection_is_visible(uuid)','execute'),
    'collection_is_visible is NOT executable by anon — nothing reads without an account (0060)');
select ok(not has_function_privilege('anon','item_is_published(uuid,uuid)','execute'),
    'item_is_published is NOT executable by anon — same rule (0060)');

-- ---------------------------------------------------------------------------
-- 4. Defaults. Default-deny is the gate's entire premise.
-- ---------------------------------------------------------------------------
select is(
    (select array_agg(column_default::text order by column_name) from information_schema.columns
      where table_name = 'privacy_scopes' and column_name in ('shelf','rankings')),
    array_fill('''only_you''::scope_enum'::text, array[2]),
    'both surviving scope columns default only_you — routines and looks are per-item since 0053');
select is((select column_default::text from information_schema.columns
            where table_name='privacy_scopes' and column_name='discoverable'), 'false',
    'discoverable defaults false');
select is((select column_default::text from information_schema.columns
            where table_name='collections' and column_name='visibility'), '''only_you''::scope_enum',
    'a new collection defaults only_you — publishing is a per-act decision');

-- ---------------------------------------------------------------------------
-- 5. collection_is_visible mirrors can_view's check ORDER. It is the one
--    permitted near-fork in the phase, and it earns its keep only by staying in
--    lockstep — owner, then block, then minor, then scope.
-- ---------------------------------------------------------------------------
-- 0053 healed the near-fork: the order lives in can_view_item once, and
-- collection_is_visible DELEGATES rather than restating it.
select ok(
    (select prosrc from pg_proc where proname = 'collection_is_visible') ~ 'can_view_item',
    'collection_is_visible delegates to can_view_item — the fork is healed, not merely in lockstep');
select ok(
    (select prosrc from pg_proc where proname = 'can_view_item') ~
    '(?s)auth\.uid\(\).*is_blocked.*is_minor_user.*public.*friends',
    'can_view_item checks owner → block → minor → scope, in that order, exactly as can_view does');

-- ---------------------------------------------------------------------------
-- 6. Privilege and policy must AGREE. A 1.5 table with no anon policy must not
--    hold anon table privilege either — otherwise RLS is the only thing
--    standing between anon and the table, and adding one legitimate `to anon`
--    policy later silently inherits table-wide access nobody intended.
--    This is GLO-150's shape, caught in our own lane (0024).
-- ---------------------------------------------------------------------------
select is(
    (select array_agg(t::text order by t) from unnest(array[
        'privacy_scopes','follows','blocks','mutes',
        'handles','public_texts','profile_badges','reserved_handles'
     ]) as t
     where has_table_privilege('anon', 'public.'||t, 'select')
        or has_table_privilege('anon', 'public.'||t, 'insert')
        or has_table_privilege('anon', 'public.'||t, 'update')
        or has_table_privilege('anon', 'public.'||t, 'delete')),
    null,
    'NO Phase-1.5 identity/privacy table grants anon any privilege — privilege and policy agree, so RLS is the second layer rather than the only one');

-- reserved_handles is deny-all to every client role, not just anon.
select ok(not has_table_privilege('authenticated','public.reserved_handles','select'),
    'reserved_handles is unreadable by authenticated too — enumerating it is a gift to squatters');

-- ...while the tables that DO carry `to anon` public read policies keep the
-- privilege they need. Revoking there would break link cards and share pages.
select ok(not has_table_privilege('anon','public.user_items','select'),
    'user_items has NO anon select — public is for signed-in viewers (0060, Sean Sept 3)');
select ok(not has_table_privilege('anon','public.collections','select'),
    'collections has no anon select for the same reason');

select * from finish();
rollback;
