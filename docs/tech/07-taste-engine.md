# 07 · The taste engine

The layer that learns what a user likes from what we know about them and how
they describe their experiences — and turns it into product suggestions now
and people suggestions later. This document is the architecture; tech/01 §8
remains the spec it implements, and the Aug 29 rulings (domain.md §1 Profile,
§5) are its constraints.

**One sentence:** onboarding seeds a prior, every log is evidence, the engine
is a single SQL function that turns that evidence into a scored attribute
vector with a receipt on every number — and it stores nothing.

---

## 1. Governing rules (all pre-decided, none new here)

| rule | source | consequence for the engine |
|---|---|---|
| Profile = prior + evidence ledger; evidence wins | domain.md §1 | the vector is *derived*, never authored; no field of it is user-editable except by logging |
| Chips are relative facts; claims name whose n | domain.md §5, research §4 | every output row carries `n_signals` and `w`; rendered claims say what they stand on |
| Inferred values are Regulated like stated ones | domain.md §5 | **compute on read, store nothing.** A persisted vector is Regulated data at rest — retention, deletion, never-in-logs. A computed one inherits all of that from the rows it reads. No new table. |
| The match is the disclosure | domain.md §5 (GLO-163) | when this engine feeds *people* suggestions (Phase 3), a taste-match badge about an identifiable person is gated on their opt-in, however the string is phrased |
| Three profiles, kept separate | tech/01 §8 | body facts **filter**, attribute affinity **ranks**, aesthetic taste **diversifies**. This engine is the middle one; it must not absorb the other two |
| No behavioral surveillance | tech/01 §8 | dwell/scroll never enter; searches are intent-only; saves weak |

## 2. The signal model

Per owned item, one weight; per attribute, the average of its items' weights,
shrunk by confidence. Weights ordered exactly as tech/01 §8 orders them:

| signal | weight | why |
|---|---|---|
| rank position | `3.0 × (2r − 1)`, r = percentile | the strongest statement a user makes; signed, so bottom-of-list is negative evidence. Single-item lists contribute **nothing** (r undefined — same rule as aggregation §3) |
| dislike + experience chip | −2.0 | a dislike with a stated reason outranks any like — "broke me out" is the most actionable signal in the system |
| like + experience chip | +1.5 | a like with a reason beats a bare like |
| bare like / dislike | +1.0 / −1.0 | |
| ownership | +0.25 | weak by design; owning ≠ endorsing |
| `want_to_try` | excluded | unworn is not evidence — the same rule fit capture follows (GLO-145) |
| *reserved:* save / wishlist | +0.5 | arrives with the discover page; explicit intent, still weak (spec: "saves weak") |
| *reserved:* dismissal / "not for me" | −0.75 | arrives with discover; the Phase-3 blend already subtracts dismissed — this is its signal-side twin |
| *reserved:* search → product opened | intent-only | arrives with discover; scopes candidates, never scores them (spec: "searches intent-only") |
| *reserved:* feed actions — follows, look saves | diversification layer only | arrives with the feed (Phase 2); aesthetic taste diversifies, it does not rank (§1) |

**The table is a registry, and that is the scalability design.** Every signal
source reduces to the same triple — *(product, weight term, provenance)* —
and the function is a sum of per-source terms over `(user, product)`. Adding
a discover or feed signal when those surfaces exist is adding one term and
one weight to this table and one CTE to the function: no schema change, no
new engine, no rescore job. What we know about the user today and what we
learn from them later differ only in which rows exist.

Shrinkage: `w = n_signals / (n_signals + k)`, k = 10, toward the **cohort
mean** — which is 0 (neutral) until `agg_variant_stats` has a writer
(GLO-157). The formula does not change when the cohort mean arrives; only the
target does. `w` is also the confidence meter, rendered honestly
(`ConfidenceMeter have/need` — same number, no separate bookkeeping).

Constants live in the one SQL function, as constant expressions in one place,
following the `min_n_trending()` precedent: tuning is a one-line change, and
none of these numbers is validated yet — they encode the spec's *ordering*,
not measured truth. BACKLOG tracks the tuning debt alongside k ≈ 10.

