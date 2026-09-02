# Phase 2 — The Social Layer (photos + people)

Scope: looks feed · comments · video via oEmbed · friends + contact import · gap cards · the Stylist · the seam · reformulation forking UX · **the full moderation stack as a launch requirement, not a follow-up** (App Store 1.2 gate).

Nav becomes four tabs (feed · discover · shelf · you) — the kit's `navTabs4`.

---

## 1. Looks

```sql
looks(id, user_id, caption, state draft|pending|public|removed, posted_at, …)
look_photos(id, look_id, r2_key, position)
look_tags(look_id, variant_id, x numeric, y numeric)        -- pin-style, tappable to product page
```

- Looks respect the `looks` privacy scope; also render on the tagged product's page (public looks only).
- Composer: photos from camera/roll → on-device **SensitiveContentAnalysis** check (entitlement `com.apple.developer.sensitivecontentanalysis.client`; runs in the main app — the framework is unavailable in extensions, so share-extension photo posts route through the app) → EXIF strip → upload → cloud image moderation → public. Prevention over takedown: with one reviewer, prevention is the only model that scales.
- Tag flow: search-your-shelf picker → drop pin. Tags are Variants (shade is the point).

## 1a. Saves — keeping other people's looks, collections and routines

Sean, Sep 2: *"Users can save other people's looks/collections/routines in
addition to want to try items. We need a place in our profile for this, and
our stylist should be able to reference saved things as well."*

`look_saves` (§2) generalises. A **save** is a private pointer from you to
something someone else published — a look, a collection or a routine — the way
`want_to_try` is a private pointer to a product you do not own yet. Four things
are settled by what already exists:

