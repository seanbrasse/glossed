-- 0029 · browse_routines() — "AM routines from people with your skin". GLO-126.
-- docs/tech/02 §4.
--
-- The routine object is unchanged from V1: slot am/pm/weekly/wash_day, ordered
-- steps, started_on. Wash day was already first-class. 1.5 adds the browse.
--
-- FOUR REQUIREMENTS, none of them implementation detail:
--
-- 1. ONE can_view() per candidate owner, NOT per row. can_view in an RLS
--    `using` clause is a per-row definer call; a browse screen filtering a
--    thousand rows through it is the wrong shape. This is an RPC for exactly
--    that reason — search_catalog (0005/0017/0019) is the precedent.
-- 2. Titles come from public_texts where state = 'approved'. A routine whose
--    title is still pending does not appear AT ALL. That is how "no unmoderated
--    text is ever visible" holds during the window between write and verdict.
-- 3. The owner must be `discoverable`. Browse is a surfacing surface, so §1.3's
--    asymmetry applies exactly as it does to suggested people: to be surfaced
--    you opt in; private users still receive everything.
-- 4. Minors never appear. can_view already refuses them, but discoverable is
--    also locked false for minors (0020's trigger), so this is belt and braces.
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
    -- One row per candidate owner, so can_view is evaluated once per owner
    -- rather than once per routine.
    with visible_owners as (
        select ps.user_id
          from privacy_scopes ps
          join profiles p on p.user_id = ps.user_id
         where ps.discoverable
           and can_view(ps.user_id, 'routines')
           and (p_skin_type    is null or p.skin_type    = p_skin_type)
           and (p_hair_pattern is null or p.hair_pattern = p_hair_pattern)
    )
    select
        r.id,
        t.body,                                  -- approved title only
        r.slot,
        h.handle,
        (select count(*)::int from routine_steps rs where rs.routine_id = r.id),
        (select count(*)::int from user_items ui
          where ui.user_id = r.user_id and ui.deleted_at is null
            and ui.status <> 'want_to_try'),     -- the n behind the row
        r.started_on,
        r.created_at
      from routines r
      join visible_owners vo on vo.user_id = r.user_id
      join handles h on h.user_id = r.user_id
      -- INNER join: no approved title, no row. A pending title does not appear.
      join public_texts t
        on t.user_id = r.user_id
       and t.kind = 'routine_title'
       and t.subject_id = r.id
       and t.state = 'approved'
     where r.slot = p_slot
       and r.deleted_at is null
       and (p_cursor is null or r.created_at < p_cursor)
     order by r.created_at desc
     limit least(coalesce(p_limit, 20), 50);
$$;

-- Full intended ACL. Browsing needs an account: the filters default from the
-- viewer's own profile, and an anonymous browse has no viewer to default from.
revoke execute on function browse_routines(routine_slot, text, text, int, timestamptz)
    from public, anon, authenticated;
grant execute on function browse_routines(routine_slot, text, text, int, timestamptz)
    to authenticated;

comment on function browse_routines(routine_slot, text, text, int, timestamptz) is
    'Scope-respecting routine browse. can_view is evaluated ONCE PER OWNER, not per row. Titles are approved-only, so a pending title hides the whole routine. GLO-126, docs/tech/02 §4.';
