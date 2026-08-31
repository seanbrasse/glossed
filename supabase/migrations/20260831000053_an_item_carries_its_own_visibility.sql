-- 0053 · An item carries its own visibility, and can_view learns to ask.
-- GLO-272 (GLO-271's 1/6), built to Sean's Aug 31 rulings, plus the profile
-- photo column his same-day ask needs.
--
-- WHAT CHANGES, in one breath: privacy moves from per-surface to PER ITEM for
-- looks and routines. Collections already lived this way — 0021 gave them
-- `visibility` and `collection_is_visible()`, and that "permitted near-fork"
-- becomes the pattern the whole schema follows, through one shared function
-- instead of a fork. `privacy_scopes` SURVIVES, holding `shelf` and
-- `rankings` only (Sean: "start it as private with the shelf and build it so
-- we can maybe publicize later") — keeping those columns is the point, so
-- publishing later is a default change and a control, not a migration
-- against live data.
--
-- One correction to GLO-272's spec, found by reading rather than trusting it:
-- collections need NO new column — 0021 already gave them one. Two tables
-- gain columns, not three.

-- ---------------------------------------------------------------------------
-- The columns.
--
-- Default only_you, and that is the migration's safety property: every
-- existing row becomes private. A backfill promoting rows to the owner's old
-- surface scope would publish content chosen once for a CLASS, which is
-- exactly the lock-in the ruling removes. DO NOT backfill to a wider scope.
-- ---------------------------------------------------------------------------
alter table looks    add column visibility scope_enum not null default 'only_you';
alter table routines add column visibility scope_enum not null default 'only_you';

-- looks' UPDATE privilege is column-scoped (0048: id, user_id, caption,
-- state), so a new column needs its own grant or the owner cannot archive —
-- the RLS policy would allow the row while the privilege refuses the column.
-- routines' and profiles' UPDATE grants are table-wide; their new columns
-- ride along for free.
grant update (visibility) on looks to authenticated;

-- The profile photo's R2 key (Sean, Aug 31: the pfp gets an edit icon).
-- A KEY, not a URL: the app never holds an R2 credential (ADR 0004), and no
-- read path exists yet for user photos — rendering waits on that ruling, the
-- same as look photos. Regulated the moment it is a face (domain.md §5):
-- never into logs, analytics props or breadcrumbs.
alter table profiles add column photo_r2_key text;

comment on column looks.visibility is
    'Per-item scope (GLO-272). Composes with state: a look is readable by others only when state = public AND this scope admits the viewer. only_you is the archive Sean asked for without unposting.';
comment on column routines.visibility is
    'Per-item scope (GLO-272), the collections pattern from 0021 applied to routines.';
comment on column profiles.photo_r2_key is
    'R2 object key for the profile photo. Regulated once it is a face (domain.md §5). No read path exists yet — display falls back to the drawn avatar until that ruling lands.';

-- ---------------------------------------------------------------------------
-- The one visibility function, item-scoped.
--
-- collection_is_visible's exact check ORDER — owner, block, minor, then
-- scope — generalized to take the scope as an argument. Everything below
-- delegates here, so the rule cannot fork again.
-- ---------------------------------------------------------------------------
create or replace function can_view_item(p_owner uuid, p_scope scope_enum)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
    v_viewer uuid := (select auth.uid());
begin
    if p_owner is null then return false; end if;
    if v_viewer is not null and v_viewer = p_owner then return true; end if;
    if is_blocked(v_viewer, p_owner) then return false; end if;
    if is_minor_user(p_owner) then return false; end if;
    if p_scope is null or p_scope = 'only_you' then return false; end if;
    if p_scope = 'public' then return true; end if;
    return is_mutual_follow(v_viewer, p_owner); -- friends
end $$;

-- The fork, healed: collections' own function becomes a lookup plus the
-- shared rule. Same signature, same answers, one spelling of the check order.
create or replace function collection_is_visible(p_collection uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select can_view_item(c.user_id, c.visibility)
      from collections c
     where c.id = p_collection and c.deleted_at is null;
$$;

-- ---------------------------------------------------------------------------
-- Policies: the item tables consult the ITEM.
-- ---------------------------------------------------------------------------
alter policy routines_public on routines
    using (deleted_at is null and can_view_item(user_id, visibility));

alter policy looks_public_read on looks
    using (state = 'public' and can_view_item(user_id, visibility));

-- 0043 wrote look_photos' public read inline; it follows the look's own row
-- now, or a photo could disagree with its parent — which is exactly what the
-- suite's anti-drift assertion (look_tags_spots · 15) exists to catch, and
-- did, in the first draft of this migration.
alter policy look_photos_public_read on look_photos
    using (exists (select 1 from looks l
                    where l.id = look_id
                      and l.state = 'public'
                      and can_view_item(l.user_id, l.visibility)));

alter policy routine_steps_public on routine_steps
    using (exists (select 1 from routines r
                    where r.id = routine_id and r.deleted_at is null
                      and can_view_item(r.user_id, r.visibility)));

-- item_is_published's routines half follows the routine's own row now; the
-- rankings half is untouched (rankings stay per-surface, per the ruling).
create or replace function item_is_published(p_item uuid, p_owner uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
                select 1 from routine_steps rs join routines r on r.id = rs.routine_id
                 where rs.user_item_id = p_item and r.user_id = p_owner
                   and r.deleted_at is null
                   and can_view_item(r.user_id, r.visibility))
        or (can_view(p_owner, 'rankings') and exists (
                select 1 from rank_positions rp
                 where rp.user_item_id = p_item and rp.user_id = p_owner))
        or exists (
                select 1 from collection_items ci
                 where ci.user_item_id = p_item
                   and collection_is_visible(ci.collection_id));
$$;

-- 0049/0050's definer helpers restated the surface rule; they follow the
-- item now, so a photo, tag or link can never disagree with its parent.
create or replace function look_photo_is_public(p_photo uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from look_photos p join looks l on l.id = p.look_id
         where p.id = p_photo
           and l.state = 'public'
           and can_view_item(l.user_id, l.visibility));
$$;

create or replace function look_is_public(p_look uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from looks l
         where l.id = p_look
           and l.state = 'public'
           and can_view_item(l.user_id, l.visibility));
$$;

create or replace function routine_is_visible(p_routine uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select exists (select 1 from routines r
                    where r.id = p_routine
                      and r.deleted_at is null
                      and can_view_item(r.user_id, r.visibility));
$$;

-- ---------------------------------------------------------------------------
-- The readers of the old surface answer.
-- ---------------------------------------------------------------------------
-- browse_routines: the owner-level gate becomes a row-level column check —
-- CHEAPER than the old shape (a column filter and an indexable one, not a
-- definer call per owner). discoverable still gates surfacing (§1.3), minors
-- still cannot appear (visibility check refuses them via can_view_item's
-- order — asserted, not assumed, by the suite).
create or replace function browse_routines(
    p_slot          routine_slot,
    p_skin_type     text default null,
    p_hair_pattern  text default null,
    p_limit         int  default 20,
    p_cursor        timestamptz default null
)
returns table (
    routine_id    uuid,
    title         text,
    slot          routine_slot,
    owner_handle  text,
    step_n        int,
    owner_shelf_n int,
    started_on    date,
    created_at    timestamptz
)
language sql stable security definer set search_path = public as $$
    with discoverable_owners as (
        select ps.user_id
          from privacy_scopes ps
          join profiles p on p.user_id = ps.user_id
         where ps.discoverable
           and (p_skin_type    is null or p.skin_type    = p_skin_type)
           and (p_hair_pattern is null or p.hair_pattern = p_hair_pattern)
    )
    select
        r.id,
        t.body,
        r.slot,
        h.handle,
        (select count(*)::int from routine_steps rs where rs.routine_id = r.id),
        (select count(*)::int from user_items ui
          where ui.user_id = r.user_id and ui.deleted_at is null
            and ui.status <> 'want_to_try'),
        r.started_on,
        r.created_at
      from routines r
      join discoverable_owners vo on vo.user_id = r.user_id
      join handles h on h.user_id = r.user_id
      join public_texts t
        on t.user_id = r.user_id
       and t.kind = 'routine_title'
       and t.subject_id = r.id
       and t.state = 'approved'
     where r.slot = p_slot
       and r.deleted_at is null
       and can_view_item(r.user_id, r.visibility)
       and (p_cursor is null or r.created_at < p_cursor)
     order by r.created_at desc
     limit least(coalesce(p_limit, 20), 50);
$$;

-- public_profile: 0044's body VERBATIM — the badge rules are load-bearing
-- (GLO-205: viewer-relative, never naming the value) — with exactly one line
-- changed. The first draft of this migration copied 0025's older skeleton and
-- silently regressed those rules; the suite caught it (public_profile 13/17/18).
create or replace function public_profile(p_handle text)
returns table (handle text, display_name text, avatar_seed text, bio text,
               badge_skin_type text, badge_anchor text, badge_hair_pattern text,
               followers int, following int, shelf_n int, ranked_lists_n int,
               shelf_visible bool, rankings_visible bool, routines_visible bool)
language sql stable security definer set search_path = public as $$
    with me as (
        select (select auth.uid()) as uid
    ),
    -- The viewer's own row, read through a definer function so no profiles
    -- policy has to be relaxed. Null for anon, which is what makes a
    -- signed-out viewer see no body facts at all.
    my_profile as (
        select p.skin_type, p.hair_pattern
          from profiles p, me
         where p.user_id = me.uid
    )
    select
        h.handle,
        pr.display_name,
        pr.avatar_seed,
        (select t.body from public_texts t
          where t.user_id = h.user_id and t.kind = 'bio' and t.state = 'approved'),
        case when bg.show_skin_type
              and me.uid is not null
              and me.uid <> h.user_id
              and mp.skin_type is not null
              and mp.skin_type = pr.skin_type
             then 'similar skin to yours' end,
        case when bg.show_anchor then anchor_badge(h.user_id) end,
        case when bg.show_hair_pattern
              and me.uid is not null
              and me.uid <> h.user_id
              and mp.hair_pattern is not null
              and mp.hair_pattern = pr.hair_pattern
             then 'similar hair to yours' end,
        follower_count(h.user_id),
        following_count(h.user_id),
        (select count(*)::int from user_items ui
          where ui.user_id = h.user_id and ui.deleted_at is null and ui.status <> 'want_to_try'),
        (select count(distinct rp.category_id)::int from rank_positions rp where rp.user_id = h.user_id),
        can_view(h.user_id, 'shelf'),
        can_view(h.user_id, 'rankings'),
        -- Per-item since 0053: "does this profile hold any routine the
        -- VIEWER may see" — the only honest surface answer left.
        exists (select 1 from routines r
                 where r.user_id = h.user_id and r.deleted_at is null
                   and can_view_item(r.user_id, r.visibility))
      from handles h
      join profiles pr on pr.user_id = h.user_id
      left join profile_badges bg on bg.user_id = h.user_id
      cross join me
      left join my_profile mp on true
     where h.handle = lower(trim(p_handle))
       and not is_minor_user(h.user_id)
       and not is_blocked((select auth.uid()), h.user_id);
$$;

grant execute on function public_profile(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- privacy_scopes trims to what stays per-surface.
--
-- can_view first: its body reads the columns, and a dropped column breaks a
-- plpgsql SELECT at plan time. The routines/looks arms answer NULL now, which
-- the only_you branch turns into false — an old caller fails CLOSED, never
-- open. The enum keeps all four values: policy signatures and GLO-136's
-- renderer name them.
-- ---------------------------------------------------------------------------
create or replace function can_view(p_viewer uuid, p_owner uuid, p_surface visibility_surface)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
    v_scope scope_enum;
begin
    if p_owner is null then return false; end if;
    if p_viewer is not null and p_viewer = p_owner then return true; end if;
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

-- The minor lock reads the row's columns by name, so it must shed the two
-- that leave — a trigger referencing a dropped field is a 42703 at the next
-- write, which the suite caught (privacy_minors · 19-22, first draft).
--
-- The lock's REACH does not shrink: a minor's looks and routines are private
-- by construction through can_view_item's own minor check, per item, which is
-- stronger than a row lock — it cannot be bypassed by never inserting a row.
create or replace function lock_minor_scopes()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    if is_minor_user(new.user_id) then
        if new.shelf <> 'only_you' or new.rankings <> 'only_you' or new.discoverable then
            raise exception 'minors are private by construction' using errcode = 'check_violation';
        end if;
    end if;
    return new;
end $$;

alter table privacy_scopes drop column routines, drop column looks;

revoke execute on function can_view_item(uuid, scope_enum) from public, anon, authenticated;
grant execute on function can_view_item(uuid, scope_enum) to authenticated;

comment on function can_view_item(uuid, scope_enum) is
    'The per-item gate (GLO-272): collection_is_visible''s check order — owner, block, minor, scope — with the scope handed in. Every item policy delegates here so the rule cannot fork.';
comment on table privacy_scopes is
    'Per-surface scopes for what STAYS per-surface: shelf and rankings, both forced only_you with no user control this phase (Sean, Aug 31 — kept so publishing later is a default change, not a migration). routines/looks moved to their rows in 0053.';
