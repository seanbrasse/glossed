# GLOSSED — Domain Model

Written per Handbook §3.2, before any schema. Sources: PRD v2.0 (Aug 25 2026), the GLOSSED design system + UI kit (Claude Design project, Aug 27 2026), and the design-review decisions that supersede the PRD where they conflict (see `tech/00-architecture.md` §2).

Vocabulary in this document is the schema vocabulary. If the PRD calls it a "face-off," the table is not called `comparisons`.

---

## 1. Vocabulary

| Term | Means precisely |
|---|---|
| **Domain** | One of `makeup / skincare / haircare / fragrance`. Drives category tree, chip vocabulary, matching axis, ranking rules. All four ship in V1 (design decision). |
| **Product** | A canonical thing a brand sells: "Fenty Pro Filt'r Soft Matte." Carries brand, category, domain, INCI. |
| **Variant** | Shade + size (makeup) / formulation + size + strength (skincare) / formulation + size (haircare) / concentration + size (fragrance). **Rankings, chips, fits, and swatches all point at the Variant, never the Product.** |
| **UserItem** | One user's relationship to one Variant: their bottle. Status, dates, rank position, note. |
| **Log** | The act of adding/updating a UserItem — the core contribution. A complete log = variant + (optional chips) + (fit, if anchor category). |
| **Chip** | A one-tap label. Two kinds, never conflated: **attribute** (fact about the product, derived from structured data, no valence) and **experience** (what happened to this person, like/dislike valence, conditioned on their body facts, week-stamped for skincare). |
| **Face-off** | One pairwise "which do you reach for?" answer between two UserItems in the same category. The only rating mechanic. No stars anywhere. |
| **Ranking** | A user's ordered list of UserItems within one category (optionally one scope bucket). Produced by face-offs. Personal first; aggregates are a recommendation output, not a leaderboard input below min-n. |
| **Anchor** | A shade the user wears in an anchor category (foundation, concealer, tinted moisturizer, skin tint, powder, BB/CC) + a **fit** verdict. The color-identity primitive. We store what people wear, never compute what they are. |
| **Fit** | `just right / too light / too dark / too pink / too yellow / too orange`. Captured at log time. |
| **Tone band** | Coarse 10-step band (internal name only — never "Monk" in UI). Fallback for users with no anchor; always overwritten by anchors, never the reverse. |
| **Shade claim** | Any user-facing population claim. Always names the exact shade or the data behind it ("12 people wear fenty 240"), never a persona. The "shade twins" concept was removed in design review. |
| **Collection** | User-created group of UserItems with a cover. Seasonal collections are collections, not ranking scopes. |
| **Routine** | Ordered set of UserItems with a slot (`am / pm / weekly / wash day`), layering position, start date. (1.5) |
| **Look** | Photo post with Variants tagged pin-style. (Phase 2) |
| **Swatch** | User photo of a shade on their skin, tagged to a Variant, tone band snapshotted at capture. (1.5) |
| **Scope (catalog)** | `personal / submitted / canonical`. Personal products exist only for their creator; canonical products are searchable by everyone and aggregate. |
| **Scope (privacy)** | `just_you / friends / public`, set per surface (looks, shelf, rankings, routines). |
| **Wear-in** | Per-category day count before a skincare item can be ranked. Field on the category. |
| **Gap card** | A dismissible suggestion derived from a set-difference between what people with your anchors/skin keep and what you've logged. |

## 2. Entities and relationships

```
Brand ─< Product ─< Variant ─< UserItem ─< ChipApplication (experience)
                     │              │
                     │              ├─ FaceOff (pair of UserItems, winner)
                     │              ├─ RankPosition (derived, per category list)
                     │              └─ Swatch (1.5)
                     ├─ VariantImage (catalog | user cutout)
                     ├─ UserShadeAnchor (user, variant, fit, season?)
                     └─ AttributeChip assignments (derived at ingest)
User ─ Profile (skin, hair, tone band, climate, birthday)
     ─ PrivacyScopes (four surfaces × three scopes)          (1.5)
     ─ Collection ─< CollectionItem
     ─ Routine ─< RoutineStep                                 (1.5 public, V1 private)
     ─ Follow (follower → followed)                           (1.5)
     ─ Look ─< LookTag                                        (2)
     ─ Comment / Report / Block / Mute                        (2)
Category (tree, per domain, wear_in_days, is_anchor, unlock rules)
FailedSearch · MergeCandidate · IngestSource · AuditRecord
```

Cardinality notes:

- A Product has ≥1 Variant even when it has no shades/sizes (a "default" variant), so nothing ever points at a Product for user data.
- UserItem is unique per (user, variant). Re-purchases update status/dates rather than duplicating.
- FaceOff references two UserItems of the same user + same category; immutable once written (skips recorded too).
- UserShadeAnchor is derived from UserItems in anchor categories with a fit logged — it is a *view* of log data, not a separate entry flow.

## 3. Lifecycle state machines

### 3.1 Product (catalog scope)

```
personal ──(3 distinct users log a matching product + reviewer approves)──> canonical
personal ──(user offers it)──> submitted ──(review)──> canonical | rejected(stays personal)
canonical ──(merge)──> merged-into(survivor)      · losing name kept as search alias, never hard-deleted
canonical ──(attach-as-variant)──> variant of another product
canonical ──(INCI mismatch detected)──> forked    · old keeps history, new starts clean, linked
```

