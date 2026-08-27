# Phase 1.5 — Public Identity (text only)

The line crossed here: some user content becomes visible to other users — **text only**. Moderation surface = bios and usernames, a one-person-sized problem. Photos (looks) stay in Phase 2; **swatches ship here** (PRD §09) as the one photo exception, gated by the same pre-public moderation pipeline as Phase 2 in miniature (single content type, single reviewer).

Scope: privacy scope matrix · public profiles (rankings, shelf, collections as text) · following · routines (browse) · off-app link cards · trending · swatches · linked socials · report/block on profiles.

---

## 1. Privacy: the scope matrix (design-review model)

Two axes stay separate (PRD): **contribution** (feeds anonymous aggregates — always on, not a setting) vs **visibility** (attributed — always the user's choice).

```sql
privacy_scopes(user_id pk, looks scope_enum default 'just_you',       -- scope_enum: just_you|friends|public
               shelf scope_enum default 'just_you',
               rankings scope_enum default 'just_you',
               routines scope_enum default 'just_you',
               discoverable bool default false)                        -- surfaced in matching/suggestions at all
follows(follower_id, followed_id, created_at, primary key(follower_id, followed_id))
blocks(user_id, blocked_id, created_at) · reports(id, reporter_id, subject_kind, subject_id, reason, state, …)
```

- **UI**: three-way control per surface + an "everything" master that sets all four and reads **mixed** the moment any row differs (never lies about state). Color dot per row. The master is derived, never stored.
- **RLS**: read policy per surface, e.g. shelf rows visible when `owner = auth.uid()` OR (`scope='public'`) OR (`scope='friends'` AND follower relationship) — and never when a block exists in either direction. One SQL function `can_view(owner, surface)` used by every policy so the logic can't fork.
- **The one asymmetry, stated at the toggle**: to be *surfaced to others* in shade-based suggestions you must be `discoverable`; private users still *receive* everything. (No "shade twin" naming — copy says "people in your shade can find you.")
- Minors: default all-private, `discoverable=false` and locked.
- Publishing acts (posting a swatch; later, commenting) are per-act decisions, not profile state.

## 2. Public profiles + following

- Public profile = avatar, display name, hideable badges (skin type, anchor shade, hair pattern), bio, and whichever of shelf/rankings/collections/routines their scopes allow. Own-profile view is unchanged.
- Usernames: unique handle chosen at first publish (not at signup — V1 never needed one). Reserved-word + impersonation checks.
- Follow model (no mutuals needed). Contact import stays **out** until Phase 2 (post-activation only, PRD).
- Suggested people: same-anchor + agreeing-fit join, `discoverable` only, with the reason named ("wears fenty 240 · ranks 14 things"). One person with a reason, never a three-avatar grid (design rule).
- Report/block/mute on profiles ships day one of this phase. Blocks sever visibility both ways and suppress suggestions.

## 3. Routines (public browse)

- V1's private routines gain scope. Browse surface: "AM routines from people with your skin" — filter by skin type/concerns (and curl pattern for wash-day), scope-respecting, n shown.
- Object unchanged (slot am/pm/weekly/wash_day, ordered steps, started_on) — wash day is already first-class.

## 4. Swatches

```sql
swatches(id, user_id, variant_id, r2_key, tone_band_at_capture int,   -- snapshotted, not live-linked
         state pending_review|public|removed, posted_at, …)
```

- Tagged to the **Variant**, only for variants on your shelf. Camera roll allowed. Poster's tone band snapshotted at capture time (July tan stays filed correctly).
- Variant page groups swatches by tone band, viewer's band expanded first.
- Posting is a per-act publish: EXIF strip → upload → cloud image moderation → public. Authenticity is policy not lock: no AI-generated swatches, report+review enforced; check C2PA metadata where present; claim no detection we can't deliver. White balance is a volume problem, not fraud.
- Minors cannot post swatches (no photo posting under 18).

## 5. Off-app sharing + link cards

- Shareable URLs for collection / profile / product (`glossed.app/c/<slug>` …): OG-image link cards rendered by an Edge Function (server-rendered PNG: cutout stickers + title + n). The collection link is the unit that spreads.
- Requires respecting scopes at render time; private targets produce a generic card.
- Universal links + deep-link routing into the app (App Site Association shipped now; also covers share-in flows).

## 6. Trending + linked socials

- Trending = ownership/log velocity over trailing window, overall and per skin type, rendered as cutout stickers; min-n rule applies.
- Linked socials on profile (instagram/tiktok handles, plain links) — the creator hook, zero moderation weight (text fields, same bio pipeline).

## 7. Infra deltas

- Web presence appears for the first time (link cards + universal links): a single Edge-rendered public page per share target — no full web app; page says "open in the app."
- Moderation tooling v0: report queue view (Supabase Studio + a small internal table UI), text moderation (Claude moderation prompt) on bio/handle/collection titles at write time; image moderation API for swatches pre-public.
- Metrics added: publish rate, scope distribution, follow graph size, link-card CTR, swatch post rate + report rate.

## 8. Definition of done

- [ ] Scope matrix live with RLS enforced by `can_view()`; isolation suite extended to friend/public/block cases (viewer-pair test grid)
- [ ] Handles, public profiles, following, suggested-people with named reasons
- [ ] Routines browse; swatches end-to-end with pre-public moderation; minors restricted
- [ ] Link cards + universal links; trending
- [ ] Report/block/mute live; moderation runbook written (incl. NCMEC runbook drafted ahead of Phase 2)
