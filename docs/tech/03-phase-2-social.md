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

## 2. Feed

- Priority: friends + follows → suggested similar-skin people → products/brands. Cold start leans entirely on suggested people (new users have zero friends).
- **Implementation: fan-out on read.** At this scale a per-request query beats maintained timelines: `(posts from follows) UNION (posts from suggested cohort) ORDER BY recency + light scoring`, keyset-paginated, cached per user for minutes. No dwell/scroll signals collected — ranking inputs are follows, cohort match, and recency only (the "no engagement optimization" positioning is architectural, not just copy).
- Feed cards = the kit's Feed frame: poster + reason line ("people in your shade" naming the data, never a twin persona), photo stack, caption, tagged products expander, like/save/share.
- Likes/saves: `look_likes`, `look_saves` — saves feed the taste profile (weak signal), likes are social only.

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
