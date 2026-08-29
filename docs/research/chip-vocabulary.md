# Experience-chip vocabulary — research and rulings

GLO-154. The reasoning behind every row in `experience_chips`. The SQL in
`supabase/seed.sql` is generated from this document; when the two disagree,
this one is wrong and should be corrected to match what shipped.

---

## 1. The arithmetic that started it

`experience_chips` holds **10 rows, every one domain-wide** (`category_id`
null), against **22 categories**. Makeup's ten categories share three chips;
haircare's three share two.

What that costs, in the app as it stands:

| you logged | you are offered | what you cannot say |
|---|---|---|
| mascara | oxidized on me · creased by 2pm · lasted all day | flaked · smudged under my eyes · clumped · held my curl |
| sunscreen | purged then cleared · broke me out · pilled under makeup | **white cast** |
| conditioner | no crunch · weighed my hair down | detangled · slip · greasy roots |
| fragrance | lasts 6h · fades fast | projection, and "turned on my skin" |

Two of mascara's three offered chips are not facts about mascara. "Oxidized"
describes a foundation shifting orange as it reacts with skin oils over hours;
mascara does not do it. The user's only honest move is to tap nothing.

This is not a polish item. `docs/domain.md` and tech/01 §5 both say **chips are
queries** — they compile to SQL over `item_chips` and the aggregates, and they
are the stated search moat: *"foundations that don't oxidize, rated by people
with my skin."* A vocabulary that cannot say "white cast" can never answer the
sunscreen version of that question. Nineteen of our 22 categories currently
contribute nothing to the moat.

## 2. What earns a chip

A chip must be all three. Any one of them missing and it is noise:

1. **Variable** — it discriminates *between products in that category*.
   "Has SPF" fails: it is true or false from the label, identically for
   everyone. That is an attribute chip, derived from structured fields, and it
   lives in a different table with a different pipeline.
2. **Observable without instruments** — the owner knows it from having worn
   it. "Non-comedogenic" fails; "clogged my pores" passes. (Comedogenicity
   ships in the data and is deliberately never surfaced — domain.md.)
3. **Actionable for a stranger** — it changes someone else's buy decision.
   "Nice packaging" fails. "Stung my eyes" passes.

Two corollaries that did real work below:

- **Prefer the specific noun to the general adjective.** "Poor wear" is
  unsearchable and means eight different things. "Smudged under my eyes" is one
  thing, and it is the thing someone is searching for.
- **Name the failure the way the owner would say it to a friend**, not the way
  a lab would. The kit's voice is the owner's voice.

## 3. Findings

### 3.1 Some chips are mis-scoped, not missing

The interesting half of this work is **narrowing**, not inserting. Five of the
ten existing rows are filed domain-wide but describe one category:

| chip | filed | actually about |
|---|---|---|
| oxidized on me | all makeup | foundation (and concealer) |
| creased by 2pm | all makeup | concealer (and eyeshadow) |
| purged then cleared | all skincare | actives — serum, treatment |
| pilled under makeup | all skincare | moisturizer (and serum, sunscreen, eye) |
| no crunch | all haircare | styler |

Narrowing is safe. `item_chips` foreign-keys the chip **id**, not its scope, so
a chip already applied keeps rendering with its label intact; only the picker
narrows. Verified against the one test coupled to the table
(`shelf_isolation.test.sql:44`), which resolves `oxidized-on-me` **by slug** for
an RLS-denial assertion — the narrowing cannot reach it.

Five rows stay genuinely domain-wide, because they are true of every category
in their domain: **lasted all day** (makeup), **broke me out** (skincare),
**weighed my hair down** (haircare), **lasts 6h** and **fades fast**
(fragrance).

### 3.2 The schema allows one category per chip, and that is fine

`experience_chips.category_id` is a single nullable FK and `slug` is unique, so
a chip true of exactly two categories cannot point at both. The resolution:
**duplicate the row under a category-prefixed slug, sharing the human label.**
"Oxidized on me" becomes `oxidized-on-me` (foundation) and
`concealer-oxidized` (concealer) — one label, two rows.

This is harmless for aggregates, and worth saying why rather than assuming it:
`agg_variant_stats.chip_counts` is keyed per **variant**, and a variant belongs
to exactly one category. Two rows that never co-occur on the same variant can
never split a count.

Convention adopted: **new category-scoped slugs are prefixed with the category**
(`mascara-flaked`, `sunscreen-white-cast`). The five surviving original slugs
keep their names unprefixed — renaming them would break nothing today but would
sever the one thing slugs are for, which is stable identity across time.

### 3.3 Fragrance is collapsing two independent axes into one

Today: `lasts 6h` / `fades fast`. That is **longevity** — how long the scent
lives on skin. The fragrance world separates it from **projection/sillage** —
how far it travels off the wearer. They are independent: a scent can last nine
hours and never leave a two-inch radius. "Stays a skin scent" and "fades fast"
are different complaints with different buyers, and today they are one chip.

Also unsayable and heavily discussed: **"turned on my skin"** — the same juice
going sour, soapy, or powdery on one wearer and not another. It is the most
personal fact in the domain and therefore the one a stranger most needs
cohort-matched, which is precisely what our aggregates are for.

### 3.4 The like/dislike binary holds — by naming arcs, or by splitting

