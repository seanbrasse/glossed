# Phase 1 — The Journal

Single-player + anonymous aggregates. **No content from any user is visible to any other user.** Four domains. Ship here.

Scope (PRD §17 + design kit): onboarding (anchor-first, birthday, hair type if haircare) · catalog on the free stack + submission ladder with personal scope · shelf via search / barcode / photo / share-in · import (Notes/CSV/screenshot) · export CSV · logging + chips + fit capture + wear-in gating · pairwise ranking (face-offs) · private collections · leaderboards (always showing n, min 5 face-offs per scope) · recommendations Stage 0–1 · own profile with confidence meter · returning-user login.

---

## 1. Database schema (Postgres / Supabase)

Naming: snake_case, plural tables, `created_at`/`updated_at` everywhere, soft delete via `deleted_at`. All user-scoped tables carry `user_id uuid references auth.users` + RLS `user_id = auth.uid()`.

### 1.1 Catalog (public read, service write)

```sql
brands(id, name, normalized_name unique, aliases text[], source, created_at)
categories(id, domain domain_enum, parent_id, slug unique, label,
           wear_in_days int default 0,          -- 0=immediate · moisturizer 14 · actives 56 · retinoids/pigment 84
           is_anchor bool default false,        -- foundation, concealer, tinted moisturizer, skin tint, powder, bb/cc
           rank_unlock_min int default 3)
products(id, brand_id, category_id, domain, name, normalized_name, benefit_line,
         scope catalog_scope default 'canonical',   -- personal | submitted | canonical
         created_by uuid null,                      -- set for personal/submitted
         inci_raw text, inci_parsed jsonb,          -- {actives:[], irritants:[], flags:{fragrance_free,…}}
         forked_from uuid null, merged_into uuid null, delisted_at,
         source, last_verified, created_at, updated_at)
variants(id, product_id, kind variant_kind,         -- shade | formulation | concentration | default
         shade_code, shade_hex, size_ml numeric, strength_pct numeric,
         gtin text,                                  -- the universal join key; unique where not null
         height_mm numeric, width_mm numeric,        -- real-dimension shelf scaling
         price_cents int, currency, availability, source, last_verified)
variant_images(id, variant_id, kind image_kind,      -- catalog | typographic (user cutouts live on user_items)
               r2_key, width, height, image_source, last_fetched)
attribute_chips(id, domain, slug unique, label)      -- derived-only vocabulary (§5)
product_attributes(product_id, attribute_chip_id, source, primary key(product_id, attribute_chip_id))
experience_chips(id, domain, category_id null, slug unique, label, valence like|dislike)
                                                     -- fixed launch vocab + weekly-promoted write-ins
```

Indexes: `gin (normalized_name gin_trgm_ops)` on brands/products; FTS `tsvector` on products (name + brand + category + attribute labels); btree on `variants.gtin`.

Personal-scope isolation is **structural**: RLS on `products` = `scope = 'canonical' OR created_by = auth.uid()`. A personal product physically cannot appear in another user's search or in aggregates.

### 1.2 User shelf

```sql
profiles(user_id pk, display_name, avatar_seed, timezone,
         birth_year_month char(7),               -- 'YYYY-MM'; full birthday validated at signup then discarded (domain.md §6)
         domains domain_enum[],                                              -- what-you-buy multi-select
         skin_type enum null, concerns text[] default '{}', tone_band int null,
         hair_pattern text null,        -- '1a'..'4c', asked only when haircare in domains
         climate text null, brand_affinities text[] default '{}')
user_items(id, user_id, variant_id, status item_status default 'own',        -- want_to_try|own|finished|repurchased
           acquired_on date, started_on date null,                           -- started_on drives wear-in
           note text, cutout_r2_key text null,                               -- user's own cutout, personal scope
           like_state smallint null,                                         -- -1|0|1 pre-ranking signal
           client_id uuid unique,                                            -- idempotency
           created_at, updated_at, deleted_at,
           unique(user_id, variant_id))
item_chips(id, user_id, user_item_id, experience_chip_id, week int null,     -- week required for skincare reactions
           freetext text null,                                               -- "other" write-ins → weekly vocab review
           created_at, unique(user_item_id, experience_chip_id))
item_fits(id, user_id, user_item_id unique, fit fit_enum,                    -- just_right|too_light|too_dark|too_pink|too_yellow|too_orange
          season text null, captured_at)                                     -- fit captured at log time, on every log of an anchor-category product
face_offs(id, user_id, category_id, scope_key text default 'default',        -- scoped buckets: everyday|full_glam|… later
          winner_item_id, loser_item_id, skipped bool default false,
          client_id uuid unique, created_at)                                 -- immutable log; no updates
rank_positions(user_id, category_id, scope_key, user_item_id, position int,
               primary key(user_id, category_id, scope_key, user_item_id))   -- derived, rewritten by ranking service
collections(id, user_id, title, cover_tint, created_at, deleted_at)
collection_items(collection_id, user_item_id, position, primary key(collection_id, user_item_id))
routines(id, user_id, title, slot routine_slot, started_on, …)               -- private in V1; public browse in 1.5
routine_steps(routine_id, user_item_id, position)
```

