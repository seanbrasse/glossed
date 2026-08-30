# Design-conformance audit — Discover

**Ticket** [GLO-107](https://linear.app/glossed/issue/GLO-107) · **Date** Aug 30 2026 · **Scope** the discover tab only

GLO-107 is the whole-app pass; this is its first slice. Later slices append
sections here rather than starting new files.

## How both sides were captured

**The kit side** — `G.Discover`, `G.Tune` and `G.Leaderboard` pulled as
*source* through `docs/DESIGN.md`'s `GetFile` recipe (the browser pane, the
`OmeletteService/GetFile` call, `screens.jsx` at 108,146 bytes). Copy, order,
sizes and tokens below are quoted from that source, not read off a
screenshot. `screen-map.html` was pulled the same way for the `note=`
captions.

**The app side** — `features/Discover/Sources/**`,
`features/Onboarding/Sources/Onboarding/UI/Tune*.swift`, and the composition
in `app/Glossed/Sources/App/AppShellDiscover.swift` /
`AppShellTune.swift` / `AppShellLeaderboard.swift`, read at
`feat/GLO-107-discover-parity` off `origin/main`.

**Not yet done for this slice:** the simulator drive. Every row below is a
source-to-source comparison. Measurement rows (grid gaps, mock heights) are
therefore marked as *unmeasured* rather than asserted in points — GLO-107's
"device points, not screenshot pixels" criterion is unmet for Discover and
that is a stated gap, not a silent one.

## The headline finding

`DiscoverView.swift`'s own doc comment says:

> `G.Discover` is the frame family; per the standing ruling the screen is
> workshopped in the PR rather than traced from a frame.

**`G.Discover` is a real, complete frame** — 3,413 bytes of it, quoted
throughout below. The no-frames ruling was invoked for a screen that has one.
That is the GLO-62 shape exactly, which GLO-107 names as the finding worth
looking for, and it is why five frame elements below are missing rather than
deliberately dropped.

This is not a claim that the built screen is wrong. Three deltas landed after
the frame was drawn and two of them override it (below). It is a claim that
nobody has ever put the two side by side, so nobody could tell which
differences were decisions.

## Which document wins where they disagree

`tech/00` §2's deltas supersede the PRD, and they postdate the kit. For
Discover, three matter:

- **Delta 15** — *"discovery is incorporated into the feed… No sections, no
  headers — a sectioned page of product cards is a store's shape."* This
  overrides the frame's `PICKED FOR YOU · FENTY 240 · 3B` section header.
- **Delta 19** — editorial carousels are allowed again, *"the headline must
  cite people."* Retailer format is fine, retailer voice is not. So a
  headline may return, but only as a claim with a population and a count.
  Under either delta the frame's header copy is superseded: it names the
  anchor (`FENTY 240 · 3B`) but carries no n.
- **Delta 12** — *"a card that cannot show its n does not render"*, with the
  wander as the one recorded exception.

**Delta 15 removed the header, not the door.** The `leaderboards →` link that
lived in that header row is a navigation affordance, not a section; it is
missing from the built screen and no delta accounts for its absence.

## `G.Discover` — element by element, in the frame's own order

