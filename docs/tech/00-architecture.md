# GLOSSED — Technical Architecture (all phases)

**Status** accepted · **Date** Aug 27 2026 · **Owner** Sean
**Companion docs**: `../domain.md` · `01-phase-1-journal.md` · `02-phase-15-public-identity.md` · `03-phase-2-social.md` · `04-phase-3-depth.md` · `05-phase-4-reach.md` · `../adr/`

---

## 0. Project card (Handbook §1)

| Field | Value |
|---|---|
| Product name | GLOSSED (working title, PRD §19.20) |
| Owner | Sean (product + eng); design partner = user zero |
| Problem, one sentence | Beauty discovery has no personal record and no skin-aware ranked answer to "will this work on me" |
| Platforms | iOS only (decided; native frameworks are load-bearing) |
| Launch definition | Phase 1 checklist in `01-phase-1-journal.md` §12 |
| Launch date | Soft — pilot with design partner + circle first |
| Multi-tenant? | No (consumer, per-user isolation via RLS) |
| Data classification | Regulated (skin/hair profile, phone, birthday, photos) — see `../domain.md` §5 |
| Regulatory | COPPA (under-13 block) · BIPA/CUBI avoidance (no biometric inference) · App Store 1.2 (UGC, Phase 2 gate) · FTC gifted disclosure (Phase 2) |
| Uptime target | Best effort pre-1.5; 99.5% from Phase 2 |
| Support | Solo dev; in-app feedback widget → triage weekly |
| OS floor | iOS 17.0 (Vision foreground mask + SensitiveContentAnalysis require it); oldest device: iPhone XS class |
| Accounts/IP | Sole owner; all vendor accounts under business email, credentials in shared password manager |
| Budget: build | Sweat |
| Budget: run rate | $10–35/mo MVP target (PRD §15). Catalog $0. |

## 1. Stack (decision summary — details in `../adr/`)

| Layer | Choice | Why (criteria: Handbook §6) |
|---|---|---|
| Client | Swift 6 (strict concurrency), SwiftUI, iOS 17+, local SPM packages per feature | Native is load-bearing: Vision cutouts, Share Extension, SCA, native date wheel. Modules make the compiler enforce layering. |
| Backend | **Supabase** (managed Postgres 15+, PostgREST, Auth, Edge Functions, Realtime) | Postgres = the PRD's self-hosted-snapshot decision + RLS as the isolation backstop + pg_trgm/FTS/pgvector for dedupe & search. Auth ships Sign in with Apple (native `signInWithIdToken`) and phone OTP out of the box. Free tier fits the run-rate. Escape hatch: it's plain Postgres. |
| SMS | Twilio Verify via Supabase Auth phone provider | Supported provider list: Twilio, MessageBird, Vonage, TextLocal. Test-OTP mapping for dev. |
| Images | **Cloudflare R2** (S3-compatible), uploads via short-lived presigned URLs minted by an Edge Function | Zero egress, 10GB free tier. PRD-decided. Storage math: ~150KB/cutout → 10k users ≈ 45GB ≈ <$1/mo. |
| LLM | Claude API (`claude-haiku-4-5` for import parsing + dedupe compare; `claude-sonnet-5` where accuracy matters, e.g. photo label reading) | Import from Notes/CSV/screenshot, near-match adjudication, failed-search triage. Spend caps + per-call budget from day one. |
| Jobs | Supabase Edge Functions + `pg_cron` schedules; DB-backed job table with retries/backoff/dead-letter | Feed diffs, aggregate refreshes, INCI enrichment. No queue service until it hurts. |
| Error tracking | Sentry (iOS + Edge Functions), release-tagged, symbolicated | Handbook §19 |
| Analytics | Thin `track()` wrapper from day one → provider later | Handbook §19 |
| CI | GitHub Actions: SwiftLint/SwiftFormat, build, unit + isolation SQL tests, PR size check, secret scan; `supabase db` migrations gated | Handbook §25 day-one list |