`user_shade_anchor` is a **view**: anchor-category user_items joined to item_fits — the PRD's whole schema (`user_id, variant_id, fit, season?`) falls out of log data. Anchors always overwrite the tone band for matching; the band alone never drives matching claims.

### 1.3 Aggregates (no user identifiers stored)

```sql
agg_variant_stats(variant_id, tone_band int null, skin_type text null,       -- null = all
                  owners int, fit_counts jsonb, chip_counts jsonb, refreshed_at)
agg_rank_scores(product_id, category_id, cohort_key text,                    -- 'all' | 'shade:<variant_id>' | 'hair:3b' | …
                n_face_offs int, n_users int, mean_percentile numeric, refreshed_at)
shade_cooccurrence(variant_a, variant_b, n int, refreshed_at)                -- the crosswalk: a self-join, never parsed shade names
failed_searches(id, query, domain, user_count int, last_seen, resolved_product_id null)
```

Materialized, refreshed by `pg_cron` (hourly is fine at this scale). Client reads go through security-definer RPCs that enforce **min-n or roll up** (widen category → parent, widen shade → band) and always return the n. Popularity never down-weights a shade match; range granularity (shade count in range) weights it.

### 1.4 Ops

```sql
merge_candidates(id, product_a, product_b, similarity numeric, llm_verdict jsonb,
                 state pending|auto_merged|approved|rejected, verb merge|attach_variant|fork, decided_by, decided_at)
ingest_jobs(id, kind feed_diff|snapshot_import|inci_enrich|image_fetch, payload jsonb,
            state queued|running|done|failed|dead, attempts int, last_error, run_after)
audit_records(id, actor, action, entity, entity_id, before jsonb, after jsonb, at)  -- catalog + moderation actions
```

## 2. Auth + onboarding backend

- **Providers**: Sign in with Apple (native: `AuthenticationServices` credential → `supabase.auth.signInWithIdToken(provider: .apple, token:, nonce:)`; capture `fullName` on first sign-in only) and phone OTP (`signInWithOTP(phone:)` → `verifyOTP(phone:token:type:.sms)`, Twilio Verify provider, OTP expiry raised from the 60s default to 300s, rate limits at defaults). Email/password disabled entirely.
- **Pre-signup onboarding is anonymous**: domain selection, anchor pick, hair type, palette, and the payoff all run before an account exists, held client-side; on account creation they're written in one batch. The payoff RPC (`payoff_for_variant(variant_id)`) is anonymous-callable, returns `{n_exact_shade, n_with_fit, top_products[]}` and the client shows the evidence-backed claim **only if `n_exact_shade ≥ 8`**; otherwise it renders the neutral fallback (swatches/browse, no match claim). One weak early recommendation poisons every good one after it.
- **Birthday gate**: full birthday goes to a `before user created` auth hook that rejects under-13 and returns the derived `birth_year_month`; only the year-month is persisted (the day never touches a table). `is_minor` derives from year-month, flipping on the 1st of the month after the 18th birthday could have occurred — conservative by up to one month, deliberately. 13–17 restrictions apply on Phase 1.5+ surfaces.
- **Returning users**: login path sets no onboarding state; app lands on discover. A returning user with no anchor gets the "sharpen your matches" card, not a re-quiz.
- The hero-question flow doubles as the catalog test: log `failed_searches` from the anchor picker too — a miss in the first 30s is the churn signal (metric: catalog hit rate).

## 3. Ranking: face-offs and positions

**Model**: per (user, category, scope_key) ordered list. Face-offs are the immutable input; `rank_positions` is the derived output.

