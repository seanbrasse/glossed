-- 0035 · affinity_for_user(): the taste engine's one function.
-- GLO-169. docs/tech/07 §2–3 is the design; tech/01 §8 is the spec it
-- implements. Validated as a prototype against this schema before it was a
-- migration (rolled-back fixture run, Aug 29).
--
-- PERSISTS NOTHING, ON PURPOSE. domain.md §5 classifies inferred taste with
-- its stated equivalents, so a materialized vector would be Regulated data
-- at rest — retention rules, deletion rights, the lot. Computed on read, the
-- vector inherits all of that from the rows it reads and administers none of
-- it. If scale ever forces materialization, that is a §6 retention decision
-- taken deliberately, not a cache someone adds (tech/07 §3).
--
-- SECURITY INVOKER, deliberately — the opposite choice from 0030's
-- refresh_trending(). That function crosses an identity boundary (reads
-- identifier-carrying rows, writes an identifier-free aggregate) and so runs
-- as service_role. This one must never cross it: it reads only the caller's
-- own rows, and invoker + RLS makes that a property of the database rather
-- than a promise in a WHERE clause. auth.uid() appears anyway because "my
-- rows" needs a value, but RLS would hold even without it.
--
-- THE WEIGHTS ENCODE tech/01 §8's ORDERING, NOT MEASURED TRUTH:
--   rank        ±3.0 · (2r−1)   the strongest statement a user makes; signed,
--                               so bottom-of-list is negative evidence.
--                               Single-item lists contribute NOTHING (r is
--                               undefined — same rule as aggregation §3).
--   dislike+chip −2.0           a dislike with a stated reason outranks
--   like+chip    +1.5           any like ("dislike+chip above like")
--   bare like    ±1.0
--   ownership    +0.25          weak by design; owning ≠ endorsing
--   want_to_try  excluded       unworn is not evidence (GLO-145's rule)
-- Chips of valence OPPOSITE to like_state are deliberately not counted yet —
-- a mixed verdict ("lasted all day" but creased) is real and is tuning work,
-- not launch work. Constants live inline in ONE place below, the
-- min_n_trending() shape: tuning is a one-line change. BACKLOG carries the
-- debt alongside k≈10.
--
-- Shrinkage: w = n/(n+10) toward the cohort mean — which is 0 (neutral)
-- until agg_variant_stats has a writer (GLO-157). The formula does not
-- change when the target arrives; only the 0 does. w is also the confidence
-- meter the client renders (ConfidenceMeter have/need), and n_signals is the
-- receipt's n — every claim says what it stands on (domain.md §5).

create function affinity_for_user(p_domain domain_enum default null)
returns table (
    attribute_chip_id uuid,
    label text,
    raw_score numeric,
    n_signals int,
    w numeric,
    shrunk_score numeric
)
language sql
stable
security invoker
as $$
with my_items as (
    select ui.id, v.product_id, ui.like_state
    from user_items ui
    join variants v on v.id = ui.variant_id
    join products p on p.id = v.product_id
    where ui.user_id = auth.uid()
      and ui.deleted_at is null
      and ui.status <> 'want_to_try'
      and (p_domain is null or p.domain = p_domain)
),
chip_valence as (
    select ic.user_item_id,
           count(*) filter (where ec.valence = 'like')    as like_chips,
           count(*) filter (where ec.valence = 'dislike') as dislike_chips
    from item_chips ic
    join experience_chips ec on ec.id = ic.experience_chip_id
    where ic.user_id = auth.uid()
    group by ic.user_item_id
),
ranked as (
    -- Percentile within the user's own list, per (category, scope bucket).
    -- nullif zeroes out single-item lists: len−1 = 0 → null → no term.
    select rp.user_item_id,
           1.0 - (rp.position - 1)::numeric
               / nullif(count(*) over (partition by rp.category_id, rp.scope_key) - 1, 0)
               as pct
    from rank_positions rp
    where rp.user_id = auth.uid()
),
item_weight as (
    select mi.product_id,
           0.25                                                             -- ownership
         + case
               when mi.like_state = 1  and coalesce(cv.like_chips, 0)    > 0 then  1.5
               when mi.like_state = 1                                        then  1.0
               when mi.like_state = -1 and coalesce(cv.dislike_chips, 0) > 0 then -2.0
               when mi.like_state = -1                                       then -1.0
               else 0
           end
         + coalesce(3.0 * (2 * r.pct - 1), 0)                               -- rank, highest
           as weight
    from my_items mi
    left join chip_valence cv on cv.user_item_id = mi.id
    left join ranked r        on r.user_item_id  = mi.id
)
select ac.id                                              as attribute_chip_id,
       ac.label,
       avg(iw.weight)                                     as raw_score,
       count(*)::int                                      as n_signals,
       count(*)::numeric / (count(*) + 10)                as w,
       avg(iw.weight) * count(*)::numeric / (count(*) + 10) as shrunk_score
from item_weight iw
join product_attributes pa on pa.product_id = iw.product_id
join attribute_chips ac    on ac.id = pa.attribute_chip_id
group by ac.id, ac.label
order by shrunk_score desc
$$;

-- Anon has no shelf, so anon has no taste — and silence is a grant (0030's
-- rule), so the revoke is explicit.
revoke all on function affinity_for_user(domain_enum) from public, anon;
grant execute on function affinity_for_user(domain_enum) to authenticated;
