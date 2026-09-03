-- A public scope needs a handle (GLO-258, session-22 privacy audit).
--
-- tech/02 §3.1: a handle is "chosen at first publish"; the profile's own copy
-- says "nothing of yours is public until you pick one". Neither was true at
-- the database: `can_view` and `can_view_item` never asked whether the owner
-- had a handle, so an account that set `shelf = public` before claiming one
-- had its items, rankings, routines, collections and looks readable by user
-- id — to any signed-in stranger and, for the shelf and rankings, to the
-- anonymous role. Found by making six real accounts through the auth API and
-- reading every surface as every viewer (the audit harness in the session-22
-- handoff); the handle-less public owner ("dee") was the one cell the model
-- did not predict.
--
-- The fix sits in the two root functions every public policy funnels through
-- (user_items_public, rank_positions_public, collections_public,
-- collection_items_public, routines_public, routine_steps_public,
-- looks_public_read, look_photos_public_read, and the item_is_published /
-- collection_is_visible / routine_is_visible / look_is_public helpers all
-- call one of the two). The owner still sees their own rows; a viewer sees an
-- owner's only once that owner holds a handle. Minors, blocks and scopes are
-- unchanged and are checked after this gate, in the same order as before.
--
-- Swatches are deliberately not touched: `swatches_public_read` is its own
-- per-act predicate (state + block), no surface renders swatches yet, and
-- widening this migration to a table with no reader would be a change no
-- drive could see.

create or replace function has_handle(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (select 1 from handles h where h.user_id = p_user);
$$;

grant execute on function has_handle(uuid) to anon, authenticated;

create or replace function can_view(p_viewer uuid, p_owner uuid, p_surface visibility_surface)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_scope scope_enum;
begin
    if p_owner is null then return false; end if;
    if p_viewer is not null and p_viewer = p_owner then return true; end if;
    -- Nothing of yours is public until you pick a handle (tech/02 §3.1).
    if not has_handle(p_owner) then return false; end if;
    if is_blocked(p_viewer, p_owner) then return false; end if;
    if is_minor_user(p_owner) then return false; end if;

    -- routines and looks are PER ITEM since 0053 (can_view_item); asking the
    -- surface answers only_you, so a missed caller fails closed.
    select case p_surface
               when 'shelf'    then s.shelf
               when 'rankings' then s.rankings
           end
      into v_scope
      from privacy_scopes s
     where s.user_id = p_owner;

    if v_scope is null or v_scope = 'only_you' then return false; end if;
    if v_scope = 'public' then return true; end if;
    return is_mutual_follow(p_viewer, p_owner); -- friends
end $$;

create or replace function can_view_item(p_owner uuid, p_scope scope_enum)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    v_viewer uuid := (select auth.uid());
begin
    if p_owner is null then return false; end if;
    if v_viewer is not null and v_viewer = p_owner then return true; end if;
    -- Nothing of yours is public until you pick a handle (tech/02 §3.1).
    if not has_handle(p_owner) then return false; end if;
    if is_blocked(v_viewer, p_owner) then return false; end if;
    if is_minor_user(p_owner) then return false; end if;
    if p_scope is null or p_scope = 'only_you' then return false; end if;
    if p_scope = 'public' then return true; end if;
    return is_mutual_follow(v_viewer, p_owner); -- friends
end $$;
