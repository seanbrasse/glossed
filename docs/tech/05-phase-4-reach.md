# Phase 4 — The Reach (needs scale or funding)

None of this shapes earlier decisions beyond two standing rules already enforced in schema and jobs: **gifted entries never aggregate** and **ranking/trending placement is never for sale**. Order of operations: users → data → creators → brands.

---

## 1. Verified brand pages

- `brand_accounts(brand_id, org contacts, verification state)` — DNS or LinkedIn-mediated verification, manual at first.
- Brand pages: launch calendar (feed-derived new SKUs), structured product data corrections (a privileged lane into the merge queue — reviewer-approved, audited, never touching chips/rankings), aggregate insights **above min-n only** and never per-user.

## 2. Targeted sampling

- The product brands actually want: "send samples to 500 users whose anchors sit in shades X–Y, oily skin, who own a competitor's foundation."
- Privacy architecture: **we never sell or hand over the audience.** Brands define criteria → we count → opted-in users (`sampling_optins`) get the offer in-app → acceptors share a shipping address *per campaign* with the fulfillment step; brand receives counts + anonymized aggregate outcomes (chips/fit distribution above min-n), never identities.
- Sampled items auto-carry the gifted flag → excluded from aggregates by the existing rule.

## 3. Funded giveaways + paid creator campaigns

- Giveaways ride the Phase-3 points system (entry = points threshold), brand-funded, disclosed.
- Paid creator campaigns live entirely in curation surfaces (`curated_shelves` with sponsor labels). Rankings untouched — schema has no path from payment to rank, keep it that way.

## 4. Native video hosting

- Only if oEmbed friction proves limiting. If built: HLS via a managed pipeline (Cloudflare Stream fits the R2 posture), same moderation gate as photos plus sampled human review; ~10× moderation load is the real cost — budget a second reviewer before this ships.

## 5. Community catalog cleanup

- Reach destination of the merge queue: trusted contributors (points ≥ threshold + accuracy record) get a review lane for near-match adjudication; reviewer approves batches. Same three verbs, same audit trail; never structural access.

## 6. Scale posture (only when these hurt)

- Supabase: upgrade tier / read replicas before re-platforming; aggregates → incremental refresh; feed diffs → partitioned staging tables.
- Feed fan-out stays on-read until follow graphs make it slow; then per-user timeline cache (Redis) — an optimization, not a redesign.
- Image derivatives → Cloudflare Images or on-the-fly resizing worker in front of R2.

## 7. Definition of done (first Reach slice)

- [ ] One verified brand page live with a structured-data correction lane
- [ ] One sampling campaign end-to-end with the privacy architecture above
- [ ] Second reviewer hired/contracted before native video or community cleanup unlock
