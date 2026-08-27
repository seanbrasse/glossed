# Instrumentation & Product Analytics (all phases)

The question this system answers: **who our users are, what they reach for, what they ignore, and where they leave** — without contradicting the product's own privacy posture.

---

## 1. Posture and constraints

- **First-party analytics, in our own Postgres.** Events flow through the `track()` wrapper (core/Tracking) → batched Edge Function ingest → an `events` table in Supabase. No third-party analytics vendor at MVP.
  - Why: the questions we care about ("do 4c users adopt haircare chips?", "does the palette-fallback cohort retain worse?") are **joins between behavior and body facts** — and body facts are Regulated-class data (`domain.md` §5) that we will not ship to a vendor. In our own DB the join is one SQL statement and the data never leaves.
  - The handbook's rule is satisfied: `track()` is a thin wrapper, so adding PostHog/Amplitude later for behavioral-only events is a one-file change. If added: pseudonymous ids only, **no body facts, no phone, no birthday** as properties, ever.
- **The brand boundary, written down**: the PRD bans dwell/scroll as *recommendation inputs*. Analytics may measure screens and funnels to make product decisions; nothing in `events` is readable by the rec pipeline. Enforced structurally: rec RPCs have no grants on `events`.
- Events carry **identifiers, not values**: `variant_id`, `category_id`, counts — never note text, never photos, never free-text chips.
- App Store privacy disclosure: "Product Interaction, linked to user, not used for tracking." No IDFA, no ATT prompt needed.
- Retention: raw events 12 months, then rolled up and dropped. Deleted accounts: events deleted with the account.

## 2. Schema

```sql
events(id bigint, user_id uuid null,            -- null for pre-signup onboarding (anonymous device id)
       anon_id uuid null,                       -- links pre-signup funnel to the account after signup
       name text, props jsonb, screen text,
       app_version, os_version, ts timestamptz)
  partition by range (ts);                      -- monthly partitions, cheap to drop at retention
event_rollups_daily(day, name, cohort_key, n, users)   -- refreshed nightly by pg_cron
```

Client: buffered queue, flushed on background/foreground, dropped (not blocked) on failure — analytics must never cost UX. Client-generated event UUIDs dedupe retries.

## 3. Event taxonomy

Convention: `object_action` lowercase snake, past tense; props are ids + enums only. The canonical registry lives in one Swift enum in `core/Tracking` (compiler-checked) mirrored in a `docs/tech/events.md` table generated from it — no ad-hoc event names.

### Phase 1 (core)

| Event | Props | Feeds |
|---|---|---|
| `onb_step_viewed` / `onb_step_completed` | step, branch (hair/palette) | onboarding funnel, drop-off per step |
| `onb_anchor_captured` | brand_id, variant_id, fit | PRD metric: anchor capture % |
| `onb_payoff_shown` | n_exact_shade, evidence_backed bool | payoff quality gate monitoring |
| `search_performed` | query_hash, domain, hit bool, result_count, source (onb/ladder/discover) | catalog hit rate; failed-search queue already gets the raw query |
| `item_logged` | variant_id, category_id, source (search/barcode/photo/share_in/import/ladder_create), scope | activation, ingest-path mix |
| `chip_applied` | chip_id, kind, week | chip rate (>70% target), vocab health (which chips never fire) |
| `fit_captured` | fit | fit-prompt wording health (miss-admission rate: % non-just-right) |
| `faceoff_completed` / `faceoff_skipped` | category_id, session_len | rank adoption; skip rate = "too close" friction |
| `shelf_viewed`, `product_viewed`, `leaderboard_viewed` | ids, scope | surface usage |
| `import_completed` | source, lines, matched, to_ladder | import quality |
| `share_in_received` | source_host, resolved bool | share-ins/WAU (retention feature) |
| `cutout_captured` | confidence_band, retake bool | capture-guide tuning (PRD §19.19) |
| `export_generated` | item_count | exit-pressure signal |
| `rec_impression` / `rec_tapped` / `rec_dismissed` | slot (stage0/picked/crosswalk/exploration), variant_id, reason? | rec quality without engagement-optimizing: tap-through + dismissal reasons only |
| `error_shown` | code, support_ref | UX-visible failure rate |

### Phase 1.5+ additions
`scope_changed` (surface, from, to, via_master) · `profile_published` · `follow_added` · `swatch_posted` · `link_card_opened` (server-side) · `report_filed` — plus Phase 2: `look_posted`, `comment_posted`, `feed_session` (depth as *count of taps*, not dwell), `gap_card_{shown,accepted,dismissed}` (reason — the learning loop), `stylist_query` (tools_used, answered bool).

## 4. Person properties (snapshot, in-DB only)

Nightly job materializes `user_facts(user_id, signup_cohort_week, domains, skin_type, tone_band, hair_pattern, onboarding_branch, anchor_count, shelf_size, ranked_lists, two_domain bool, minor bool, last_active_day)`. Every analysis is `events ⋈ user_facts` — this is the "who is our user base" table.

## 5. The standing questions (weekly dashboard)

One SQL file per question, rendered by a lightweight dashboard (Supabase Studio saved queries now; Metabase on a free box if/when charts matter):

1. **Who**: signup mix by domains selected, skin type, tone band (granularity check on the deep range — PRD §06 trust issue), hair pattern, anchor vs palette-fallback cohort, minor share.
2. **Funnel**: onboarding step → payoff → account → 5-item activation; split by branch and by `evidence_backed` payoff.
3. **What they use**: feature adoption matrix (logged via which ingest path, chip rate, face-off rate, collections, import, export) by cohort — **and the inverse: features with <X% adoption at W4 get flagged as dead-or-hidden**, the "what they don't use" report.
4. **What they like/dislike** (the product data *is* the preference data): top chips by valence per category/cohort, dislike-chip concentration (which products create dislikes), fit-miss distribution (are people admitting bad buys — PRD §19.9), leaderboard scope usage (your-shade vs everyone).
5. **Where they leave**: W1/W4 retention curves by cohort + last-event-before-churn distribution; search-miss → churn correlation (the 30-second holy-grail test).
6. **Ops canaries**: merge-queue depth, payoff evidence rate, cutout retake rate, share-in resolution rate.

## 6. Qualitative loop

- **Feedback widget** (V1): one tap from settings + shake gesture → `feedback(user_id, route, body, screenshot?)` → piped to the `#qa` channel. Cheap, and how we learn what the funnel numbers can't say.
- **Design-partner reviews** stay the primary qualitative instrument through 1.5 (PRD: user zero validates every flow); notes filed in `docs/research/`.
- No NPS, no survey pop-ups in-app before Phase 2 — the app talks like a group chat, not a brand.

## 7. Ownership + cadence

- Metrics review: 30 min weekly against §5, decisions logged in `#decisions`.
- Any new event = PR to the Tracking enum + this doc's registry. Events without a standing question they answer get rejected in review — no data hoarding.