| # | Frame says | App does | Verdict | Governing |
|---|---|---|---|---|
| 1 | `<Input placeholder="vibe search: dewy blush that lasts…" />`, the **first** element on the screen | nothing — no search anywhere on discover | **diverges** (missing) | frame + PRD §10 bullet 1, `Search + filters V1`. No delta touches it. See GLO-224 |
| 2 | `sharpen your matches` button → `go('tune')`; sub `skin type · concerns · brands — moved out of onboarding`; `background:var(--lilac-soft)`, `borderRadius:14`, chevron-right glyph | `TuneCard`, injected by the app at position 0. Copy is `SHARPEN YOUR MATCHES` (eyebrow) + `skin type, concerns, the brands you rate — three taps`; `Tokens.Support.butterSoft`; affordance is `tune →` | **diverges** (present, three cosmetic differences) | frame. Gated by `TuneGate` — correct and beyond the frame. See GLO-225 |
| 3 | `<Eyebrow color="var(--cherry-deep)">PICKED FOR YOU · FENTY 240 · 3B</Eyebrow>` | absent | **matches the governing rule, not the frame** | **delta 15** removes it; **delta 19** would only allow it back with an n. Correctly dropped |
| 4 | `leaderboards →` — mono 11, `--cherry-deep`, underlined, `go('leaderboard')` | absent. The board is reachable only as pick → product page → `onLeaderboard`, three taps deep, and only for that product's category | **diverges** (missing) | frame. Delta 15 removes the header this sat in, not the door. Built in this lane |
| 5 | `gridTemplateColumns:'1fr 1fr'`, `gap:'30px 16px'`; per cell `G.Mock h={98} rotate={[-3,2,3,-2][i]}` | one column of full-width `GlossedCard`s, each wrapping a horizontal `ProductCard` | **diverges** (layout) | no delta mandates one column — delta 15 forbids *sections*, not a grid. Unmeasured. See GLO-226 |
| 6 | per-cell `<Eyebrow>{c.type}</Eyebrow>` — `CREAM BLUSH`, `LIP OIL`, `CURL CREAM`, `CONCEALER` | absent | **diverges** (missing) | frame. `CatalogHit.categorySlug` is already on the wire, so this needs no new read. See GLO-226 |
| 7 | name `font-display` 800 / 18 / `lineHeight:1.05`; brand in mono under it | `ProductCard(meta:)` renders brand + name + variant | **matches** (in substance) | — |
| 8 | up to two `Chip`s per cell: one `kind:'attribute'` (`dewy`), one `kind:'like'` with `count:'×89'` (`lasts on combo`), `rotate={[-1,0.8]}` | absent | **diverges** (missing, blocked) | frame + PRD §03 *"chips become search"*. **Blocked**: `CatalogHit` carries no chips and `AggregatesRepository.payoff` is per-*variant*; a per-product chip read is a DataKit opening. See GLO-227 |
| 9 | hand aside, `font-hand` 19, `--cherry-deep`, `rotate(-1deg)`: `tags = what YOU look for. tap one to search it` | absent | **diverges** (missing, blocked) | frame. Depends on #8 and #1 — the sentence is only true once chips are tappable and search exists. See GLO-227 |
| 10 | `<GapCard title="pro filt'r soft matte" sub="fenty beauty · foundation · shade 240" n={12} thumb={…} onYes={()=>go('product')}/>` | absent from discover. **The `GapCard` primitive exists** in `DesignSystem/Primitives/HairTypePicker.swift`, fully built with its four dismiss reasons, and is referenced by nothing but the preview gallery | **frame vs PRD conflict — PRD wins** | PRD §10 marks gap cards **`V1.5`**; PRD §17 puts them in Phase 2. The frame draws a post-V1 element. Correctly absent from V1; the built-and-unused primitive is worth a note, not a fix. See GLO-228 |
| — | *(nothing)* | `Text("discover").font(Typography.display(30))` page title | **addition** | the frame has no page title — the nav labels the tab. Harmless; flagged for the workshop list |
| — | *(nothing)* | crosswalk card, `PEOPLE WHO WEAR WHAT YOU WEAR`, rows reading `also wear …` + `EvidenceLine(n:label:"wear both")` | **addition, correct** | PRD §05 + `tech/01` §9. Never says "your match", as §05 requires |
| — | *(nothing)* | trending teaser card → `TrendingView` | **addition** | PRD §10 marks trending `V1.5`; wired by #287. Renders only when the app supplies a destination |
| — | *(nothing)* | the wander: `basis == .exploration`, butter tint, the screen's one pop moment, `no evidence, just curiosity`, no n, exempt from dismissal | **addition, required** | delta 12's recorded exception + PRD §11 *"reserve an explicit exploration slot, labeled as such"* |
| — | *(nothing)* | empty state — `NOTHING PICKED YET` / `your picks build from what you log` | **addition, required** | delta 10. The map's stage-0 empty frame is the *shelf's*, not discover's |

## `G.Tune` — element by element