**Docs consulted for the above** (Handbook: read the docs before committing): Supabase phone-login guide + Swift reference (`signInWithOTP`/`verifyOTP`, provider list, OTP expiry/rate limits), Supabase Apple provider guide (native `signInWithIdToken(provider: .apple, token:, nonce:)`; name only arrives on first sign-in), Supabase features matrix (Swift SDK GA, phone auth GA, RLS GA, Edge Functions GA), Apple docs for `VNGenerateForegroundInstanceMaskRequest` (iOS 17+/macOS 14+, on-device, device-only — no simulator) and the `com.apple.developer.sensitivecontentanalysis.client` entitlement (iOS 17+, value `analysis`, silently returns negative without it, **unavailable inside extensions**), Cloudflare R2 pricing (zero egress; free tier 10GB-mo, 1M class A, 10M class B).

## 2. Design-review deltas (supersede the PRD where they conflict)

Recorded so they don't get relitigated (Handbook principle 7). Source: the Claude Design project chat + kit README.

1. **"Shade twins" concept removed.** The anchor-join *mechanism* stays (PRD §05), but no twin persona, no `#shadetwins` surface, no twin cards. Every population claim names the shade or the data: "12 people wear fenty 240", "people in your shade". No tone-band claim where an exact shade exists.
2. **All four domains ship in V1** (makeup, skincare, haircare, fragrance). Fragrance has no shade or skin axis: ranks by face-off only, and the UI says so. Hair-type question is an onboarding branch gated on the haircare domain.
3. **Returning users skip onboarding entirely.** Login is the account screen in `mode=login`; Apple lands straight on discover; phone → number → code → discover. Nothing re-asked. Sign-in method buttons always pinned to the bottom.
4. **Onboarding order** (new accounts): start → what-you-buy → anchor → [hair branch] → [palette branch, only for "I don't wear any"] → payoff → account (way-in → phone → code → birthday; one decision per screen; every screen goes back one) → shelf starter → tour (2 frames) → welcome. Skin type/concerns/brands moved *after* signup ("sharpen your matches" on discover).
5. **Privacy (1.5) is a scope matrix**, not presets: three scopes (just you / friends / public) × four surfaces (looks, shelf, rankings, routines) + one "everything" master that reads **mixed** the moment any row differs.
6. **Personal → canonical promotion trigger: three distinct users log a matching product** (plus reviewer confirmation). The personal-scope badge states the deal in-product.
7. **Leaderboard min-n: 5 face-offs per scope** before a product can be ranked in that scope; unranked rows say so instead of hiding. Every row shows its n.
8. **Birthday**: native date wheel, own screen; used for the under-13 block, 18+ gating, and recommendations only; never shown on the profile.
9. **V1 nav = three tabs** (discover / shelf / you) + center plus (drawer: add · import · collection · routine). The feed tab exists only in Phase 2.
10. **Empty states are Stage 0 recommendations** — an empty shelf still knows your shade. "None of these" carries equal visual weight at every ladder rung.

### Product-direction deltas — Sean, Aug 30 2026 (same authority as the above; recorded from his direction verbatim, tickets updated the same day)

