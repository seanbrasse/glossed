-- Nothing reads without an account (GLO-258, session-22 audit, finding 2).
--
-- Sean, Sept 3: *"There should be no anonymous callers though? Only public
-- and private profiles/posts."* Until now the anonymous role held the
-- platform's default grant — every privilege on every table — and row-level
-- policies were the only thing between the anon key and everyone's public
-- rows: the audit read public shelves, rankings and collections by user id
-- with no session at all, while looks and routines happened to refuse. The
-- rule is now the one Sean stated: "public" means visible to any signed-in
-- account; the anonymous key reads the catalog and nothing else, because
-- onboarding searches it before an account exists (the payoff's bay, the
-- anchor variants, the category list).
--
-- Three parts. Every user-content table, view and RPC loses its anon grant;
-- the catalog tables keep SELECT only; and the default privileges for
-- objects `postgres` creates in `public` no longer hand anon anything, so a
-- future table needs an explicit grant to be anonymously readable. tech/02
-- §6's link cards, which assumed anon reads, will need a server-side
-- renderer with its own credential when they arrive.

-- 1 · user content: no anon grant of any kind.
revoke all on table
    agg_rank_scores, agg_variant_stats, audit_records,
    collection_items, collections, face_offs, failed_searches, ingest_jobs,
    item_chips, item_fits, merge_candidates, profiles, rank_positions,
    routine_steps, routines, scored_face_offs, shade_cooccurrence, swatches,
    user_items, user_shade_anchor, user_shelf_items
from anon;

-- 2 · the catalog: read-only for anon, nothing else.
revoke insert, update, delete, truncate, references, trigger on table
    attribute_chips, brands, categories, experience_chips, product_attributes,
    products, routine_events, variant_images, variants
from anon;

-- 3 · RPCs that speak about people, or write. Most of these carried Postgres's
--     default EXECUTE to PUBLIC, which anon inherits — so the revoke is from
--     PUBLIC and the grant to accounts is explicit.
revoke execute on function public_profile(text) from public, anon;
grant execute on function public_profile(text) to authenticated, service_role;
revoke execute on function leaderboard(uuid, text, boolean, integer) from public, anon;
grant execute on function leaderboard(uuid, text, boolean, integer) to authenticated, service_role;
revoke execute on function can_view(uuid, visibility_surface) from public, anon;
grant execute on function can_view(uuid, visibility_surface) to authenticated, service_role;
revoke execute on function payoff_for_variant(uuid) from public, anon;
grant execute on function payoff_for_variant(uuid) to authenticated, service_role;
revoke execute on function trending(text, integer) from public, anon;
grant execute on function trending(text, integer) to authenticated, service_role;
revoke execute on function apply_face_off_session(jsonb, jsonb) from public, anon;
grant execute on function apply_face_off_session(jsonb, jsonb) to authenticated, service_role;
revoke execute on function capture_fit(uuid, fit_enum[], text) from public, anon;
grant execute on function capture_fit(uuid, fit_enum[], text) to authenticated, service_role;
revoke execute on function create_personal_product(uuid, uuid, domain_enum, text, text, text) from public, anon;
grant execute on function create_personal_product(uuid, uuid, domain_enum, text, text, text) to authenticated, service_role;
revoke execute on function collection_is_visible(uuid) from public, anon;
grant execute on function collection_is_visible(uuid) to authenticated, service_role;
revoke execute on function item_is_published(uuid, uuid) from public, anon;
grant execute on function item_is_published(uuid, uuid) to authenticated, service_role;
revoke execute on function has_handle(uuid) from public, anon;
grant execute on function has_handle(uuid) to authenticated, service_role;
revoke execute on function viewer_blocked_by(uuid) from public, anon;
grant execute on function viewer_blocked_by(uuid) to authenticated, service_role;
revoke execute on function record_failed_search(text, domain_enum) from public, anon;
grant execute on function record_failed_search(text, domain_enum) to authenticated, service_role;

-- 4 · the fence: what postgres creates from now on grants anon nothing.
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on functions from anon;
-- A new function otherwise arrives with EXECUTE to PUBLIC, which anon is a
-- member of; accounts and the service role still get theirs from the platform's
-- defaults, so nothing signed in loses anything.
alter default privileges for role postgres in schema public revoke execute on functions from public;
alter default privileges for role postgres in schema public revoke all on sequences from anon;

-- 5 · the two root functions fail closed for a viewer with no account, so a
--     policy reached through some future anon grant still answers no.
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
    -- No account, no reading (Sept 3). Public is for signed-in viewers.
    if p_viewer is null then return false; end if;
    if p_viewer = p_owner then return true; end if;
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
    -- No account, no reading (Sept 3). Public is for signed-in viewers.
    if v_viewer is null then return false; end if;
    if v_viewer = p_owner then return true; end if;
    -- Nothing of yours is public until you pick a handle (tech/02 §3.1).
    if not has_handle(p_owner) then return false; end if;
    if is_blocked(v_viewer, p_owner) then return false; end if;
    if is_minor_user(p_owner) then return false; end if;
    if p_scope is null or p_scope = 'only_you' then return false; end if;
    if p_scope = 'public' then return true; end if;
    return is_mutual_follow(v_viewer, p_owner); -- friends
end $$;