| Frame says | App does | Verdict |
|---|---|---|
| `← back`, mono 12, `--cherry-deep`, underlined | same | **matches** |
| `AFTER SIGNUP · NEVER BEFORE THE PAYOFF`, eyebrow, `--cherry-deep` | same string | **matches** |
| `sharpen your<br/>matches`, display 800 / 28 / `letterSpacing:-.02em` | `"sharpen your\nmatches"`, `Typography.display(28)`, `.tracking(-0.56)` | **matches** |
| hand aside `three taps, and none of it gated the payoff`, `rotate(-1deg)` | same string, same rotation | **matches** |
| `SKIN TYPE` + `Segmented(['oily','dry','combo','sensitive'])` | `SkinType.allCases` = `oily, dry, combo, sensitive` | **matches** |
| `CONCERNS` + `['acne','texture','redness','dark spots','fine lines','dryness']` | `TuneModel.concernOptions`, same six, same order | **matches** |
| `BRANDS YOU RATE` + nine hardcoded brands | brand chips sourced from the user's own shelf, most-shelved first, plus already-saved affinities | **diverges, deliberately and correctly** — the kit's nine are a fixture; you rate the brands you use |
| `save` block button | same, plus `saving…` and an error line | **matches** |
| mono `looks and swatches used to live here too — both moved to phase 1.5` | same string | **matches** |

`G.Tune` is the counter-example to the headline finding: it was built to its
frame, element for element, including the copy.

## Verdict roll-up

| Verdict | Count |
|---|---|
| matches | 9 |
| diverges — built in this lane | 1 (#4) |
| diverges — ticket filed, buildable | 3 (#1, #5+#6, #2) |
| diverges — ticket filed, blocked on a DataKit opening | 2 (#8, #9) |
| frame draws a post-V1 element; PRD phases it out | 1 (#10) |
| correctly superseded by a delta | 1 (#3) |
| additions beyond the frame, all justified | 5 |

## PRD §10 asks for things neither the frame nor the code has

Listed separately because these are not frame divergences.

| PRD §10 / §11 | State |
|---|---|
| **Search + filters** `V1` — *"by category, brand, skin type fit, chip attributes, price band. The filter learns."* | No search on discover at all. `CatalogRepository.search` exists and is public (name/brand FTS); category, chip-attribute and price-band filters do not. GLO-224 |
| **Leaderboards** `V1` — *"best-ranked per category… and the spicy one: lowest-ranked, with the chip reasons why"* | Built (`G.Leaderboard`, both boards, dislike reasons on the lowest). Only the door from discover was missing |
| **Attribute affinity is visible to the user** §11 — *"Visible, and it's a feature. Explains itself: '8 of your top 10 are fragrance-free.'"* | `AggregatesRepository.affinity()` is public, returns `[AffinityRow]` with the label, `nSignals` and the confidence `w` — **and is consumed by nothing in the app.** The receipts surface the PRD calls a feature is unbuilt. GLO-229 |
| **Gap cards** `V1.5` | Primitive built, unused. Correctly not on V1 discover. GLO-228 |
| Feed / seam / #shadetwins / creator curation `V2` | Out of Phase-1 scope; delta 11 pulls the *looks feed* into V1, tracked on the feed epic, not here |

## Open product questions this audit could not settle

1. **Does discover get its own search, or does search stay behind the +
   drawer?** The frame puts a search field first on discover; the app's only
   catalog search is the add-ladder's rung, which exists to *log* a product,
   not to browse one. These are different jobs on the same index.
2. **What does "vibe search" mean concretely?** The frame's placeholder,
   `vibe search: dewy blush that lasts…`, describes a chip-conditioned query
   (PRD §03: *"chips become search"*). `search_catalog` is name/brand FTS.
   Shipping the frame's placeholder over the built search would promise a
   capability we do not have — the GLO-178 line.
3. **One column or two?** The frame's grid is a browsing shape; the built
   stream is a feed shape, and delta 15 argued for the feed. Delta 15's
   objection was to *sections*, so a two-column stream is not obviously
   forbidden — but it is a look, and looks are Sean's.
4. **Is `avatar_seed`-style dead data the pattern here too?** `GapCard` and
   `affinity()` are both built, correct, and reachable by nothing. Each is
   either a missing surface or a dead artifact, and the answer differs.
