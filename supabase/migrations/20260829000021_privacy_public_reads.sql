-- 0021 · The additive public-read layer. GLO-116. docs/tech/02 §2.1, §2.3.
--
-- 0020 gave us can_view(). This turns it into actual visibility.
--
-- PURELY ADDITIVE. Every table below keeps its Phase-1 owner-only policy
-- untouched and gains a SECOND, select-only policy beside it. Postgres ORs
-- permissive policies together, so nothing that was visible stops being
-- visible. If Phase 1's 125 assertions move at all, this migration is wrong.
--
-- CREATION ORDER IS NOT COSMETIC. A `language sql` body is parsed AND resolved
-- at CREATE FUNCTION time (check_function_bodies defaults on); a `language
-- plpgsql` body is not. item_is_published is sql and calls
-- collection_is_visible, so the plpgsql one must exist first. Order:
--   column -> collection_is_visible (plpgsql) -> item_is_published (sql) -> policies.

-- Collections publish one at a time (§1.1, confirmed by Sean Aug 29) rather
-- than under a fifth profile-level surface — so a user whose shelf is only_you
-- can still share the collection link that §6 calls the unit that spreads.
alter table collections add column visibility scope_enum not null default 'only_you';

-- Mirrors can_view's check ORDER exactly — owner, block, minor, then scope —
-- because a collection's scope lives on its own row rather than in
-- privacy_scopes. This is the one permitted near-fork in the phase, and it
-- earns its keep only by staying in lockstep; the shape test asserts it.
create or replace function collection_is_visible(p_collection uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
    v_owner uuid;
    v_vis   scope_enum;
begin
    select user_id, visibility into v_owner, v_vis
      from collections where id = p_collection and deleted_at is null;
    if v_owner is null then return false; end if;
    if v_owner = (select auth.uid()) then return true; end if;
    if is_blocked((select auth.uid()), v_owner) then return false; end if;
    if is_minor_user(v_owner) then return false; end if;
    if v_vis = 'public' then return true; end if;
    if v_vis = 'friends' then return is_mutual_follow((select auth.uid()), v_owner); end if;
    return false;
end $$;

-- A user_item is published when the SHELF scope allows it, or when the item is
-- a step in a published routine / a row in a published list / a member of a
-- published collection. The second half is the BOUNDED disclosure: publishing a
-- routine discloses the products in THAT routine, not the whole shelf.
--
-- Definer, and not by accident: this reads routine_steps / rank_positions /
-- collection_items, each of which carries its own RLS. Calling them from inside
-- a policy on user_items without bypassing RLS is a mutual-recursion trap that
-- resolves to "invisible" and reads exactly like a working privacy feature.
create or replace function item_is_published(p_item uuid, p_owner uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select (can_view(p_owner, 'routines') and exists (
                select 1 from routine_steps rs join routines r on r.id = rs.routine_id
                 where rs.user_item_id = p_item and r.user_id = p_owner and r.deleted_at is null))
        or (can_view(p_owner, 'rankings') and exists (
                select 1 from rank_positions rp
                 where rp.user_item_id = p_item and rp.user_id = p_owner))
        or exists (
                select 1 from collection_items ci join collections c on c.id = ci.collection_id
                 where ci.user_item_id = p_item and c.user_id = p_owner and c.deleted_at is null
                   and collection_is_visible(c.id));
$$;

-- ---------------------------------------------------------------------------
-- The six public read policies.
--
-- `want_to_try` is never published (§2.1, confirmed by Sean Aug 29, explicitly
-- "for now — this may change later"). It is ONE predicate in ONE policy on
-- purpose, so revisiting it is a one-line change rather than archaeology.
-- ---------------------------------------------------------------------------

create policy user_items_public on user_items for select
    to anon, authenticated
    using (
        deleted_at is null
        and ((status <> 'want_to_try' and can_view(user_id, 'shelf'))
             or item_is_published(id, user_id))
    );

create policy rank_positions_public on rank_positions for select
    to anon, authenticated
    using (can_view(user_id, 'rankings'));

create policy routines_public on routines for select
    to anon, authenticated
    using (deleted_at is null and can_view(user_id, 'routines'));

create policy routine_steps_public on routine_steps for select
    to anon, authenticated
    using (exists (select 1 from routines r
                    where r.id = routine_id and r.deleted_at is null
                      and can_view(r.user_id, 'routines')));

create policy collections_public on collections for select
    to anon, authenticated
    using (collection_is_visible(id));

create policy collection_items_public on collection_items for select
    to anon, authenticated
    using (collection_is_visible(collection_id));

-- ---------------------------------------------------------------------------
-- The Regulated boundary, as a constraint rather than a convention.
--
-- The rule domain.md §5 draws is about EGRESS — logs, breadcrumbs, vendors —
-- NOT about our own Postgres. user_facts (0011) deliberately stores tone_band /
-- skin_type / hair_pattern precisely so the events ⋈ user_facts join stays
-- in-house. So this bans two things:
--   - free text and direct identity, which have no analytical use and are a
--     disclosure the moment a prop reaches a log line;
--   - body facts user_facts already holds, where duplicating into props buys
--     nothing the join does not already give.
--
-- It deliberately does NOT ban `fit` / `fits`. Event.swift already declares
-- onbAnchorCaptured(…, fit:) -> "fit" and fitCaptured(fits:) -> "fits".
-- Neither has a call site yet, so banning them would pass CI, pass review, and
-- then fail the day someone wires the fit events under a PHASE-1 ticket, with
-- the error pointing at this migration. The test asserts they are ACCEPTED.
--
-- NOT VALID first: `events` already carries Phase-1 rows and a validating ALTER
-- takes ACCESS EXCLUSIVE while it scans every partition. The constraint binds
-- new writes either way; the validate is a separate statement so the lock is
-- taken deliberately rather than as a side effect.
alter table events add constraint events_no_regulated_props check (
    not (props ?| array[
        'tone_band', 'tone_band_at_capture', 'skin_type', 'hair_pattern', 'concerns',
        'birth_year_month', 'birthday', 'age', 'phone', 'email',
        'bio', 'handle', 'display_name', 'anchor_shade'
    ])
) not valid;

alter table events validate constraint events_no_regulated_props;

-- ---------------------------------------------------------------------------
-- Grants. An RLS policy expression executes as the INVOKING user, so every
-- function a policy names must be executable by that user — this is the rule
-- 0020 learned the hard way (its follows insert policy called revoked helpers
-- and made following impossible for everyone).
--
-- Both functions below are security definer and take ids only. They answer
-- exactly the question their policy already discloses, and they internally call
-- the helpers that stay revoked from clients.
-- ---------------------------------------------------------------------------

revoke execute on function collection_is_visible(uuid) from public;
revoke execute on function item_is_published(uuid, uuid) from public;
grant  execute on function collection_is_visible(uuid) to anon, authenticated;
grant  execute on function item_is_published(uuid, uuid) to anon, authenticated;

comment on function item_is_published(uuid, uuid) is
    'Bounded disclosure: publishing a routine/list/collection discloses the items IN it, not the whole shelf. GLO-116, docs/tech/02 §2.1.';
