-- The weekly fill list. GLO-14 PR 4; PRD §15.
--
-- "Every empty search names exactly which product is missing, weighted by
-- demand. Log, rank, fill the top 50 weekly. Catalog work becomes a
-- prioritized queue instead of an infinite problem."
--
-- The intake half already runs (record_failed_search, 0005; the search rung
-- and its guards — GLO-55/57/58 — keep the queue honest). This is the read
-- half: one query, run weekly, its top rows are the week's catalog work.
--
-- Completeness is % of searches that find the product, never % of the world's
-- products held — so the same query reports the hit-rate denominator the
-- snapshot decision reads (buy only when <85% of first searches hit).

-- The fill list: unresolved misses, demand-ranked, recency-broken.
select
    query,
    domain,
    user_count,
    last_seen::date as last_seen,
    round(user_count::numeric / greatest(1, (current_date - last_seen::date + 1)), 2)
        as demand_per_day
from failed_searches
where resolved_product_id is null
order by user_count desc, last_seen desc
limit 50;

-- The resolution report: what last week's fill work actually closed.
-- (run with \echo or as its own statement; kept in one file so the weekly
-- sit-down is one \i)
select
    count(*) filter (where resolved_product_id is not null) as resolved,
    count(*) filter (where resolved_product_id is null) as open,
    coalesce(sum(user_count) filter (where resolved_product_id is null), 0) as unmet_demand
from failed_searches;