11. **The feed is in V1.** The looks feed, public profiles, and the anchor-join matching all ship at launch. Pulled in as launch requirements: the full moderation stack before first App Store review (GLO-26, now V1); on-device nudity screening at upload plus cloud image moderation before anything goes public; under-18s cannot post photos, enforced at the policy layer; the privacy controls (built in 1.5 — the scope matrix's master row is the preset); and a hand-recruited beta cohort (GLO-192). **Deliberately held back: comments (GLO-34 — "comments are where incidents come from"), contact import (GLO-35), and DMs — permanently.** The feed is photo posts plus reactions. *Delta 9's "the feed tab exists only in Phase 2" is superseded on timing; the nav question it answered is now open again and undecided — it joins the browse-tab IA question already parked with Sean.* Delta 1 stands: the matching **mechanism** ships; no twin persona, no twin surface, no twin cards.
12. **Discover is not a shopping page.** A store's card is name, price, buy; ours is evidence — "ranked #2 of 11 by people with your anchors, n=34." **Hard rule: a card that cannot show its n does not render. A card with no community data behind it is an ad, not discovery.** Enforced server-side (0040 gates every tier on min-n before rows leave the database). One recorded nuance: the wander row deliberately renders no n because it makes no claim — "a zero would read as a failed claim rather than the absence of one" — and labels itself a wander instead.
13. **Want-to-try → tried → own/finished is a proper status arc, and its two signals never blend.** Want-to-try is weak for taste (people save hype) and strong for intent, so it drives gap detection and catalog priorities and **never** feeds affinity — 0035's "unworn is not evidence" is the same rule from the other side. The funnel stat this enables ("47 wanted, 12 tried, 3 kept") is GLO-193, min-n gated like every claim.
14. **Shelf images are the user's own products, background-removed on device, scaled to real dimensions** — the half-used bottle with the smudged label is the point. Catalog images (product pages, search, discover, where consistency matters) come from **retailer affiliate feeds, not OBF** — OBF is the stopgap until GLO-90/91 unblock GLO-194. Fallback order, always: user's photo → catalog image → typographic tile; never a broken image. (Whether the drawn `ProductMock` counts as the typographic tile is flagged on GLO-194 for a ruling.)

## 3. System architecture

```
┌─ iOS app (SwiftUI, iOS 17+) ─────────────────────────────────┐
│ features/* (SPM modules)  ── DataKit (the frozen core) ──────┼── PostgREST + RPC (RLS)   ┐
│ Share Extension ── App Group queue ─┘                        │                            │
│ Vision cutout · SCA (P2) · barcode scan · photo OCR confirm  │── Edge Functions ──────────┤ Supabase
└──────────────────────────────────────────────────────────────┘   (presign, import-parse,  │  Postgres
                                                                    payoff, ingest jobs)    │  + Auth
        Cloudflare R2 ◄── presigned PUT (cutouts, swatches)         pg_cron schedules ──────┘
        R2 ◄── catalog image pipeline (one-time batch, Mac + rembg/Vision)
        Retailer affiliate feeds (Rakuten/Impact) ─► feed-diff job ─► catalog
        Licensed snapshot (one-time) ─► self-hosted import ─► catalog
        INCI API / Open Beauty Facts ─► enrichment job (once per product, cached forever)
        Claude API ◄── import parsing · dedupe compare · label reading
```

**The frozen core** (Handbook §10.1 adapted to consumer): `DataKit` — the one Swift module through which every query passes. It injects the session, exposes typed repositories, and never exports a raw client. RLS on every user-scoped table is the second, independent layer: per-user `user_id = auth.uid()` policies; aggregate reads go through security-definer RPCs that enforce min-n so raw rows never leave the database. Agents never modify DataKit or migrations (stated in per-directory instruction files).

**Isolation test suite (required CI check)**: for every user-scoped table, seed two users and assert user A cannot read/update/delete B's rows by ID guessing, and cannot fetch B's R2 objects (keys are non-guessable; presigns are per-user). A new user-scoped table without an isolation test fails CI. SQL tests run against `supabase db` local in CI.

## 4. Repo layout (Handbook §7 → iOS)

```
glossed/
  app/Glossed/                 entry point, routing, DI — thin
  app/ShareExtension/
  features/                    one SPM package per slice; may not import each other
    Onboarding/ Shelf/ Discover/ ProductPage/ Ranking/ AddLadder/
    Import/ Leaderboard/ Profile/ Privacy/ (P1.5+) Feed/ Looks/ (P2)
  core/
    DataKit/                   frozen core: session, repositories, typed errors
    DesignSystem/              tokens + primitives (see §6)
    Media/                     Vision cutout, EXIF strip, upload
    Tracking/                  track() wrapper
  supabase/
    migrations/  functions/  seed/  tests/isolation/
  docs/  (this tree)
```

Layering (enforced by SPM dependency graph): `app → features → core`. Features never import features. DesignSystem knows nothing about the app.

## 5. Environments (Handbook §5)

| Env | What | Data |
|---|---|---|
| Local | `supabase start` (Docker) + Xcode; one command: `make dev`. SMS test-OTP mapping so no real SMS. | Deterministic committed seed: 2 users, all four domains, every lifecycle state (wear-in mid-window, personal-scope product, empty category, sub-3 category, thin leaderboard cell) |
| Preview | Supabase branch per PR + TestFlight internal build | Branched from seed |
| Staging | Persistent Supabase project, prod-shaped config | Synthetic, refreshed from seed; never prod data |
| Prod | Deploys from main via CI after staging | Real. No manual edits — fixes are reviewed scripts through CI. |

Env vars validated at boot (app refuses to start on a missing/malformed var). `.env.example` complete.

## 6. Design system (build before feature work — Handbook §8.3)

Port the Claude Design kit 1:1 into `core/DesignSystem`:

- **Tokens** (from `tokens/*.css`, single Swift file, no literals in views): ground `milk #EFEDE7`, `card #FFFFFF`, `line #DED9CF`, ink `#1B1917/#5D5850/#A29C90`; the one loud accent cherry `#E23A66 / deep #A8123D / soft #F7DCE3`; semantic-only support hues mint (like), lilac (attribute), butter (progress); radii 8/12/18/pill; hard zero-blur ink sticker shadows 1.5–4px; rotations −2/1.4/−1/2.2°; motion 120/200ms spring; 44pt hit targets.
- **Type**: Bricolage Grotesque 700–800 display (lowercase, tight), system sans body, Space Mono meta/eyebrows (the only uppercase), Caveat hand asides (max one per screen). Dynamic Type + contrast are the real a11y work; chip polarity carries a glyph per kind so it survives without color.
- **Primitives** (each its own PR): Button, IconButton, Tag, Badge, Avatar, RankBadge · Chip, ChipGroup · Input, Select, Checkbox, Switch, Segmented (multi + "all") · Card, Dialog, Toast · FloatingNav, TabBar, ActionDrawer · ShadeAnchorPicker, FitControl, HairTypePicker, EvidenceLine, ConfidenceMeter, GapCard, ProductCard.
- **The one rule**: two layers, never mixed — resting (bone, hairline, no shadow) vs pop (ink border, sticker shadow, rotation, cherry), one pop moment per screen. Counts go through `EvidenceLine`, never ad-hoc text. No claim without its n.

## 7. Cross-phase concerns

### 7.1 Observability + error logging

| Concern | How |
|---|---|
| Crashes + errors (iOS) | **Sentry** (free tier: 5k errors/mo): crash reporting, symbolicated, release-tagged; breadcrumbs carry screen + event names, never regulated values. MetricKit hangs/launch metrics via Sentry's integration. |
| Errors (server) | Sentry in every Edge Function; Postgres errors surface in Supabase logs (Logflare), log-drain later if needed. |
| Typed errors | One Swift error enum + one SQL error convention: machine code + user-safe message; a single boundary maps them to UI. Internal details never reach the user. Every user-facing error renders a short **support reference** that maps 1:1 to a Sentry event id. |
| Structured logs | Request id, user id (pseudonymous), route/RPC name on every server log line. Never document contents, tokens, photos, or regulated field values — identifiers only. |
| Uptime | External cron ping (Better Stack / UptimeRobot free) against a `health` RPC that touches the DB. |
| Alerting | Sentry alert rules + uptime alerts → one alerts channel (email/Slack). Quiet by default — noise there is a bug. Watch 30 min after each deploy. |
| Job visibility | `ingest_jobs` table is the queue *and* the dashboard: state, attempts, last_error, dead-letter rows reviewed weekly. |
| Product analytics | Separate system, first-party — see `06-instrumentation.md`. Sentry answers "what broke"; the events table answers "what do people do". |

- **Never log field values for regulated data** (`domain.md` §5) — applies to Sentry breadcrumbs and server logs equally.
- **Idempotency**: client-generated UUIDs for UserItem/log/face-off writes; unique constraints make double-taps no-ops.
- **Offline**: cut from MVP (PRD decision). Deliberate behavior: reads cache-last, writes fail loudly with retry affordance. Revisit at 1.5.
- **Migrations**: free-reset until first real record; expand-and-contract from that day (Handbook §20).
- **Spend caps** on every metered vendor (Twilio, Claude API, R2, Sentry) on day one; one cost sheet, monthly.
- **App Store**: privacy manifest + data-collection disclosures matching `../domain.md` §5; review lead time in release plan; expedited-review path rehearsed.

## 8. Phase map (the line: is any UGC visible to another person?)

| Phase | Ships | Doc |
|---|---|---|
| 1 · The Journal | Single-player + anonymous aggregates. Four domains. No user content visible to any other user. | `01` |
| 1.5 · Public identity | Privacy scope matrix, public profiles (text), following, routines, swatches, link cards, trending, report/block. | `02` |
| 2 · The Social Layer | Feed, looks, comments, oEmbed video, contacts, gap cards, the Stylist, the seam, full moderation stack (launch requirement). | `03` |
| 3 · The Depth Layer | Price history + deal alerts, recs v2 (Kendall-tau neighbors), ingredient conflict warnings, creator cohort. | `04` |
| 4 · The Reach | Brand pages, targeted sampling, giveaways, paid creator campaigns, native video, community catalog cleanup. Needs scale/funding. | `05` |