- **Unlock**: category list ranks only when ≥3 items AND each skincare/haircare item is past `categories.wear_in_days` from its `started_on` (per-item: unranked items can exist in a ranked category as "in wear-in · week N"; a nudge fires when the window elapses).
- **Insertion (Beli-style binary)**: new item enters with bounds `[lo, hi]` over the current list. Each face-off compares against the midpoint item; win → `hi = mid−1`, loss → `lo = mid+1`; converges in ⌈log₂ n⌉ comparisons, capped at 4 (list ≤ 15 resolves fully; longer lists insert at the unresolved midpoint and refine on later face-offs). "Too close to call" (skip) recorded, insertion at midpoint.
- **Consistency**: later face-offs can contradict positions; resolve by moving the loser/winner minimally (adjacent transposition toward the observed result). No Elo, no scores — the list is the truth the user can drag later if we ever allow it.
- Runs client-side in `Ranking` feature against local list, persists face_offs + full new position set in one RPC (`apply_face_off_session`) transactionally.

**Aggregation** (the leaderboard input): per user per category, an item's percentile = `1 − (position−1)/(list_len−1)` (single-item lists contribute nothing). `agg_rank_scores.mean_percentile` = mean over users in the cohort, `n_face_offs` = total face-offs touching the product in-cohort. **Render rule: a row needs ≥5 face-offs in the scope, else it shows "not enough face-offs yet · k of 5"** (design decision). Lowest-ranked leaderboard = same data ascending, with the dislike-chip reasons.

Cohorts for V1: `all`, `shade:<anchor variant>` ("your shade" = users sharing that exact anchor variant with agreeing fit), `hair:<pattern>` for haircare. Fragrance: `all` only, face-off ranked, no skin axis — the shelf says so.

## 4. Catalog pipeline

**Architecture in one line (PRD §15): licensed snapshot backfills once, retailer feeds are the heartbeat, users are the tail. Steady-state cost $0, nothing metered per user.**

1. **Spine — affiliate feeds** (Sephora/Ulta/Sally via Rakuten/Impact publisher accounts): nightly `feed_diff` job downloads feed → normalize → upsert by GTIN (fallback: brand FK + trigram-normalized name) → new SKUs, price/availability updates, delistings (`delisted_at`, never delete). New launches arrive the day they're purchasable.
2. **Backfill — licensed snapshot** (180k products, INCI dictionary, GTIN, images): one-time import into our Postgres. Self-hosted; never their per-call API. Bought **only when** free-stack hit rate says to (<85% of first searches finding their product).
3. **Enrichment — INCI parse**: per product, once, cached forever: INCI API (free 20k req/mo) + Open Beauty Facts → `inci_parsed` + `product_attributes`. Reformulation detection = string compare of `inci_raw` on feed refresh → mismatch queues a **fork** (old keeps chips/rankings, new starts clean, linked).
4. **Tail — users**: failed-search queue (log every empty search with count; fill top 50 weekly — completeness metric = % of searches that find the product), share-in misses, submission ladder.

**Dedupe (the real recurring cost)**: block-and-match before insert — candidates only within the same brand; compare normalized names (sizes/SPF/shades stripped) via trigram + embedding similarity; high confidence auto-rejects the insert (surfaces the match), middle band asks the user (near-match cards **with images**, "none of these" equal weight), low confidence creates. Merge queue with **three verbs** (merge / attach-as-variant / fork); LLM adjudicates within-brand pairs, one human reviews the middle band weekly. Queue depth is the canary metric — growth means thresholds are wrong, not the reviewer. Dedupe the shelf, not the catalog: a duplicate nobody logged is harmless.

**AI rule**: LLM lookups may only fill fields attributable to a real source. Empty beats fabricated.

## 5. Chips

- **Attribute chips derive only from structured fields** (INCI, feed numbers, counts) — never marketing copy. Per-domain derivations per PRD §15 (fragrance-free/silicone-free/…, actives, SPF, finish/coverage, shade-count-in-range; haircare computed from INCI since no catalog sells hair attributes). Comedogenicity ships in the data and is never surfaced.
- **Experience chips**: fixed launch vocabulary per domain/category (design-partner validated — treated as resolved; seed list from the kit: creased by 2pm, oxidized on me, lasted all day, pilled under spf, purged then cleared, broke me out, melted in heat, no crunch, weighed my hair down, crunchy cast, frizz by hour 3, flaked, scalp itch, built up, faded my color fast, fades fast, lasts 6h, …) + free-text "other" → weekly review promotes recurring write-ins.
- **Skincare reaction chips require a week stamp** ("broke me out · week 1" ≠ "· week 10"). Client derives from `started_on`, server recomputes.
- Chips are queries: chip filters compile to SQL over `item_chips`/aggregates conditioned on reviewer skin — this is the search moat ("foundations that don't oxidize, rated by people with my skin").

