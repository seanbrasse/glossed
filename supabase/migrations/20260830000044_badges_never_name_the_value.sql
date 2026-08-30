-- 0044 · A profile badge never names a body fact. GLO-205.
-- Sean's ruling, Aug 30, asked directly with four options on the table
-- including "exact is fine once they opt in". He took the strictest:
--
--   never the exact value — for skin type or hair pattern, opted in or not.
--
-- It began as "maybe we shouldn't outright tell people other people's
-- hairtypes" and widened on inspection: show_skin_type was publishing the
-- literal 'combo' by the same mechanism, so a hair-only fix would have left
-- the two surfaces inconsistent for the second time.
--
-- This finishes what 0034 started. That migration applied "consent AND
-- non-disclosure, not one traded for the other" to suggested_people and
-- stopped there. public_profile kept quoting the row. Same principle, the
-- other surface.
--
-- WHAT CHANGES, and it is behaviour rather than wording: a body-fact badge
-- stops being a fact about its owner and becomes a match between two people.
--
--   viewer signed in, same value   → 'similar skin to yours'
--   viewer signed in, differs      → nothing
--   viewer signed out, or no value → nothing
--   viewer IS the owner            → nothing (see below)
--
-- So the columns are now VIEWER-RELATIVE. Anything that memoises a profile by
-- handle alone is now wrong; nothing does today, and this comment is here for
-- whoever adds the first cache.
--
-- THE OWNER CASE IS LOAD-BEARING, NOT TIDINESS. StrangerPreview (GLO-190)
-- builds "what a stranger sees" from public_profile called on YOURSELF, and
-- takes the badge strings straight from it. Compare viewer to owner naively
-- and you trivially match yourself, so that screen would show a badge no
-- signed-out stranger can see — the precise lie the screen exists to catch,
-- reintroduced by the fix meant to protect the same data. Excluding self is
-- what makes the preview honest for free, with no client change.
--
-- ANCHOR IS UNTOUCHED, for the reason 0034 already recorded and this ticket
-- restates: 'wears fenty 240' is a product someone owns, not a body fact.
-- domain.md §5 draws that line and Sean's rulings have kept it twice.
--
-- Not in scope: hair_pattern as an aggregation DIMENSION in the taste engine.
-- Identifier-free, min-n gated, and what the attribute is for. The ruling is
-- about display.

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
        can_view(h.user_id, 'routines')
      from handles h
      join profiles pr on pr.user_id = h.user_id
      left join profile_badges bg on bg.user_id = h.user_id
      cross join me
      left join my_profile mp on true
     where h.handle = lower(trim(p_handle))
       and not is_minor_user(h.user_id)
       and not is_blocked((select auth.uid()), h.user_id);
$$;

-- Re-granted explicitly. CREATE OR REPLACE keeps the existing ACL, but this
-- function has already lost an option once to a replace that assumed
-- otherwise (0031's security_invoker), so the grant is restated rather than
-- trusted.
grant execute on function public_profile(text) to anon, authenticated;

comment on function public_profile(text) is
    'Public profile projection. Body-fact badges are VIEWER-RELATIVE and never name the value (GLO-205, Sean Aug 30): they render only to a signed-in viewer, other than the owner, whose own value matches. anchor_badge is a product fact and is unconditional on its opt-in.';