- Nothing is ever blocked on review; personal products work instantly, never appear in anyone else's search, never aggregate.
- Late-binding promotion: when a personal product later matches a feed product, offer link + remap of the user's logs.

### 3.2 UserItem status

```
want_to_try → own → (skincare/haircare: in_wear_in, from started_on + category.wear_in_days) → rankable
own → finished | repurchased | retired(soft delete)
```

- Ranking unlock per category: `count(user items in category) >= 3` AND (non-skincare OR wear-in elapsed). Below 3: like/dislike + chips only.

### 3.3 Face-off / ranking

```
log new item → (category unlocked?) → 2–4 face-offs (binary insertion) → RankPosition updated
skip ("too close to call") → recorded, insertion falls back to neighbor midpoint
```

### 3.4 Account

```
visitor → onboarding (pre-signup: domains, anchor, [hair], [palette], payoff)
        → account (apple | phone OTP) + birthday
   birthday < 13y  → hard block (COPPA) — server enforced
   13–17           → restricted: private-by-default, no photo posting (2), no contact sync, no DMs ever
        → active → (user deletes) → deleted (anonymized; audit records persist with identifiers, personal fields redacted)
returning user → login (same two ways) → straight to discover; nothing re-asked
```

### 3.5 Content (Phase 2)

```
draft → on-device SCA check (photos) → cloud moderation → public
public → reported → reviewed → (removed | restored) ; reporter + poster notified
```

## 4. Permission matrix

Roles: `anon` (pre-signup onboarding only), `user`, `minor` (13–17, a restricted `user`), `reviewer` (catalog/merge queue + reports; internal), `service` (edge functions / jobs).

| Action | anon | user | minor | reviewer | service |
|---|---|---|---|---|---|
| Browse catalog, leaderboards (n-thresholded) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Onboarding payoff query (n for a variant) | ✅ | ✅ | ✅ | — | ✅ |
| Create account | ✅ | — | — | — | — |
| Log / chip / face-off / fit (own rows only) | — | ✅ | ✅ | — | — |
| Create personal product | — | ✅ | ✅ | — | — |
| Submit product to catalog | — | ✅ | ✅ | — | — |
| Read another user's items/rankings/routines | — | per privacy scope (1.5) | per scope | — | ✅ (aggregation only) |
| Post swatch (1.5) / look (2) / comment (2) | — | ✅ | **swatch/look: ❌** · comment: ✅ | — | — |
| Follow / contact import (1.5/2) | — | ✅ | follow ✅ / contacts ❌ | — | — |
| Report / block / mute (1.5+) | — | ✅ | ✅ | — | — |
| Merge / attach / fork / promote catalog rows | — | — | — | ✅ | ✅ (auto-band) |
| Act on reports | — | — | — | ✅ | — |
| Write aggregates / refresh materialized views | — | — | — | — | ✅ |

Authorization lives in the service layer (RLS + security-definer functions), never the UI. Hiding a button is presentation.

## 5. Data classification (per Handbook §9.2)

| Class | Entities | Consequences |
|---|---|---|
| **Public** | Brand, Product/Variant (canonical), Category, attribute chips, aggregate stats above min-n | none |
| **Internal** | FailedSearch, MergeCandidate, IngestSource, metrics events | access control |
| **Confidential** | UserItem, chips, face-offs, rankings, collections, routines, personal-scope products, follows | encryption at rest (platform default), access logging on reads by staff, RLS |
| **Regulated** | phone number, birthday, Apple identity, tone band + skin/hair profile, anchors + fit, swatch/look photos, contact-import data (2) | all of the above + retention rules + deletion rights + never in logs. Skin/hair/tone data is treated as sensitive personal data even where not statutorily biometric. **No biometric inference ever** (no selfie tone detection — BIPA/CUBI). Face photos are user content, not data: no analysis beyond the user's own tagging + moderation scanning. |

Uploaded photos: EXIF (incl. GPS) is stripped on device before upload, deliberately.

## 6. Retention and deletion

- **Account deletion**: UserItems, chips, face-offs, rankings, collections, routines, photos → destroyed. Their *contributions to aggregates* are recomputed on the next refresh (aggregates store no user identifiers). Audit records persist with pseudonymous identifiers, personal fields redacted.
- **Catalog** rows are never hard-deleted (shelves point at them): merge keeps aliases; delisted SKUs get `delisted_at`.
- **Phone number / birthday**: kept while account active (auth + age gate); destroyed on deletion.
- **Reports + moderation records**: outlive the content they describe (T&S), 2 years.
- **Backups**: daily, 14-day retention minimum, PITR on prod once real users exist; restore drill rehearsed on staging before launch and quarterly.
- **Export**: user can export their shelf as CSV (V1 feature, and the honest answer to "what if I leave").

## 7. Time

- Store UTC everywhere (`timestamptz`). `started_on` for wear-in is a **date** in the user's timezone at capture; wear-in unlocks compare dates, not instants. Birthday is a `date`, never a timestamp.
- User timezone stored on profile (from device at signup, updatable), used for notification scheduling later.
- "Week N" chip stamps derive from `started_on`, computed server-side: `floor((logged_date - started_on)/7) + 1`.