## 6. Ingest paths (all V1)

| Path | Implementation |
|---|---|
| Search | FTS + trigram typeahead RPC; ladder rung 1. Aggressive "did you mean" via trigram distance. |
| Barcode | `AVFoundation`/`VisionKit` scan → `variants.gtin` lookup → miss → GTIN web lookup Edge Function → still miss → ladder rung 3. Pushed as the common path. |
| Photo extract | Snap the vanity → `VNRecognizeTextRequest` OCR on-device → Claude label-matching Edge Function against catalog → user confirms per item ("is this it?"). Bulk mode for first shelf dump. |
| Share-in | iOS Share Extension: Sephora/Ulta URLs parse to SKU+shade (URL patterns + page meta via Edge Function); TikTok/Reels → caption + OCR → candidates → confirm in-app. Extension writes to App Group queue; app resolves on next open. The retention feature, not a nice-to-have. |
| Import | Paste/Notes text, CSV, or screenshot → `import_parse` Edge Function (Claude, line-by-line) → per-line: matched / matched-pick-size / no-match→ladder. Lands on the shelf only. |
| Manual + photo | Ladder rung 4: brand (typeahead FK, no free text), product, variant, category + optional photo → **personal scope**, instant, badged "yours only until three people log it". |
| Export | CSV of the shelf (items, variants, chips, ranks) via RPC → share sheet. |

## 7. Images

- **User cutouts**: capture/pick → `VNGenerateForegroundInstanceMaskRequest` **on device** (iOS 17+, no server GPU, no per-image API cost) → mask → PNG/HEIF cutout ~150KB → EXIF stripped → presigned PUT to R2 (`users/<uid>/items/<item_id>.png`, non-guessable, per-user presign). Framing guide at capture; retake prompt when mask confidence is low; re-shoot supported (first-session dumps are the worst photos anyone takes). Shadow applied in-app at render, never inherited.
- **Catalog images**: processed **once at ingest, never at render**: fetch feed URL → normalize to square canvas → batch background removal (rembg or Vision on our own Mac, one-time) → 2–3 derivative sizes → R2 with `image_source` + `last_fetched`. Hotlinking is a fallback only. Hand-check the top ~200 products.
- **Render rules**: your shelf/collections/profile → your cutout; product pages/leaderboards/discover/search → catalog image. Fallback chain everywhere: user photo → catalog image → typographic tile (brand + category-derived tint). Nobody ever sees a broken image.
- **Shelf scaling**: scale cutouts by `variants.height_mm` against a shared ground line — a lipstick is visibly smaller than a shampoo bottle. Flag angle outliers.
- Personal-scope inheritance: user product photos stay personal; nothing user-shot becomes canonical in Phase 1.

## 8. Recommendations (Stage 0–1)

Three profiles, kept separate (PRD §11): **body facts filter** (anchors+fit, skin type, concerns, hair pattern — never rank), **attribute affinity ranks** (chip-affinity vector), **aesthetic taste diversifies** (brands, finishes).

