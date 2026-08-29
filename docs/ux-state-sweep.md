# UX state sweep — the grid

[GLO-110](https://linear.app/glossed/issue/GLO-110)'s deliverable. Every built
surface against empty, one, extreme and error, driven on the canon simulator
(iPhone 16 Pro, `0E1EF64B`) rather than reasoned about.

**Status: 24 of ~25 states driven. Not complete.** The unfinished rows are
listed as unfinished; a blank cell is a cell nobody has looked at, and saying
so is the point of the file.

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
  looks fine. Three of the four defects below were found that way — the screen
  looked plausible and contradicted something the code already claimed.

## The grid

| Surface | Empty | One | Extreme | Error |
|---|---|---|---|---|
| Shelf — bays | ✅ [GLO-166](https://linear.app/glossed/issue/GLO-166) | ✅ search narrowed | ✅ 11 items, 2 bays | ✅ search came up dry |
| Shelf — list | — | ✅ personal scope | — | — |
| Shelf — item sheet | — | ✅ remove offered | ✅ [GLO-160](https://linear.app/glossed/issue/GLO-160) | ✅ chip refused · ⬜ remove-failed |
| Ladder — search | ⬜ | — | — | ⬜ |
| Ladder — scan | — | — | — | ✅ no camera |
| Ladder — create | — | — | — | ✅ write failed |
| Logging sheet | ✅ nothing on file | ✅ sole variant · three shades | ✅ **40 shades** ([GLO-168](https://linear.app/glossed/issue/GLO-168)) | ✅ variants didn't load |
| Product page | ✅ not an anchor | — | — | ✅ evidence lookup failed |
| Import | — | — | ✅ messy list | ⬜ parse failed |
| **Dynamic Type** | — | — | ❌ [GLO-172](https://linear.app/glossed/issue/GLO-172) | — |

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
| `product · not an anchor category` | no fit block and no meter — shade is only evidence where a shade is meant to match skin | ✅ — and the evidence line still shows its n, so the page loses the *question*, not the *receipts*. Also [GLO-165](https://linear.app/glossed/issue/GLO-165)'s gate on the branch that PR did not change |

## Still to drive

`shelf · remove failed`, the ladder's search and near-match rungs,
`product · thin`, `import · pick a source` / `no matches` / `parse failed`.

**And every surface except the shelf at accessibility text sizes.** GLO-172 is
one screen's worth of a check nobody has run anywhere else.

## Two things that could not be driven honestly

- **A live failed remove.** Inducing a real network failure means taking the
  local stack down, and three sessions share it. The revert logic is covered by
  three tests (sheet stays, retry succeeds, a new sheet clears the failure).
- **The matched-barcode fit gap** ([GLO-16](https://linear.app/glossed/issue/GLO-16)'s note). It needs a barcode scan and
  the simulator has no camera.

Both are listed rather than quietly skipped, because a grid with an unmarked
cell reads as covered.
