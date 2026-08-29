-- 0025 · public_profile() — the only way a profile reaches another human.
-- GLO-121. docs/tech/02 §3.3, §3.4.
--
-- `profiles` holds Regulated fields (birth_year_month, tone_band, skin_type,
-- hair_pattern) and its owner-only policy NEVER relaxes. This is a projection,
-- not a policy change. Whatever this function does not return does not exist on
-- a public profile — GLO-125's screen is forbidden from falling back to any
-- other query, because every other query is owner-scoped by design.

-- Follower counts come from here, never from selecting `follows`. That policy
-- returns only your own edges (0020), and this is the entire anti-scraping
-- mechanism: if a client could enumerate follows for an arbitrary user, the
-- graph is walkable one profile at a time.
create or replace function follower_count(p_user uuid)
returns int language sql stable security definer set search_path = public as $$
    select count(*)::int from follows where followed_id = p_user;
$$;

create or replace function following_count(p_user uuid)
returns int language sql stable security definer set search_path = public as $$
    select count(*)::int from follows where follower_id = p_user;
$$;

-- The anchor badge's evidence, with GLO-145 worked around explicitly.
--
-- user_shade_anchor filters c.is_anchor and deleted_at but NOT status, so a fit
-- captured on a never-worn want_to_try item becomes anchor evidence (GLO-145,
-- verified in psql). Phase 1's version of that is a bad match. HERE it would be
-- a false public statement about a person — "wears fenty 240" on a profile a
-- stranger is reading.
--
-- So this filters status itself rather than inheriting the defect silently.
-- When GLO-145's view half lands, this join becomes redundant, not wrong —
-- leave it, or remove it deliberately in that ticket.
create or replace function anchor_badge(p_user uuid)
returns text language sql stable security definer set search_path = public as $$
    select b.name || ' ' || v.shade_code
      from user_shade_anchor a
      join user_items ui on ui.user_id = a.user_id and ui.variant_id = a.variant_id
      join variants v    on v.id = a.variant_id
      join products p    on p.id = v.product_id
      join brands b      on b.id = p.brand_id
     where a.user_id = p_user
       and ui.status <> 'want_to_try'      -- GLO-145: never-worn is not evidence
       and ui.deleted_at is null
       and v.shade_code is not null
     order by a.captured_at desc
     limit 1;
$$;

-- ---------------------------------------------------------------------------
-- public_profile(handle)
--
-- Returns ZERO ROWS — not an error, not a stub — for an unclaimed handle, a
-- minor owner, or a block in either direction. "Not found" and "blocked" are
-- deliberately the SAME response: anything else is a private-account oracle,
-- where a blocked user learns they are blocked by comparing response shapes.
-- ---------------------------------------------------------------------------
create or replace function public_profile(p_handle text)
returns table (
    handle             text,
    display_name       text,
    avatar_seed        text,
    bio                text,
    badge_skin_type    text,
    badge_anchor       text,
    badge_hair_pattern text,
    followers          int,
    following          int,
    shelf_n            int,
    ranked_lists_n     int,
    shelf_visible      boolean,
    rankings_visible   boolean,
    routines_visible   boolean
)
language sql stable security definer set search_path = public as $$
    select
        h.handle,
        pr.display_name,
        pr.avatar_seed,
        -- Only APPROVED text ever renders. A pending edit shows the previously
        -- approved body via this same filter, or nothing.
        (select t.body from public_texts t
          where t.user_id = h.user_id and t.kind = 'bio' and t.state = 'approved'),
        -- Badges are an opt-in publication of Regulated data: the flag must be
        -- on, and the values are display strings, never the raw profiles row.
        case when bg.show_skin_type    then pr.skin_type    end,
        case when bg.show_anchor       then anchor_badge(h.user_id) end,
        case when bg.show_hair_pattern then pr.hair_pattern end,
        follower_count(h.user_id),
        following_count(h.user_id),
        -- The n behind every claim the profile makes. want_to_try is excluded
        -- for the same reason it is never published (0021).
        (select count(*)::int from user_items ui
          where ui.user_id = h.user_id and ui.deleted_at is null and ui.status <> 'want_to_try'),
        (select count(distinct rp.category_id)::int from rank_positions rp where rp.user_id = h.user_id),
        can_view(h.user_id, 'shelf'),
        can_view(h.user_id, 'rankings'),
        can_view(h.user_id, 'routines')
      from handles h
      join profiles pr on pr.user_id = h.user_id
      left join profile_badges bg on bg.user_id = h.user_id
     where h.handle = lower(trim(p_handle))
       -- The three reasons a profile does not exist, all producing zero rows.
       and not is_minor_user(h.user_id)
       and not is_blocked((select auth.uid()), h.user_id);
$$;

-- Full intended ACL per object. anon needs public_profile for web share pages
-- (GLO-30 §6.2); the count and badge helpers are internal to it.
revoke execute on function public_profile(text)   from public, anon, authenticated;
revoke execute on function follower_count(uuid)   from public, anon, authenticated;
revoke execute on function following_count(uuid)  from public, anon, authenticated;
revoke execute on function anchor_badge(uuid)     from public, anon, authenticated;

grant execute on function public_profile(text) to anon, authenticated;

comment on function public_profile(text) is
    'The ONLY way a profile reaches another human. profiles RLS never relaxes; this is a projection. Unclaimed handle, minor owner and blocked viewer all return zero rows identically — anything else is a private-account oracle. GLO-121, docs/tech/02 §3.3.';
