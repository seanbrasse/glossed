# Phase 3 — The Depth Layer (retain)

Still not a revenue phase. Scope: price history + deal alerts · recommendations v2 (neighbor-based, Kendall tau) · ingredient conflict warnings · creator cohort operations.

---

## 1. Price history + deal alerts (free regardless)

```sql
price_points(variant_id, retailer, price_cents, currency, in_stock, seen_at)   -- appended by the nightly feed diff
price_alerts(id, user_id, variant_id, kind any_drop|threshold, threshold_cents null, active, last_fired_at)
```

- The feed diff already sees prices daily — history is a write-through, zero new acquisition cost. Chart on the product page (sparkline, mono labels).
- Alerts: nightly job compares last two points per watched variant → APNs push. Push infra arrives here: APNs key, provisioning renewal dates calendared with an owner (Handbook §12), notification preferences + per-kind opt-out from day one, quiet by default.
- Wishlist/want_to_try items get a one-tap "watch the price."
- Affiliate links remain a kept-warm switch (`Later`), not flipped here.

## 2. Recommendations v2 — neighbors by rank correlation

- **Hard filter on body facts first** (unchanged, always).
- Neighbor score = **Kendall tau over shared ranked products**, not shelf overlap: two people *ordering* the same ten products the same way means a lot; owning them means little. Computed pairwise within body-fact cohorts (cohorting keeps the pair space small); cached in `user_neighbors(user_id, neighbor_id, tau, shared_n, refreshed_at)`, refreshed weekly, `shared_n ≥ 5` to count.
- Recs blend: candidate set from neighbors' top-percentile items (minus owned/ranked/dismissed) → attribute-affinity rank → taste diversification + the labeled exploration slot. Recency decay on signals; a forked reformulation resets that product's history.
- Neighbor graph stays **opaque** to users (gaming + no user benefit); body facts and affinity stay visible with receipts and an adjust control.
- Cross-domain transfer: affinity vector already spans domains (fragrance-avoidance transfers to haircare free); neighbors computed per domain but blended.
- Evaluation before rollout: offline replay (hold out last-ranked items, measure hit-rate@k vs Stage-1 baseline); ship only on a win.

## 3. Ingredient conflict warnings

- Static pairwise rule table curated from published derm guidance (`inci_conflicts(active_a, active_b, severity, note, source_url)`) — e.g. retinoid × BHA same-slot, benzoyl peroxide × vitamin C. Sources cited in-row; no rule without one.
- Surfaces: routine editor (same-slot conflicts flagged inline) and product page ("pairs poorly with your PM routine — 2% BHA · week 14"). Community chips add receipts where they exist.
- **Caution, not verdict** phrasing everywhere; never medical advice; no comedogenicity.

## 4. Creator cohort ops

- Hand-recruited cohort (from Phase 2 outreach) gets: profile flair, early features, a monthly office-hours loop. Contribution points system v1 (PRD §14): points for swatches/reviews/chips/catalog fixes/tagged looks, **paid in status only** (badges, flair, "top swatcher for tone 7"), weighted by usefulness (helpfulness marks + uniqueness), not volume.
- `contribution_events(user_id, kind, weight, subject_id, at)` + weekly rollup to badges. Giveaways stay `Reach`.

## 5. Ops maturity in this phase

- Recommendations + neighbor jobs move to scheduled Edge Functions with dead-letter visibility; aggregate refresh SLOs.
- QA jams at regular cadence with rotating charters (permissions grid, timezone boundaries, poor connectivity, oversized imports).
- Cost sheet review monthly; Supabase tier + Twilio + Claude + R2 + Sentry lines; caps re-checked.

## 6. Definition of done

- [ ] Price history charts + alerts with push infra, prefs, and renewal calendar
- [ ] Neighbor pipeline live behind flag, offline-eval win recorded, exploration slot labeled
- [ ] Conflict table sourced + surfaced in routines and product pages with caution phrasing
- [ ] Points/badges live; creator cohort ≥ 20 active