- **Stage 0 (zero items)**: filter by body facts → population stats: "top-rated in your anchor's cohort" from `agg_rank_scores` + `agg_variant_stats`. Powers empty states — never a blank screen.
- **Stage 1 (1–5 items)**: user affinity vector over attribute chips (like/dislike/rank-weighted counts of owned products' attributes), **shrunk toward the cohort mean** by `w = n_signals/(n_signals + k)` (k≈10). Ranking position weighs highest; dislike+chip above like; ownership weak; saves weak; searches intent-only; **dwell/scroll never used**.
- Signal weights and shrinkage live in one SQL function so nothing changes architecturally between stages — only `w`. Confidence meter = same `w` rendered honestly (`ConfidenceMeter have/need`).
- Crosswalk (display only in V1): `shade_cooccurrence` self-join, thresholded on n, n displayed: "people who wear fenty 240 also wear …". Never "your match." Never parse shade names.
- Age bracket enters the **taste/diversification layer only** as a weak prior (cohort trends), plus the legal 18+ product gate as a hard filter. Age never maps to concern categories the user didn't self-report (no unprompted anti-aging pushes) — see `06-instrumentation.md` "rules of use."
- Failure-mode guards: popularity damping on the rec surface (not on shade matching), one labeled exploration slot, exclude items already ranked top-of-list (circularity).
- Visible profile: body facts editable ("sharpen your matches" = `G.Tune`); affinity shown as receipts ("8 of your top 10 are fragrance-free") **gated on confidence**; neighbor internals opaque (Phase 3).

## 9. iOS app structure (screens ↔ kit)

Three tabs + plus drawer. Every screen exists in the kit ([`screens.jsx`, screen map](https://claude.ai/design/p/38230b94-09d2-4776-9d21-be0722ba54f2?file=ui_kits%2Fglossed-app%2Fscreen-map.html) — opening instructions in [`DESIGN.md`](../DESIGN.md)); **build to the frame**. If you cannot open it, stop and say so rather than inferring the layout from the primitives.

| Feature module | Screens (kit names) |
|---|---|
| Onboarding | OnbHook (login reveal), OnbQuiz (domains → anchor → hair/palette branches), OnbPayoff, OnbAccount (method → phone → code → birthday), OnbSignIn (=OnbAccount mode=login), OnbBuild, OnbTour (2 slides), OnbWelcome |
| Discover | Discover (picked-for-you grid, tune card, leaderboards link, gap card slot — V1 renders the crosswalk card), Leaderboard, Tune |
| Shelf | Shelf (shelf view w/ real-dimension bays + list view, domain Segmented multi+all, sort, item sheet w/ FitControl), empty = Stage 0 |
| AddLadder | search → barcode → near matches → create → personal-scope confirm |
| Import | source pick → parse → per-line resolution → ladder handoff |
| ProductPage | chip evidence, FitControl + ConfidenceMeter, rank-it, leaderboard. No stars, no swatches. |
| Ranking | FaceOff (pairwise, skip, result #N of M) |
| Profile | Profile (badges, bio, routines/collections tabs, settings), privacy stub row (V1.5 tag: "nothing of yours is visible to anyone in V1") |

## 10. Testing (Handbook §17)

- Unit: ranking insertion/consistency, wear-in gating, unlock rules, chip week derivation, import line parsing (fixtures), fit/anchor view logic.
- Integration: repositories against local Supabase; every RPC gets authorized/unauthenticated/wrong-user/cross-user tests (the four-test template).
- Isolation suite (CI-required): per user-scoped table, two seeded users, deny-by-id assertions; aggregate RPCs return no row below min-n.
- E2E (XCUITest, journeys only): onboard→anchor→payoff→account→first log; add-via-ladder→personal scope; log→chips→3rd item→face-offs→rank; import 5 lines; returning-user login.
- Coverage gate: service layer 80%. No UI gate.

## 11. Metrics instrumentation (V1 events)

`onb_anchor_captured` (hero question answerable) · `search_hit`/`search_miss` (catalog hit rate, incl. first-30s anchor search) · `activation_shelf5` (5+ items, session one) · `log_chipped` (chip rate target >70%) · `faceoff_completed` (rank adoption) · `share_in_received`/WAU · `two_domain_shelf` (the moat metric) · W4 retention · merge-queue depth (ops dashboard, the canary).

## 12. Launch definition (Phase 1 done =)

- [ ] All §9 screens live against prod schema; design-system parity with the kit
- [ ] Onboarding e2e incl. payoff evidence gate + both auth paths + returning login
- [ ] Catalog: feed diff running nightly; ≥85% hit rate for the pilot circle's shelves; failed-search queue + weekly fill loop
- [ ] Ladder + import + barcode + photo + share-in + export all functional
- [ ] Ranking + wear-in + chips + fit capture; leaderboards with n everywhere
- [ ] Cutout pipeline on device; catalog images on R2; fallback chain verified
- [ ] Isolation suite green in CI; backups on with restore drill rehearsed; Sentry wired; spend caps set
- [ ] Seeds + one-command local setup; TestFlight to design partner + circle

## 13. Build order (each ≈ one S/M ticket run)

1. Repo + CI + tokens/DesignSystem primitives + supabase project + migrations 0001 (catalog) / 0002 (shelf) / 0003 (aggregates+ops) + seeds + isolation suite
2. DataKit (frozen core) + auth (Apple, phone OTP, birthday gate)
3. Catalog ingest: feed-diff job + normalize/dedupe + INCI enrichment + failed-search logging
4. Search + AddLadder + barcode + personal scope
5. Shelf + logging + chips + FitControl + cutout pipeline
6. Ranking (face-offs, positions, unlock, wear-in) + Leaderboard + aggregates refresh
7. Onboarding flow + payoff RPC + returning login + Tune
8. Import + share extension + photo extract + export
9. Discover + Stage 0/1 recs + crosswalk card + ConfidenceMeter
10. Profile + collections + settings + metrics events + polish/QA jam
