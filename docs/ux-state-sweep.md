# UX state sweep — the grid

[GLO-110](https://linear.app/glossed/issue/GLO-110)'s deliverable. Every built
surface against empty, one, extreme and error, driven on the canon simulator
(iPhone 16 Pro, `0E1EF64B`) rather than reasoned about.

**Status: 34 driven. Every named cell is now driven.** What is left is two
whole axes rather than scattered cells — Dynamic Type, run on exactly one
surface ([GLO-172](https://linear.app/glossed/issue/GLO-172)) and nowhere else,
and the ladder's transitions, which cannot be driven at all yet
([GLO-180](https://linear.app/glossed/issue/GLO-180)). The unfinished rows are
listed as unfinished; a blank cell is a cell nobody has looked at, and saying so
is the point of the file.

**One thing the grid cannot tell you, and it took driving to learn:** none of
the ladder cells below is a claim about *transitions*. The picker hosts every
rung bare, so `LadderFlowView` — where every rung-to-rung move actually lives —
has no fixture at all ([GLO-180](https://linear.app/glossed/issue/GLO-180)).
A ✅ on a ladder row means the rung renders and holds its promise, not that you
can get off it.

## Why the file exists

The project's three most expensive bugs were all the same shape — a state that
was never driven because it was not the happy path. [GLO-88](https://linear.app/glossed/issue/GLO-88)'s
variant sheet was pickable with the confirm off-screen. [GLO-68](https://linear.app/glossed/issue/GLO-68)'s
bay overflowed at five items. [GLO-96](https://linear.app/glossed/issue/GLO-96)'s
ladder resumed a stale flow. Each sat unnoticed until somebody drove it.

Two rules govern the cells:

- **A state that renders is not a state that works.** Every state must be
  *finishable*: if you can enter it, you must be able to leave it.
- **Check the state against its own stated promise**, not against whether it
  looks fine. Most of the defects below were found that way — the screen looked
  plausible and contradicted something the code already claimed, often a claim
  in the very comment above the line that broke it.

## The grid

| Surface | Empty | One | Extreme | Error |
|---|---|---|---|---|
| Shelf — bays | ✅ [GLO-166](https://linear.app/glossed/issue/GLO-166) | ✅ search narrowed | ✅ 11 items, 2 bays | ✅ search came up dry |
| Shelf — list | — | ✅ personal scope | — | — |
| Shelf — item sheet | — | ✅ remove offered | ✅ [GLO-160](https://linear.app/glossed/issue/GLO-160) | ✅ chip refused · ✅ remove failed |
| Ladder — search | ✅ nothing found | ✅ three matches | — | ✅ doctrine held · [GLO-179](https://linear.app/glossed/issue/GLO-179) no retry |
| Ladder — scan | — | — | — | ✅ no camera |
| Ladder — near match | ❌ [GLO-176](https://linear.app/glossed/issue/GLO-176) | ❌ [GLO-177](https://linear.app/glossed/issue/GLO-177) | — | — |
| Ladder — create | — | — | — | ✅ write failed |
| Logging sheet | ✅ nothing on file | ✅ sole variant · three shades | ✅ **40 shades** ([GLO-168](https://linear.app/glossed/issue/GLO-168)) | ✅ variants didn't load |
| Product page | ✅ not an anchor | ✅ thin sample | — | ✅ evidence lookup failed |
| Import — source pick | ❌ [GLO-178](https://linear.app/glossed/issue/GLO-178) | — | — | — |
| Import — parsed | ✅ nothing matched | — | ✅ messy list | ✅ parse failed |
| **Dynamic Type** | — | — | ❌ [GLO-172](https://linear.app/glossed/issue/GLO-172) | — |
| **Ladder transitions** | ⬜ [GLO-180](https://linear.app/glossed/issue/GLO-180) | ⬜ | ⬜ | ⬜ |

✅ driven and passing · ❌ driven and failing · ⬜ not yet driven · — not applicable

## What the sweep found

**[GLO-166](https://linear.app/glossed/issue/GLO-166) — the shelf goes blank four ways, and only one of them says so.** Fixed
in [#237](https://github.com/seanbrasse/glossed/pull/237). Turning all four domain chips off is four taps and produced a bare
screen. The rule was already written in `ShelfView` (*"a designed dead end, not
a blank shelf"*) and the gap was named in `searchCameUpEmpty`'s own comment. The
likeliest case in practice — a shelf that is all want-to-try, invisible because
[GLO-100](https://linear.app/glossed/issue/GLO-100) hides the wishlist — had no fixture at all.

**[GLO-165](https://linear.app/glossed/issue/GLO-165) — a fit control that could not save and did not say so.** Fixed in
[#236](https://github.com/seanbrasse/glossed/pull/236). Found reviewing my own PR mid-sweep, before it merged.

**[GLO-168](https://linear.app/glossed/issue/GLO-168) — GLO-88's regression had no fixture and no test.** Fixed in [#242](https://github.com/seanbrasse/glossed/pull/242).
The most-cited scar in the project was guarded by two private constants and a
comment, and the 40-shade case this ticket asks for by name was reachable only
by finding a real 40-shade product. Both now exist; driven to *finishable* at
forty.

**A fixture my own [GLO-165](https://linear.app/glossed/issue/GLO-165) fix silently broke.** `product · the evidence
lookup failed` lost its fit block. #236 gated the block on being answerable and
gave three fixtures a store to compensate — but the regex that did it matched
only call sites carrying an `evidence:` argument, and this one passes
`failure: .offline`. It hit `backed`, `thin` and `notAnAnchor`, and missed the
one anchor fixture that needed it. Nothing failed; the block simply stopped
being there. Found by driving the cell, four PRs later.

**[GLO-172](https://linear.app/glossed/issue/GLO-172) — at accessibility text sizes the shelf is unusable.** Open. The page
overflows and clips on both edges with no scroll: every product is off-screen
and the shelf shows four empty bays. The obvious fix repairs it completely and
regresses the default size, so it was reverted — details and three candidate
fixes on the ticket.

**[GLO-176](https://linear.app/glossed/issue/GLO-176) — the ladder asks for a name and accepts one letter of it.** Open, high. The
near-match rung is *"the only state with a field on it"*, and the field deletes
itself on the first keystroke: `needsAName` is `ladder.query.isEmpty && scannedGTIN == nil`,
the field binds `$model.query`, and `query.didSet` writes straight into
`ladder`. One character and the input is gone from the view tree, keyboard
dismissed, the rest of the typing lost — with no way back, because
`needsAName` can never be true again.

Driven one character at a time, which is the only reason it was caught. The
first pass typed twenty-two characters, got three candidates, and looked like
success — the stub returns the same matches for any non-empty query, so a
wrong answer wore the shape of a right one. **The same costume as the
`queued`/`pending` scar: the output was plausible, so the input went
unexamined.** Typing a single `l` is what made it visible.

The consequence is worse than lost keystrokes. `near_matches` needs
`similarity >= 0.3`, which one letter never clears, so the real outcome is an
empty list — and `isCandidateListTrustworthy` is *true* at that point, so the
screen vouches for a list built from one character and offers `none of these —
create it`. That is the duplicate this rung exists to prevent, on the rung
whose own comment calls it *"the last look before we let someone create a
duplicate."* Reachable without a scan: search with nothing typed → the scan
rung's escape → here.

**[GLO-177](https://linear.app/glossed/issue/GLO-177) — "check the photo" over three drawings.** Open. The near-match
eyebrow reads *"CHECK THE PHOTO, NOT THE NAME"* whenever the list loaded, but
the gate that produces it (`isCandidateListTrustworthy`) asks *"are these all
of them?"*, never *"is there a photo?"* — while its own doc comment says the
instruction must not appear when there are no photos to check. Counted against
the catalog: **430 of 497 brands have zero catalog images**, 993 products' worth,
and this rung assembles candidates *by brand*. So the screen routinely points
at a drawn mock and, in the same line, tells you not to trust the one thing
that does disambiguate — the per-candidate reason lines directly underneath it.

**[GLO-178](https://linear.app/glossed/issue/GLO-178) — a source you cannot supply.** Open, low. `screenshot of a haul ·
we read the text, you confirm` opens the same bare `TextEditor` as the other
two sources, with no photo picker anywhere. Photo extract is genuinely unbuilt
and genuinely tracked ([GLO-19](https://linear.app/glossed/issue/GLO-19)) — but
unlike the `add 4` affordance this sweep cleared on those grounds, this one
lands you on a screen that *looks* live (editable box, a counter ticking `we
read 0 lines`) and cannot accept what the card just named. The editor also has
no placeholder, while carrying `.accessibilityLabel("your list, one product per
line")` — VoiceOver is told what to type and nobody else is.

**[GLO-179](https://linear.app/glossed/issue/GLO-179) — "try again" with nothing to press.** Open, low. The search
rung's failed lookup is otherwise exemplary (see the triad below), but its
`no connection — try again in a sec.` has no retry control: the only recovery
is to edit a query that was already correct. Two sibling failure states — the
logging sheet's and the item sheet's — both give you a live `try again`. The
inconsistency is what makes it a defect rather than a preference.

**[GLO-180](https://linear.app/glossed/issue/GLO-180) — the instrument cannot reach the bug class it was built for.**
Open. `LadderFlowView` appears in exactly two files: itself and `AppShell`. The
picker hosts every rung bare, so no rung-to-rung transition is drivable without
the live stack. Two consequences showed up while driving: tapping a search hit
does nothing (nothing observes `pickedHit`), and tapping the escape advances the
progress rail while the body stays put — a state the real app cannot produce.
This file's own opening names [GLO-96](https://linear.app/glossed/issue/GLO-96),
*"the ladder resumed a stale flow"*, as one of the three bugs it exists to
prevent. That is a transition bug, and transitions are the one thing the grid
cannot currently speak to.

**Two stale fixture notes.** Fixed in [#238](https://github.com/seanbrasse/glossed/pull/238). The picker's notes are what a
driver checks the screen *against*, so a wrong one is worse than none.

## Checked and clean — with the promise that was checked

Recorded so nobody re-drives them, and because "clean" means a specific claim held.

| State | The promise | Held? |
|---|---|---|
| `logging sheet · nothing on file` | an honest dead-stop with a way back, not an unpressable button | ✅ message + `back` |
| `logging sheet · variants didn't load` | a failure is not an empty catalog — say so and keep the retry | ✅ names the failure, live `try again` |
| `ladder 4 · created, but the shelf write failed` | same product on retry, never a duplicate | ✅ and it is **tested**, `CreateRungModelTests.swift:268` |
| `ladder 2 · a phone that cannot scan` | never tell someone to point a camera they do not have | ✅ plus an escape row |
| `ladder 4 · create it` | the button stays down until brand + name + category exist | ✅ |
| `import · the kit's messy list` | "add 4" while a row says "pick the size" | ✅ **investigated and cleared** — `addableCount` includes `needsSize` per the kit, `onAdd` is empty, and the drawer says import lands with [GLO-19](https://linear.app/glossed/issue/GLO-19). Unbuilt, not broken |
| Shelf removal | soft delete, recoverable | ✅ psql: `deleted_at` set, row and status intact, gone from the view |
| `shelf · chips, skincare without a start date` | a reaction chip refuses to save without `started_on` | ✅ refused **and said why**: *"set a start date first — week 1 and week 10 are opposite facts"*. The chip did not toggle |
| `shelf · search came up dry` | a designed dead end that names the way onward, domains still visibly on | ✅ — and it still shows the *search* message rather than one of [GLO-166](https://linear.app/glossed/issue/GLO-166)'s new ones, which is the ordering that change introduced holding under its own test |
| `shelf · item sheet, remove offered` | the way off the shelf, quiet on purpose — `rank it` stays the pop moment | ✅ remove is a small underlined link; the fit section shows, which is [GLO-145](https://linear.app/glossed/issue/GLO-145)'s gate correct on a tried anchor |
| `shelf · search, narrowed to one bay` | the other bays drop out **whole**, the count follows — search narrows the shelf, never the catalog | ✅ two bays for `rhode`, count reads 2, domains still visibly on, ranks intact |
| `import · nothing matched` | five misses is a full ladder handoff, not an error — every row offers `fix →` | ✅ all five rows offer it, the header reads *"not enough data yet"*, and there is **no add button at all** rather than a dead one |
| `import · the parse failed` | must **not** list five misses — a parse that did not happen says nothing about the catalog | ✅ **lists no rows**, only *"no connection — try again in a sec."* |
| `shelf · item sheet, remove failed` | a remove that silently did not happen is an item that reappears next launch — the sheet stays up, says why, keeps the retry, and never shows the item as gone | ✅ all four. The item renders intact (`#1 of 3`, `own`), `no connection — try again in a sec.` sits under the pop moment, `try again` is live and wired to `onRemove`. `ShelfModel` also guards the stale case — `guard openItem?.id == id` means a failure from one sheet cannot land on whatever opened since |
| `ladder 1 · search` | a search that DID find things is not a dead end either: the escape row survives alongside the hits, and a personal-scope hit is visibly personal | ✅ `3 MATCHES IN THE CATALOG`, the butter escape row still last in the same list, and the personal product carries a `yours only` badge. **Finishability not provable here** — tapping a hit sets `pickedHit` and only `LadderFlowView` observes it ([GLO-180](https://linear.app/glossed/issue/GLO-180)) |
| `ladder 1 · nothing found` | a designed dead end that names the way onward, never an error | ✅ `nothing yet — we noted that you looked` — a demand signal, not a failure. And **no `0 MATCHES` eyebrow**: the count is gated on `matchCount > 0`, so an empty search never renders a zero the user could read as a fact about the catalog |
| `ladder 1 · the lookup failed` | must NOT read as an empty catalog — a failure is not evidence a product does not exist | ✅ on the doctrine: names the failure, suppresses the `nothing yet` miss copy, lists no rows, renders no zero count, keeps the escape. The retry clause is the one that failed ([GLO-179](https://linear.app/glossed/issue/GLO-179)) |
| `ladder 3 · arrived from a missed scan` | a GTIN and no name, so the rung asks for one and nothing pretends to know the name we do not have | ✅ on the *asking*: `the scan came up empty`, a real field, no invented candidates, and the eyebrow correctly drops to a bare `NEAR MATCHES` because the list cannot yet be vouched for. ❌ on the *answering* — [GLO-176](https://linear.app/glossed/issue/GLO-176). Note the gate works exactly as designed on this branch, which is what makes GLO-177 legible: it suppresses the photo line for an *unvouchable* list and not for a *photoless* one |
| `product · not enough reports yet` | a promise, not an apology — and the anchor count stays real, because that number is about you | ✅ and this is the clearest instance of the doctrine in the file. The cohort claim is **withheld entirely**: with `exactShadeCount: 2` the page renders no count at all, where the backed state renders `89 reports in your shade`. What survives is `match confidence · 3 of 5 anchors` — and `withFitCount` is *your* anchors carrying a fit, not a cohort (`ProductPageView`: *"the two halves of this page agree about the same user"*). A thin sample silences what others say and changes nothing about what you have logged |
| `product · not an anchor category` | no fit block and no meter — shade is only evidence where a shade is meant to match skin | ✅ — and the evidence line still shows its n, so the page loses the *question*, not the *receipts*. Also [GLO-165](https://linear.app/glossed/issue/GLO-165)'s gate on the branch that PR did not change |

## One rule, enforced in three places independently

The sweep's most reassuring result is not any single cell. Three different
surfaces, built at different times, all refuse to turn a failure into a
finding:

- `ladder · the lookup failed` — *"must NOT read as an empty catalog"*
- `product · the evidence lookup failed` — *"we did not ask, so we know nothing"*
- `import · the parse failed` — lists **no** rows rather than five misses

Same doctrine, three independent implementations, all holding — and the first
of the three is no longer taken on trust. It was recorded from its own comment
in the previous round; this round drove it, and it holds for a reason worth
naming: the search rung suppresses *two* different things at once, the `nothing
yet` miss copy **and** the match count, because `matchCount > 0` gates the
eyebrow. A failed lookup that rendered `0 MATCHES IN THE CATALOG` would satisfy
the letter of the rule and break it completely. That is the
posture `domain.md` asks for — evidence is a claim, and a failure is not
evidence of absence — surviving contact with three separate authors.

## Still to drive

Every named cell from the last round is done. Two things remain, and both are
axes rather than cells:

**Every surface except the shelf at accessibility text sizes.**
[GLO-172](https://linear.app/glossed/issue/GLO-172) is one screen's worth of a
check nobody has run anywhere else, and it found the shelf unusable. Nine other
surfaces have never been looked at above the default size.
`xcrun simctl ui <udid> content_size accessibility-extra-large` — underscore,
not a hyphen.

**Every ladder transition.** [GLO-180](https://linear.app/glossed/issue/GLO-180)
— not drivable from the picker at all today, so it needs the fixture before it
needs the sweep.

## What this round changed about how to drive a cell

Three things, all learned the expensive way:

**Type one character, not a word.** The near-match field bug survived a
twenty-two character drive that produced three candidates and looked entirely
correct, because the stub answers any non-empty query the same way. The
smallest possible input is the one that separates "the screen handled it" from
"the screen handled the first byte of it".

**A stub's plausible output proves nothing about the input.** Same shape as
session 8's `queued`/`pending` and session 11's fabricated migration deficit: a
result that looks right stops you checking what produced it. When a fixture
cannot vary its answer, the answer is not evidence.

**Ask what hosts the screen before calling a cell finishable.** Half the ladder
rows in the grid above cannot be driven to their next state at all, and that was
invisible until a tap did nothing. A picker entry that constructs a view
directly is testing the view, not the flow — and the grid should say which one
it means.

## Two things that could not be driven honestly

- **A live failed remove.** Inducing a real network failure means taking the
  local stack down, and three sessions share it. The revert logic is covered by
  three tests (sheet stays, retry succeeds, a new sheet clears the failure).
- **The matched-barcode fit gap** ([GLO-16](https://linear.app/glossed/issue/GLO-16)'s note). It needs a barcode scan and
  the simulator has no camera.

Both are listed rather than quietly skipped, because a grid with an unmarked
cell reads as covered.