`chip_valence` has exactly two cases, and `ShelfChip.init(_:)` in
`features/Shelf` maps them case-by-case, so a third valence would be a compile
error there rather than a silent default. Good. **No valence change here.**

Some experiences are genuinely not binary. Two patterns cover every case found:

- **Name the arc in one chip.** "Purged then cleared" is filed `like` and its
  first half is a bad experience. It works because the chip describes the whole
  shape. Its opposite is not "did not purge" — it is
  **"purged and never cleared"**, and both now exist for `treatment`.
- **Split into a matched pair on the same axis.** Sunscreen gets both
  "no white cast on me" (like) and "white cast on me" (dislike). A neutral
  "has a white cast" would be useless: the whole point is that the same product
  casts on one person and not another, so the *valence* carries the personal
  half. Same pattern for styler's "no crunch" / "crunchy cast".

### 3.5 Balance is a design constraint, not an accident

An all-dislike category turns the section into a complaint form, and people
stop opening it. Target **6–8 scoped chips per category, roughly balanced**.

Foundation and mascara are deliberately dislike-heavy (5 of 8) because they
genuinely have more distinct, nameable failure modes than successes — a
foundation succeeds by being unremarkable and fails in six specific ways. That
is a fact about the products, not a mood.

### 3.6 Ordering will read badly, and it is not this ticket's to fix

`CatalogRepository.chipVocabulary` ends `.order("label")`. With 10 chips that is
invisible. With ~8 scoped chips plus domain-wide ones, likes and dislikes will
interleave alphabetically — "clumped, flaked, held my curl, smudged under my
eyes" reads as a jumble rather than two groups. Flagged to
`glo-145-fitsection-gate` and left alone here: it is a client ordering decision
on a frozen-core query, and plausibly Sean's call on the section's feel.

## 4. Where the rows live — `seed.sql`, not a migration

No migration in this repo has ever inserted into a reference table:

```
grep -n "insert into \(categories\|experience_chips\|attribute_chips\|brands\)" \
  supabase/migrations/*.sql   →  (nothing)
```

Every reference row — the 22 categories, the brands, all 10 chips — is in
`supabase/seed.sql`, and both prior vocabulary expansions (GLO-81's lip
category, GLO-102's nine-category growth) were seed edits carrying their ticket
reasoning in comments. **Migrations here are pure DDL.** This ticket follows
that convention rather than inventing a data-migration pattern for one table,
and therefore never contends for the one-open-migration-PR slot.

**`seed.sql` is not deferred, and this is the part that is easy to get wrong.**
CI rebuilds a fresh database from migrations + seed on every PR touching
`supabase/(migrations|tests|seed)`. The moment this merges it is what every
subsequent PR's suite runs against — so the bar is **the full suite passes**,
not "my tests pass". Known-good baseline before this work, to be re-confirmed
after: exactly two pre-existing drive-drift failures, `shelf_isolation` test 4
and `shelf_view` test 14. **A third failure belongs to this ticket.**

Locally the rows go in by `psql` against the running database — additive
inserts and `category_id` updates, no DDL — so **no `supabase db reset`**, none
of the ~50-minute catalog restore in HANDOFF §9, and none of the shared
fixtures other sessions depend on are disturbed.

### Flagged, deliberately unsolved

`seed.sql` is local-only; a hosted project never runs it. So **no** reference
data in this repo has a production path — categories included. That is a real
gap, bigger than chips, and it wants Sean's ruling on whether reference data
becomes a migration pattern. Solving it inside a vocabulary ticket would be the
wrong place to set that precedent.

**Since confirmed against hosted, and it is worse than "no path" — there is no
data.** `glossed-phase-1-1fbaa3-cd` checked rather than inferring: hosted holds
**zero** brands, products, variants, categories, and `experience_chips`, behind
30 migrations of schema. Filed as GLO-158. The reason it matters here is that
`categories` and `experience_chips` are not sample data, they are *vocabulary* —
zero categories means no `is_anchor`, no `wear_in_days`, and nowhere to log a
product; the 171 chips below do not exist there at all. And every consequence is
**silent**: `payoff_for_variant()` returns `evidence_backed=false`, browse
returns nothing, and each is indistinguishable from "correct, just early."

Worth stating plainly: the status quo — seed stays local/CI, hosted gets
populated by hand once — is a choice nobody made, and it starts rotting the
moment someone edits `seed.sql`, which is what this document does.

## 5. The client needs no changes

`ShelfChipStore.repository(shelf:catalog:)` (live as of #210) resolves the
item's category slug → id, then calls
`CatalogRepository.chipVocabulary(domain:categoryID:)`, whose filter is
`.or("category_id.is.null,category_id.eq.<id>")`. A foundation therefore
receives the domain-wide chips **and** its own. These rows light that path up
with zero Swift changes.

**This data is the first thing that can falsify that path.** #210 could not:
with all 10 rows domain-wide, narrowing and not-narrowing return an identical
list and the screen is byte-identical either way, so the branch is covered by
two unit tests and nothing else. The drive proof is therefore specified as:
log a mascara **and** a foundation, and confirm the mascara does *not* offer
the foundation-scoped chips. **Absence is the load-bearing half** — a
domain-wide chip appearing proves only the `category_id.is.null` side of the
`or` — which is why it takes two products and not one.

Note for whoever drives it: chips render only for **tried** items
(`liveStatus.isTried`, GLO-87). A `want_to_try` fixture shows no chip section
at all. Expected, not a bug in the data.