- **Saves are private and never a feed event** (`tech/00` delta 13: *"a feed
  of saves is a product feed wearing a person's name"*). Same posture as
  `want_to_try`, which is never published (0021). No counts, no "saved by n".
- **Saves are a weak taste signal** (`tech/07` §2's reserved row, +0.5). A saved
  routine contributes its steps' variants' chips weakly; a saved look its tags'.
  They never rank; they diversify.
- **A save is a pointer, not a copy.** It renders whatever the owner shows
  *today*, through `can_view(owner, scope)`. Something that went private, or
  whose owner blocked you, renders as a quiet "no longer shared" row and is
  dropped from every count — a save must never become a way to keep reading a
  thing after its owner stopped sharing it.
- **"Make it mine" is a draft, not an edit.** Saved things belong to other
  people. The one action on a saved routine is *use this* → a `RoutineDraft`
  of your own, attributed ("from @maya's night routine"); on a collection,
  *add to want to try* per item; on a look, open the tagged products.

```sql
create type save_kind as enum ('look', 'collection', 'routine');
create table saves (
    user_id       uuid not null references auth.users (id) on delete cascade,
    kind          save_kind not null,
    look_id       uuid references looks (id) on delete cascade,
    collection_id uuid references collections (id) on delete cascade,
    routine_id    uuid references routines (id) on delete cascade,
    created_at    timestamptz not null default now(),
    constraint saves_one_target check (
        (kind = 'look'       and look_id is not null and collection_id is null and routine_id is null) or
        (kind = 'collection' and collection_id is not null and look_id is null and routine_id is null) or
        (kind = 'routine'    and routine_id is not null and look_id is null and collection_id is null)),
    constraint saves_not_own check (true)  -- enforced in save_thing(): you cannot save your own
);
-- one row per (user, target): partial unique indexes per kind
-- RLS: select/insert/delete own rows only; insert goes through save_thing(kind, id),
-- which checks can_view(owner, scope-for-kind) and owner <> caller at save time.
-- Reads of the TARGET go through the existing public read paths, so a save of a
-- since-private thing returns nothing for it — the client renders the gap.
```

**On the profile** (Sean, Sep 2: *"to try should be moved into the saved
tab. Saved tab should have saved routines, products, collections, and
looks"*): a fourth tab, `saved`, beside looks · collections · routines, scope
mark `only you` and no other scope possible. Four groups, in Sean's order:
**routines**, **products** (the existing want-to-try default collection,
moved here from the collections tab where it leads today — a saved product IS
a want-to-try item, and the collections tab stops carrying it), **collections**,
**looks** — the three saved-from-others groups each attributed to their
owner's handle, opening the owner's thing through the shell's existing doors
(`openLook`, a public collection, a public routine). Empty state: *"things you
save land here — products to try, and other people's routines, collections
and looks."*
The save affordance is the kit's `SaveIcon` on the three stranger surfaces
(look post, public collection, public routine), toggling; no save on your own.

**For the stylist** (`tech/08`): the prefetch under the caller's JWT gains
`saves` — each with its owner's handle and, for routines and collections, the
overlap with the caller's shelf — and the tool belt gains `reference_saved(kind,
id)`, validated against the prefetch like `reference_look`. The receipts rule is
unchanged: *"you saved @maya's night routine — 2 of its 5 steps are on your
shelf"* is a claim with its n. The stylist may compare, adapt (`propose_routine`
from a saved one, attributed) and remind; it never edits a saved thing, and it
never mentions a save to anyone but its owner.

**Minors:** saving is allowed (private, nothing published); what a minor can
*see* to save is already `can_view`'s problem. **Deletion:** `saves` cascades
with the user and with the target; add it to `domain.md` §6's list.

**Tickets** (workspace at its issue cap — thread on GLO-224 until lifted):

| # | ticket | needs |
|---|---|---|
| SAV-1 | this section | — |
| SAV-2 | migration: `save_kind`, `saves`, `save_thing()`, RLS, pgTAP four-test template | the migration slot, after STY-8 |
| SAV-3 | DataKit `SavesRepository` (list, save, unsave) | a frozen-core opening |
| SAV-4 | profile `saved` tab: routines · products · collections · looks, attribution, gap row, empty state; want-to-try moves in and leaves the collections tab (Sean's ruling) | SAV-3 |
| SAV-5 | `SaveIcon` on look post, public collection, public routine | SAV-3 |
| SAV-6 | stylist: `saves` in the prefetch, `reference_saved` tool, attribution rule in the prompt, tests | SAV-2 |
| SAV-7 | taste: saves as the +0.5 reserved signal in `affinity_for_user()` | migration, after SAV-2 |
| SAV-8 | `save_added` / `save_removed` events (kind only, identifiers only) | — |

## 2. Feed

- Priority: friends + follows → suggested similar-skin people → products/brands. Cold start leans entirely on suggested people (new users have zero friends).
- **Implementation: fan-out on read.** At this scale a per-request query beats maintained timelines: `(posts from follows) UNION (posts from suggested cohort) ORDER BY recency + light scoring`, keyset-paginated, cached per user for minutes. No dwell/scroll signals collected — ranking inputs are follows, cohort match, and recency only (the "no engagement optimization" positioning is architectural, not just copy).
- Feed cards = the kit's Feed frame: poster + reason line ("people in your shade" naming the data, never a twin persona), photo stack, caption, tagged products expander, like/save/share.
- Likes/saves: `look_likes`; `look_saves` is superseded by `saves` (§1a), which covers looks, collections and routines — saves feed the taste profile (weak signal), likes are social only.

## 3. Comments

```sql
comments(id, look_id, user_id, body, state pending|public|removed, …)
mutes(user_id, muted_id)
```

- Ships **with** report/block/mute from day one. Text moderation at write (blocklist + model pass) → public; reported → review queue.
- Commenting is a per-act publishing decision; minors can comment (text), never DM (DMs don't exist, ever, this phase).

## 4. Contact import + friends

- Post-activation only, opt-in screen, never during onboarding. `CNContactStore` → hashed phone numbers (SHA-256, salted server-side) → match against auth phone hashes → "already here" list + invite sheet. Raw contacts never stored server-side; hashes stored transiently for matching then discarded. Minors: no contact sync.
- Apple Private Relay users are unreachable by email — expected; phone matching is the path (PRD).

## 5. Video

- **Link, don't host**: oEmbed TikTok/Reels on looks and profiles (paste URL → oEmbed fetch server-side → embedded player card). Drives traffic back to the creator. Native upload stays out.

## 6. Gap cards + the seam

- Gap card v1 = **set difference, no model**: categories your same-anchor/skin cohort keeps (≥ threshold share) minus categories you've logged → top 1–2, dismissible strip, never Discover's organizing principle. Tone rule: "what people like you keep," never "what you lack."
- Rejection reasons captured (already have one → prompt the log; not interested → suppress category; too expensive → price-band signal; use something else → prompt the log). `gap_dismissals(user_id, category_id, reason, at)`.
- Mismatch cards **do not ship** until gap cards prove out; when they do, claims are only user-reported receipts ("14 people with acne-prone skin tagged this broke me out"), never our assertions, never comedogenicity ratings.
- **The seam**: cross-domain queries the multi-shelf uniquely answers — surfaced as editorial-style discover modules backed by chip co-occurrence across domains on the same shelf (e.g. silicone-heavy stylers × hairline-acne chips; sunscreen × pilled-under-makeup by foundation). Implementation: SQL over `item_chips` joins on shared `user_id` across domains, min-n enforced, receipts shown. Start with hair/skin (least served).

## 7. The Stylist (AI chat)

A discovery feature wearing a chat costume. **If it can't use our data, it doesn't answer.**

- Architecture: Claude (`claude-sonnet-5`) with tool use over a fixed tool belt of in-app queries — `search_catalog`, `query_chips(cohort, filters)`, `user_shelf`, `crosswalk(variant)`, `find_people(criteria)` (discoverable users only), `draft_look/routine/collection`. Edge Function orchestrates; every tool result carries its n; answers must cite tools used (server enforces: no tool call → templated "I don't have receipts for that").
- Outputs are structured artifacts (look draft, routine draft, collection draft, product list, person card) rendered natively and editable — not paragraphs.
- Hard rules: no skincare-as-medical-advice (system prompt + refusal patterns + response classifier), no claims beyond retrieved data, conflict checks phrased as caution not verdict.
- Gap cards are the Stylist speaking first — same data path, same receipts rule.
- Cost control: per-user daily budget, small model for routing, cache tool results.

## 8. Trust & safety stack (launch requirement)

- **Age**: birthday from signup. Under-13 blocked (already). Under-18: private default (already), **no photo posting** (looks + swatches blocked), no contact sync, no DMs (nobody has DMs).
- **Pipeline**: on-device SCA at selection → cloud image moderation pre-public → text moderation on comments/bios/captions → report queues with SLAs (S1-class content same-day) → audit_records on every action.
- **App Store 1.2 checklist**: filtering ✅ (pre-public moderation), reporting ✅, blocking ✅, developer contact + act-on-reports within 24h documented.
- **NCMEC runbook** written before needed (1.5 drafted it); reporting path + evidence preservation documented in `docs/runbook.md`.
- **UGC license** in ToS: users own photos, grant non-exclusive royalty-free license to host/display in-service; marketing use opt-in only.
- Moderation observability: queue depth, time-to-action, prevalence sampling — reviewed weekly.

## 9. Creators (product work only, no budget)

- Ship for them: linked socials (1.5), oEmbed, public collections, link cards, creator-friendly URLs (`glossed.app/@handle`).
- **Gifted/sponsored flag at item level** (`user_items.disclosure gifted|sponsored|null`): FTC-required disclosure renders wherever the item appears; **gifted entries are excluded from aggregate scoring** (filter in aggregate jobs), still visible on the creator's own profile. Sponsored content lives in curation surfaces, never rankings. The constraint is the marketing line.
- Hand-recruit micro-creators (1k–50k) with early access + flair.

## 10. Definition of done

- [ ] Moderation stack live end-to-end before any photo surface unlocks (hard gate)
- [ ] Looks + tags + feed + comments + likes/saves; minors restricted correctly (test grid)
- [ ] Contact matching with hashed numbers; invites; suggested-people upgraded with follow graph
- [ ] oEmbed video; gap cards with reason capture; seam module #1 (hair/skin)
- [ ] Stylist behind a feature flag with tool-cited answers only; budgets + spend caps
- [ ] Gifted-disclosure flag + aggregate exclusion; isolation + scope test grid extended to all new tables
