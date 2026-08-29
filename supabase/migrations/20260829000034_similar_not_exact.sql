-- 0034 · Suggestion reasons say "similar to you", never the exact value.
-- GLO-167. Sean's ruling, Aug 29, answering the §3.4-vs-§3.5 question on
-- GLO-122:
--
--   "no we won't tell others a users exact skin details, but we may say this
--    user has similar skin/preferences etc to you if they choose to be public
--    and share that"
--
-- A refinement of 0032, and a STRICTER one. 0032 gated the skin reason on
-- profile_badges.show_skin_type — that is "if they choose to be public and
-- share that", and it stays. What changes is the sentence: 0032 rendered
-- 'also has combo skin', which names the value. It now renders
-- 'similar skin to yours', which does not.
--
-- So the requirement is now BOTH: the opt-in gate AND no exact value. Not one
-- in exchange for the other.
--
-- This does not weaken domain.md §5. "The match is the disclosure" is exactly
-- why the gate cannot be traded away for vaguer wording — a viewer who knows
-- their own skin type learns the candidate's either way. Vaguer wording is
-- required in ADDITION to consent, because there is a difference between
-- "someone who opted in is shown to be similar to you" and "their profile row
-- is quoted at strangers."
--
-- THE ANCHOR REASON IS UNCHANGED and still names the shade. The ruling says
-- "exact skin details"; a shade someone wears is a product they own, not a
-- skin attribute, and tech/02 §3.4 describes show_anchor as publishing "the
-- user's own choice to wear their shade on their profile." A card whose whole
-- contract is a named reason cannot say "wears a foundation". Flagged on
-- GLO-167 as an interpretation rather than assumed silently.
--
-- Only the skin_reasons CTE changes. The rest is 0032 verbatim, restated
-- because CREATE OR REPLACE FUNCTION takes a whole body.

create or replace function suggested_people(p_limit int default 10)
returns table (
    user_id      uuid,
    handle       text,
    display_name text,
    reason       text,
    reason_kind  text,
    n            int)
language sql stable security definer set search_path = public as $$
with me as (
    select (select auth.uid()) as uid
),
my_anchors as (
    select a.variant_id, a.fit
      from user_shade_anchor a, me
     where a.user_id = me.uid
),
my_profile as (
    select p.skin_type, p.domains
      from profiles p, me
     where p.user_id = me.uid
),
candidates as (
    select h.user_id, h.handle, pr.display_name, pr.skin_type, pr.domains,
           coalesce(bg.show_anchor, false)    as show_anchor,
           coalesce(bg.show_skin_type, false) as show_skin_type,
           (select count(*)::int from rank_positions rp where rp.user_id = h.user_id) as ranked_n
      from handles h
      join privacy_scopes s  on s.user_id = h.user_id
      join profiles pr       on pr.user_id = h.user_id
      left join profile_badges bg on bg.user_id = h.user_id
         , me
     where me.uid is not null
       and s.discoverable
       and h.user_id <> me.uid
       and not is_minor_user(h.user_id)
       and not is_blocked(me.uid, h.user_id)
       and not exists (select 1 from mutes mu
                        where mu.user_id = me.uid and mu.muted_id = h.user_id)
       and not exists (select 1 from follows f
                        where f.follower_id = me.uid and f.followed_id = h.user_id)
),
anchor_reasons as (
    select c.user_id, c.handle, c.display_name,
           'wears ' || b.name || ' ' || v.shade_code as reason,
           'anchor' as reason_kind,
           c.ranked_n as n,
           1 as rank
      from candidates c
      join user_shade_anchor a on a.user_id = c.user_id
      join my_anchors ma       on ma.variant_id = a.variant_id and ma.fit = a.fit
      join variants v          on v.id = a.variant_id
      join products p          on p.id = v.product_id
      join brands b            on b.id = p.brand_id
     where c.show_anchor
       and v.shade_code is not null
),
skin_reasons as (
    select c.user_id, c.handle, c.display_name,
           -- The ruling, in one line. The candidate's skin_type is what the
           -- JOIN matches on; it is never what the sentence contains. A future
           -- edit that interpolates c.skin_type back in here is caught by the
           -- test asserting no reason string contains a skin-type value.
           'similar skin to yours' as reason,
           'skin_type' as reason_kind,
           c.ranked_n as n,
           2 as rank
      from candidates c, my_profile mp
     where c.show_skin_type
       and c.skin_type is not null
       and c.skin_type = mp.skin_type
       and c.domains && mp.domains
)
select s.user_id, s.handle, s.display_name, s.reason, s.reason_kind, s.n
  from (
        select distinct on (u.user_id) u.*
          from (select * from anchor_reasons union all select * from skin_reasons) u
         order by u.user_id, u.rank, u.n desc
       ) s
 order by s.rank, s.n desc, s.handle
 limit least(coalesce(p_limit, 10), 50);
$$;

comment on function suggested_people(int) is
    'People to follow, each with a named reason carrying its n. Every exclusion is a WHERE clause (GLO-122). Reasons are gated on profile_badges AND never state an exact skin value (GLO-167, Sean Aug 29): consent and non-disclosure are both required, not traded against each other.';
