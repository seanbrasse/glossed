-- 0032 · suggested_people() — every exclusion in the query.
-- GLO-122. docs/tech/02 §3.5.
--
-- Depends on 0031. §3.5 said this RPC must not ship before GLO-145's view fix,
-- because its whole contract is a NAMED REASON said to a stranger about
-- someone — "wears fenty 240" — and the unfixed view would let that sentence
-- be false about a product the person never wore. 0031 landed, so this reads
-- user_shade_anchor directly and does NOT filter status itself. If you are
-- reading this because the view broke again: the fix belongs in the view.
--
-- ---------------------------------------------------------------------------
-- A CONFLICT BETWEEN §3.4 AND §3.5, RESOLVED IN §3.4's FAVOUR.
--
-- §3.5 specifies two reason kinds: a shared anchor variant, and same skin type
-- as the weaker fallback. Both are Regulated data (domain.md §5) about the
-- CANDIDATE, published to a stranger.
--
-- §3.4 states the invariant that settles it: "the badges are the only path by
-- which skin_type, the anchor variant, and hair_pattern reach another human."
-- Written as specified, this RPC would be a SECOND path — and one with no
-- opt-in at all, publishing to strangers exactly what profile_badges exists to
-- make voluntary. All three flags default false, so it would publish data from
-- people who had actively not chosen to.
--
-- So each reason is gated on the badge that governs the same fact:
--   anchor reason    requires profile_badges.show_anchor
--   skin-type reason requires profile_badges.show_skin_type
--
-- Note that phrasing cannot dodge this. "Also has your skin type", with the
-- value omitted, still discloses the candidate's skin type to a viewer who
-- knows their own — the MATCH is the disclosure, not the string. There is no
-- wording that makes an ungated version safe.
--
-- CONSEQUENCE, WHICH IS A PRODUCT FACT AND NOT A BUG: badges default false, so
-- this surface returns nothing until people turn them on. That is what
-- "opt-in" means. An empty suggestions list is the correct behaviour for a
-- population that has not consented to being suggested, and it is a far better
-- failure than publishing a stranger's shade without asking.
-- ---------------------------------------------------------------------------

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
-- The viewer's own worn anchor shades. Post-0031 this cannot contain a
-- never-worn product.
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
-- EVERY EXCLUSION IS HERE, IN THE QUERY. domain.md §4: authorization lives in
-- the service layer, never the UI — hiding a button is presentation.
--
-- This function is security definer, so the RLS that would otherwise hide most
-- of these rows is not helping. That makes each exclusion load-bearing rather
-- than belt-and-braces, which is why each one has its own assertion.
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
       and s.discoverable                                    -- surfacing is opt-in (§1.3)
       and h.user_id <> me.uid                               -- not yourself
       and not is_minor_user(h.user_id)                      -- minors are never suggested
       and not is_blocked(me.uid, h.user_id)                 -- either direction
       and not exists (select 1 from mutes mu
                        where mu.user_id = me.uid and mu.muted_id = h.user_id)
       and not exists (select 1 from follows f
                        where f.follower_id = me.uid and f.followed_id = h.user_id)
),
-- Reason 1: a shared anchor variant with an AGREEING fit. Two people who wear
-- the same shade and disagree about whether it fits are not evidence for each
-- other, so the fit has to match, not merely exist.
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
     where c.show_anchor            -- §3.4: the badge is the only path
       and v.shade_code is not null -- a reason with no shade names nothing
),
-- Reason 2: the weaker fallback. Same skin type, and at least one shared
-- domain so the suggestion is about something they both do.
skin_reasons as (
    select c.user_id, c.handle, c.display_name,
           'also has ' || c.skin_type || ' skin' as reason,
           'skin_type' as reason_kind,
           c.ranked_n as n,
           2 as rank
      from candidates c, my_profile mp
     where c.show_skin_type         -- §3.4: the badge is the only path
       and c.skin_type is not null
       and c.skin_type = mp.skin_type
       and c.domains && mp.domains
)
-- One row per person, strongest reason wins. distinct on is what enforces
-- "never a three-avatar grid": a person appears once, with one named reason.
select s.user_id, s.handle, s.display_name, s.reason, s.reason_kind, s.n
  from (
        select distinct on (u.user_id) u.*
          from (select * from anchor_reasons union all select * from skin_reasons) u
         order by u.user_id, u.rank, u.n desc
       ) s
 order by s.rank, s.n desc, s.handle
 limit least(coalesce(p_limit, 10), 50);
$$;

-- A SUGGESTION WITH NO REASON DOES NOT RENDER, and that is enforced here
-- rather than by a client checking for nil. Both reason branches are inner
-- joins onto their evidence, so a candidate who matches nothing produces no
-- row at all — there is no code path that emits a person with an empty reason.
comment on function suggested_people(int) is
    'People to follow, each with a named reason carrying its n. Every exclusion is a WHERE clause (GLO-122). Reasons are gated on profile_badges: §3.4 makes the badges the only path by which Regulated data reaches another human, and this RPC is not a second one.';

revoke execute on function suggested_people(int) from public, anon;
grant execute on function suggested_people(int) to authenticated;
