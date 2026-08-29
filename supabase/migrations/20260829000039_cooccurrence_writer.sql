-- 0039 · shade_cooccurrence gets its writer — the last of 0004's three.
-- GLO-175, after 0036/0037 (variant stats, GLO-157) and 0038 (rank scores,
-- GLO-174). With this, every aggregate 0004 created is actually written.
--
-- The crosswalk, exactly as tech/01 words it: "a self-join, never parsed
-- shade names." n = users who wear both anchor variants. Display-only in V1
-- (§8): "people who wear fenty 240 also wear …", thresholded on n at render
-- with the n shown — and never "your match." The render threshold belongs
-- to the surface ticket when that UI is built; the table stores every pair
-- including n=1, the same render-gates-data-doesn't principle as 0036/0038.
--
-- THE DEDUPE IS LOAD-BEARING: user_shade_anchor yields one row per fit AXIS
-- (0009 — a depth answer and an undertone answer are two item_fits rows), so
-- a user with both answers on one anchor appears twice in the view. Without
-- distinct (user_id, variant_id) first, the self-join would inflate n for
-- exactly the users who gave the most complete fit answers.

create or replace function refresh_shade_cooccurrence() returns void
language sql
security definer
set search_path = public
as $$
delete from shade_cooccurrence;
insert into shade_cooccurrence (variant_a, variant_b, n, refreshed_at)
with anchors as (
    select distinct user_id, variant_id from user_shade_anchor
)
select a.variant_id, b.variant_id, count(*)::int, now()
from anchors a
join anchors b on b.user_id = a.user_id
             and a.variant_id < b.variant_id
group by a.variant_id, b.variant_id;
$$;

revoke execute on function refresh_shade_cooccurrence() from public, anon, authenticated;
grant execute on function refresh_shade_cooccurrence() to service_role;

-- hourly, off-minute, not contending with 0036's :43 or 0038's :53
select cron.schedule('cooccurrence-hourly', '23 * * * *',
    $$select refresh_shade_cooccurrence()$$);