Validated against the live schema (rolled-back fixture run, Aug 29): a
disliked-with-chip product's attribute lands at −1.75 raw, a liked one at
+1.25, mere ownership at +0.25, and n = 1 shrinks everything to ±0.16 — a
cold profile makes almost no claims, which is correct.

## 3. Shape: one RPC, computed on read

`affinity_for_user(p_domain domain_enum default null)` →
`(attribute_chip_id, label, raw_score, n_signals, w, shrunk_score)`

- **Security invoker**, not definer: it reads only the caller's own rows and
  RLS already guarantees that. `authenticated` only; anon has no shelf.
- Reads: `user_items` (status, like_state) × `item_chips`/`experience_chips`
  (valence) × `rank_positions` (percentile) × `product_attributes` (the
  dimensions). Nothing else. Every input already carries deletion semantics;
  the vector inherits them by existing only at query time.
- Cost: a user's own shelf is tens of rows; this is a sub-millisecond query.
  Discover and feed signals raise the row count, not the shape: every source
  aggregates to one row per `(user, product)` before weighting, so the read
  stays bounded by shelf-adjacent size, not by event volume. The pressure
  valve, if scale ever demands one, is a per-user materialization — and that
  table is Regulated at rest and gets §6 retention treatment, **decided then,
  not drifted into**.
- **Taste signals come from domain rows only — never the analytics stream.**
  A save is a row the user owns and can delete; an `events` row is telemetry
  with its own classification and rules of use (tech/06). The discover page
  will emit both kinds; the engine reads only the first. This line is what
  keeps "we learn from your feed" from quietly becoming behavioral
  surveillance — the user's ledger feeds the engine, their telemetry never
  does.
- Receipts fall out of the shape: "8 of your top 10 are fragrance-free" is a
  render of one output row (`label`, `n_signals`, `w`) — gated on `w` per §8,
  and it names its basis per the relative-facts rule.

## 4. Feeder reality (measured Aug 29, local)

The engine's correctness and its usefulness are different questions. The
function is buildable today; its food mostly is not:

| feeder | state | path to live |
|---|---|---|
| user signals — items, like_state, chips, ranks | **live** (171-chip vocabulary, 22/22 categories; chip editor live) | growing with use |
| `product_attributes` — the vector's dimensions | **1 of 3,204 products.** Vocabulary: 4 rows. | `inci_raw` exists for 683 products; **zero parsed; no enrichment script exists** (tech/01 §4 step 3 was specified, never built). One Deno script + an attribute vocabulary away |
| `agg_*` cohort means (Stage 0 + shrinkage target) | **no writer** (GLO-157) | writer must be cohort-shaped from day one; min-n before render |
| variant structured facts (shade_hex, strength_pct, price) | populated | derivable attributes ("finish", "strength band") — later, same pipeline |

Build order that follows: **(1)** the RPC — correct against empty feeders,
returns honest n = 0; **(2)** the INCI parse feeder — 683 products of
dimensions, the single highest-leverage unlock; **(3)** GLO-157's writer —
Stage 0 population stats and a real shrinkage target; **(4)** the client
surface, reading receipts. Each is independently shippable and none blocks
another's correctness — only its usefulness.

## 5. People suggestions (Phase 3, designed-for now)

The same vector is the similarity basis for neighbors: two users' shrunk
vectors, cosine-ish, computed per domain and blended (tech/04). Nothing about
that changes this engine — which is the point of building it as one function
with a stable output shape. Constraints already decided: neighbor internals
stay **opaque** to users; any *rendered* taste-match about an identifiable
person is a disclosure and rides the badge opt-in (§5); cohort claims about
groups name their n. `suggested_people` (GLO-122) is the template: the RPC
can exist, the render is what's gated.

## 6. What this engine must never do

Consolidated from rules above because a future session will be tempted:
no persisted per-user vector without a §6 retention decision; no dwell/scroll
signals; no body-fact *ranking* (facts filter, they never score); no age →
concern mapping; no persona labels ("glowy girl") — receipts only; no
recommendation rendered without its n and never below min-n once cohort
data exists; no taste signal read from the `events` stream — a signal source
that wants in comes as a domain row with an owner, a weight in §2's registry,
and deletion semantics, or it does not come in at all.
