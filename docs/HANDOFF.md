# Session handoff — Aug 28 2026 (second session)

Where Phase 1 stands, what to do next, and the decisions a new session would
otherwise have to rediscover. Read `docs/README.md` first for the design; this
file is only about state.

## 0. Read this before you build a screen

**Open the frame first.** [`docs/DESIGN.md`](DESIGN.md) has the design kit's URL
and — more importantly — how to read `screens.jsx` **as source**, which gives
you exact copy, sizes and tokens instead of a screenshot to squint at.

The route in `DESIGN.md` (read the code viewer's `<textarea>`) **no longer
works**: the viewer moved into a cross-origin frame that the browser pane's
`javascript_tool` cannot reach. What works, and what GLO-62 was built from, is
the project's own API, called from the pane with the session's cookies:

```js
// with any page of the design project open in the browser pane
const r = await fetch('/design/anthropic.omelette.api.v1alpha.OmeletteService/GetFile', {
  method: 'POST', credentials: 'include',
  headers: {'content-type': 'application/json'},
  body: JSON.stringify({projectId: '38230b94-09d2-4776-9d21-be0722ba54f2',
                        path: 'ui_kits/glossed-app/screens.jsx'})});
const {content} = await r.json();                       // base64
const src = new TextDecoder().decode(Uint8Array.from(atob(content), c => c.charCodeAt(0)));
```

`ListFiles` takes `{projectId, path}` and lists a directory. `screen-map.html`
comes back the same way, captions included — which is the part the frames alone
do not carry. Both are exact, both are ~100KB, and slicing by symbol
(`src.indexOf('G.Shelf = function')`) is how to read one screen at a time.

This is not a nicety. An earlier session could not reach the kit, built the
whole submission ladder from the primitives instead, and produced screens that
use every token correctly and look nothing like the design. That is
[GLO-62](https://linear.app/glossed/issue/GLO-62), and it is a rework, not a
polish pass. **If you cannot open the frame, stop and say so.**

Every UI ticket now names its `G.<Screen>` symbol and quotes the frame's
structure. The PRD sections that constrain each screen are quoted there too,
because the PRD is not in this repo (§9).

## 1. Where to start

Everything is tracked in **Linear**, not GitHub Issues:
workspace [glossed](https://linear.app/glossed), team **GLO**, project
**GLOSSED — Phase 1: The Journal**. Every ticket carries its design frame, its
PRD references, and what is blocking it.

Next tickets, in dependency order:

| Ticket | Why it is next |
|---|---|
| **[GLO-66](https://linear.app/glossed/issue/GLO-66) · [GLO-63](https://linear.app/glossed/issue/GLO-63) · [GLO-60](https://linear.app/glossed/issue/GLO-60)** — one door | **Start here.** Three tickets all want the frozen core opened, and it should open *once*. GLO-66 is the biggest: `ShelfRepository.items()` returns a variant id and a status, so **the shelf cannot render one row** and every screen built on it runs on fixtures. Wants a `security_invoker` view, so it is a migration ticket too |
| [GLO-56](https://linear.app/glossed/issue/GLO-56) who owns the shade/size pick | A decision, not code, and it now blocks **three** screens: the ladder's search rung, import's `needsSize` lines, and the shelf's logging sheet |
| [GLO-21](https://linear.app/glossed/issue/GLO-21) PR 1 only — `core/Tracking` | Scheduled last, needed first. Every feature ticket has event criteria and `core/` has no Tracking package, so four screens have shipped with no events at all. Splitting its PR 1 out is cheaper than retrofitting six packages — see the comment on the ticket |
| [GLO-14](https://linear.app/glossed/issue/GLO-14) catalog ingest | **The last genuinely unblocked lane.** Server-only, parallel with all iOS work. Wants a migration slot and a `read-the-damn-docs` pass before any Claude API code |
| [GLO-67](https://linear.app/glossed/issue/GLO-67) fit: multi-axis or one? · [GLO-68](https://linear.app/glossed/issue/GLO-68) ✅ · [GLO-69](https://linear.app/glossed/issue/GLO-69) the ✿ | Three design decisions found by building. GLO-67 is the substantive one: the kit's fit control is multi-axis, `item_fits` stores one row |
| [GLO-16](https://linear.app/glossed/issue/GLO-16) shelf · [GLO-47](https://linear.app/glossed/issue/GLO-47) product page · [GLO-19](https://linear.app/glossed/issue/GLO-19) import | **Screens built to the frames.** What remains on each is blocked — `core/Media` + R2, the fit write, the Share Extension's App ID, events |
| [GLO-62](https://linear.app/glossed/issue/GLO-62) ✅ · [GLO-65](https://linear.app/glossed/issue/GLO-65) ✅ | Ladder rework and the screen picker. Done |
| [GLO-15](https://linear.app/glossed/issue/GLO-15) submission ladder | Rungs 0–2 merged and reworked to the frames. The create rung is not buildable (GLO-60) |
| [GLO-48](https://linear.app/glossed/issue/GLO-48) catalog images + R2 | Presign done. The rest **needs a human with the Cloudflare account** — see §9 |

**Blocked on a human, not on code:**
[GLO-50](https://linear.app/glossed/issue/GLO-50) App Store Connect — the Sign in
with Apple capability on the App ID gates [GLO-23](https://linear.app/glossed/issue/GLO-23)
(auth flows), which gates [GLO-18](https://linear.app/glossed/issue/GLO-18)
(onboarding). Everything else routes around it.

## 2. What exists

**70 PRs merged, all CI-green.** `main` is the only long-lived branch.

| Layer | State |
|---|---|
| Schema | 6 migrations, all applied to the hosted project. 49 pgTAP assertions. No open migration PR — the slot is free, and three tickets want it. |
| `core/DataKit` | **FROZEN** — see §4. 23 tests. Three tickets queued against it (GLO-60, GLO-63, GLO-66); open it once. |
| `core/DesignSystem` | Tokens, 3 bundled fonts, 28 primitives, 31 tests. `ProductMock` is what the frames draw. No icon set ([GLO-64](https://linear.app/glossed/issue/GLO-64)); `Caveat` cannot draw the kit's ✿ ([GLO-69](https://linear.app/glossed/issue/GLO-69)). |
| `core/Media`, `core/Tracking` | **Do not exist.** Media needs R2 (§9); Tracking is owned by GLO-21 and needed by everything. |
| `features/Ranking` | Complete: engine, rules, session, view. 29 tests. |
| `features/AddLadder` | Rungs 0–2, all built to the kit frames. 78 tests. Create rung blocked (GLO-60). |
| `features/Shelf` | Bays, list, filter, sort, item sheet — the whole screen. 41 tests. |
| `features/ProductPage` | Hero, evidence card, fit block, actions. 11 tests. **The only screen with a live data source** (`payoff_for_variant`). |
| `features/Import` | Source pick, paste, per-line resolution, ladder handoff. 12 tests. |
| `app/Glossed` | `#if DEBUG` screen picker — 16 states, two taps each. Release root is still `PlaceholderView` until onboarding (GLO-18). |
| `supabase/functions` | `storage_presign` only. 14 Deno tests. **Not deployed** (§9). |

**Every feature screen except the product page renders from fixtures**, because
GLO-66 has not landed. That is deliberate and the seams are declared — each
feature owns a protocol naming exactly what it needs — but it means *nothing in
the app is wired to real data yet*.

**Hosted Supabase**: project `glossed`, us-east-1. The project ref lives in the
Supabase dashboard and in `.env`, deliberately not written down here — RLS is
what actually protects the data, but a public repo is no place to hand someone
a target. Migrations are applied **manually via the Supabase MCP after each
merge**; [GLO-46](https://linear.app/glossed/issue/GLO-46) replaces that with a
CI `db push`. Never apply `seed.sql` to it — the seed creates fake auth users
and is local/staging only.

## 3. How this session worked (worth repeating)

- Branches `feat/GLO-<n>-desc`, conventional commits, squash merge.
- **PRs ≤5 files / 400 lines.** `size-override` was used three times, each with
  the reason written at the top of the PR body: one where splitting would have
  separated a screen from the model it exists to render, one where any split
  ships a non-compiling intermediate, one where 223 of the counted lines were a
  file move that SwiftLint's own `file_length` rule forced. **The label is for
  the case where splitting makes the review worse, not for convenience** — and
  saying which of those it is, in the body, is the whole point.
- **Stack PRs when one idea spans layers.** DesignSystem primitive → feature
  model → feature view → picker entry, each its own PR, each retargeted at
  `main` as the one below it merges. `gh pr edit <n> --base main` **before**
  merging the parent, or GitHub closes the child and will not reopen it.
- Migrations are a global lock: one open migration PR at a time.
- **The user authorized self-merge on green CI for this session.** The handbook
  default is a human read on every PR. Without explicit authorization, do not
  self-merge.

### The loop that worked

For every screen, in this order:

1. **Open the frame** (§0) and read it as source. Not the tokens — the frame.
2. **Read the frame against the schema and the frozen core** *before* writing
   anything. Three of this session's seven new tickets came from that step, and
   each would otherwise have been discovered halfway through an implementation.
3. Build the model first, with the rules as pure functions and the data source
   behind a feature-owned protocol.
4. Build the view to the frame's own numbers, named once rather than scattered.
5. **Run it on a simulator and drive it.** Not a screenshot — tap the thing.
6. Add the state to the debug picker (§5) so it stays caught.
7. Say in the PR which frame it was built to, and where the two differ, why.

## 4. DataKit is frozen

`core/DataKit` is the one path every query takes. Do not modify it. If a feature
needs data it does not expose, that is a ticket against DataKit reviewed on its
own — not an edit made in passing. The reasoning is in `core/CLAUDE.md`; the
short version is that a missing session check there stops being a bug and
becomes a data leak.

Business rules do not belong in it either. Ranking order, wear-in gating and
unlock thresholds live in the features that own them.

**Three changes are queued against it**, bundled into
[GLO-60](https://linear.app/glossed/issue/GLO-60) so the core is opened once
rather than three times. One of them is not a nicety:
`PersonalProductDraft` requires a `brandID`, and nothing on `CatalogRepository`
returns brands — `search_catalog` gives `brand_name` as a string with no id. So
the create rung's "brand typeahead FK, no free-text brands" **cannot be built at
all**, and GLO-15 cannot close until that lands.

## 5. The automated recap earns its keep — read it

**It is manual now, not automatic** (Aug 28). Each run is a full Sonnet agent at
30 turns billed to a *personal* Anthropic key, and a busy agent session opens a
dozen PRs — plus a close/reopen for every recap that came back a stub. That
outran what the review was worth paying for on every PR. Ask for one where it
matters:

```bash
gh workflow run visual-recap -f pr=123
```

It still posts the same thing: mermaid diagram, file map by layer, schema
deltas, risk-ordered review notes.

It has now caught four real bugs, and they are all one family: **a name
claiming more certainty than the code can supply.** Two sub-shapes, worth
telling apart because the fixes differ.

*A guess reported as a statement.* A placement the system guessed recorded as
one the user stated — first for comparison-cap exhaustion, then, in the very fix
for the first, for skips, because a skip collapses the search range exactly as a
resolved comparison does. The fix adds a flag that admits the uncertainty.

*An attempt reported as an achievement.* `SearchRung` returned
`recordedMiss: true` after calling `recordFailedSearch` — which is `try?` inside
frozen DataKit and swallows its own transport errors, so the layer above cannot
know whether the miss was recorded. And `SearchRungModel` re-derived "is this a
miss" from the raw query while the rung decides from the *tidied* one, so `" a "`
would have claimed a miss for a search that never ran. The fix here *removes* a
claim rather than adding a flag — rename to what is actually known, or delete
the second implementation of the rule. Prefer this shape where it is available.

Treat its findings as review, not decoration: act on them before merging. If
acting on them pushes the PR past 400 lines, that is what `size-override` with a
written reason is for — trimming the reasoning the review asked for to hit a
number defeats the point of both.

Two mechanical facts:
- It **refuses to run on any PR that modifies workflow files** (a sound guard:
  otherwise a PR could rewrite the workflow to exfiltrate the key). Workflow
  changes cannot test themselves; the next feature PR is the check.
- **A green `recap` run does not prove a recap was posted.** Seen twice
  ([#43](https://github.com/seanbrasse/glossed/pull/43),
  [#45](https://github.com/seanbrasse/glossed/pull/45)): the agent spent its
  turns working out how to pipe a body into `gh pr comment`, left a stub, and
  exited green. The prompt now tells it to write the body to a file and forbids
  test comments ([GLO-59](https://linear.app/glossed/issue/GLO-59)), but look for
  the comment rather than the check mark.

**Since it no longer runs automatically, the PR body's Visual plan section is
the only shape-of-the-change artifact on most PRs.** Hold it to that bar.

### With the recap manual, you are the review

Turning it off ([#51](https://github.com/seanbrasse/glossed/pull/51)) removed the
only automated review these PRs had. It caught five real bugs in one session, so
the loss is real. Two things partly cover it:

- **The PR body's Visual plan section is now the only shape-of-the-change
  artifact on most PRs.** Write it like someone will rely on it, because they
  will.
- **Run the thing on a simulator.** Every UI bug this session that mattered was
  found by looking at the screen, not by a test: a doubled heading, iOS
  autocapitalising a brand name into a miss, a rung that never searched on
  appear, and copy instructing a phone that cannot scan to scan.

  It held on the next session too. GLO-62's rework was looked at four times and
  the two defects that came out of it were both invisible to tests: an escape
  row nobody could pick out of a list, and a near-match list whose products all
  drew as the same pink dropper — on the screen whose eyebrow says *check the
  photo, not the name*.

  **There is now somewhere to look.** [GLO-65](https://linear.app/glossed/issue/GLO-65)
  landed: debug builds open on a screen picker with **16 states**, each carrying
  a note saying what the state is *for*. Use it, and add to it — an entry is
  cheap and it is the only thing that keeps a state from silently regressing.

  **Every UI defect this project has had needed a particular state, and none of
  them was expressible as an assertion:**

  | defect | why no test would have caught it |
  |---|---|
  | an escape row nobody could pick out of a list | it rendered correctly; it just did not stand out |
  | a near-match list where every product drew as the same pink dropper | each row was individually right |
  | a brand sticker running under the product name | only at one scale, with one long brand |
  | a primary action under the home indicator | layout correct; the OS overlaps it |
  | copy telling a phone with no camera to point its camera | the right string, for a different device |
  | a shelf overflowing at five while half of it was empty | five items is what the kit says |
  | a bay packed on one width and drawn at another | nine items fitted; the shelf was still short |

  The last two are the ones to learn from: **both were found by looking at a
  screen that already passed every test**, and the second was a bug I introduced
  while fixing the first. A number used in two places has to be the same number.

## 6. CI economics

The repo is **public**, so Actions minutes are free and this is now about speed
and noise rather than spend. The shape is still worth knowing: measured over 98
runs, the macOS iOS build was **87% of billed minutes**, because macOS bills at
**10×** and each run costs ~21 minutes.

Already in place: a concurrency group cancels superseded runs; a cheap Ubuntu
`scope` job gates the macOS build on Swift changes and the database suite on
`supabase/` changes; CI no longer re-runs on push to `main` (a squash-merge has
identical content to the PR just tested). Skipped jobs cost nothing.

If the repo ever goes private again, the macOS build is the only thing that
matters, and batching pushes is the single biggest lever.

## 7. Open threads

| Item | Where |
|---|---|
| **Nothing is wired to real data** | [GLO-66](https://linear.app/glossed/issue/GLO-66) — every screen but the product page renders from fixtures |
| **No events fire anywhere** | [GLO-21](https://linear.app/glossed/issue/GLO-21) owns `core/Tracking` and is scheduled last; see the comment |
| The shade/size pick has no owner | [GLO-56](https://linear.app/glossed/issue/GLO-56) — now blocking three screens |
| Fit: multi-axis in the kit, one row in the schema | [GLO-67](https://linear.app/glossed/issue/GLO-67) — a real conflict, needs a decision |
| The kit has no icon set in the app | [GLO-64](https://linear.app/glossed/issue/GLO-64) — five SF Symbols stand in so far |
| `Caveat` cannot draw the kit's ✿ | [GLO-69](https://linear.app/glossed/issue/GLO-69) — verified in the font's `cmap` |
| Category labels are singular *and* plural | [GLO-51](https://linear.app/glossed/issue/GLO-51) — "#2 of 5 cream blush" reads as a typo |
| Mid-session shelf changes desync a ranking session | [GLO-53](https://linear.app/glossed/issue/GLO-53) |
| Hair-type reference photos are placeholders | [GLO-52](https://linear.app/glossed/issue/GLO-52) |
| Category tree + chip vocabulary exist only in dev seeds | [GLO-51](https://linear.app/glossed/issue/GLO-51) |
| No branch protection on `main` | Free now the repo is public — worth enabling |
| Numbers chosen, not validated | `docs/BACKLOG.md` — payoff n≥8, min-n 5, shrinkage k≈10 |
| Two-char search floor duplicated | [GLO-55](https://linear.app/glossed/issue/GLO-55) |
| Autocorrect fix lives at a call site | [GLO-57](https://linear.app/glossed/issue/GLO-57) |
| Orphaned cutouts accumulate | [GLO-54](https://linear.app/glossed/issue/GLO-54) |

### The kit is not always ahead of the app

Twice this session the frame was the thing that was wrong, not the port:

- **[GLO-68](https://linear.app/glossed/issue/GLO-68)** — the kit's own bay holds
  five and fills 56% of its 390px frame. Fixed in the app; **the kit still says
  five**, so the next person reading `G.Shelf` will re-introduce it.
- **[GLO-69](https://linear.app/glossed/issue/GLO-69)** — the kit's ✿ is not in
  the typeface the kit specifies for it.

`docs/DESIGN.md` says a divergence must be stated and justified. It should also
say: **when the frame is wrong, change the frame.** Otherwise the app and the kit
drift in the direction nobody chose.

## 8. Local setup

```bash
make setup         # tools, xcodegen, supabase start, db reset + seed
make dev           # regenerate + open Xcode
supabase test db   # 49 pgTAP assertions
```

Docker runs via **colima** (`colima start --cpu 2 --memory 4`). One gotcha seen
this session: a Docker image whose layer was corrupted by a full disk keeps
being reused after a re-pull — `docker system prune -a -f --volumes` is the fix,
not another `docker pull`.

## 9. Blocked on a human, not on code

Both need credentials no agent has. Everything else routes around them.

**R2 provisioning ([GLO-48](https://linear.app/glossed/issue/GLO-48)).** Buckets
`glossed-prod` / `glossed-dev`, an API token, CORS, and a spend alert. Until
they exist, `storage_presign` is merged but deliberately **not deployed** — a
deployed function without secrets is just an endpoint that 500s. The env var
names are already in `.env.example` and are read only inside the Edge Function,
never in the app bundle. Deploy with `supabase functions deploy storage_presign`
once the secrets are set.

**App Store Connect ([GLO-50](https://linear.app/glossed/issue/GLO-50)).** The
Sign in with Apple capability on the App ID gates
[GLO-23](https://linear.app/glossed/issue/GLO-23) (auth), which gates
[GLO-18](https://linear.app/glossed/issue/GLO-18) (onboarding).

## 10. Two agents at once works, with one rule

Two sessions ran concurrently on Aug 28 without collision. What made it work:
**claim tickets explicitly before starting, by message, and say what you are
holding on disk but have not pushed.** Use `ListAgents` to find peers and
`SendMessage` to claim. The near-miss was both sessions eyeing GLO-15 at the
same minute; one message settled it.

Worth repeating: a session that is winding down should say so and name what it
is leaving free, and one agent should not merge another's PR when that PR
touches a file class its own instructions put off-limits — merging is not
modifying, but the conservative read costs nothing.

One git habit that cost the earlier session real work twice: `git push -q` hides
a failed push, and a docs commit whose content never reached the remote merged
as an empty pointer. **Check `git show --stat HEAD` before pushing**, and check
the PR's file list after.

## 11. What is actually blocked, and on whom

Worth reading before picking anything up — three of the remaining GLO-15 pieces
are blocked on something other than effort.

| Blocked thing | On what | Who can unblock |
|---|---|---|
| `storage_presign` deploy · catalog images | R2 buckets, token, CORS, spend alert ([GLO-48](https://linear.app/glossed/issue/GLO-48)) | the Cloudflare account holder |
| GLO-15 create rung | **two** gaps in the frozen core ([GLO-60](https://linear.app/glossed/issue/GLO-60)) — see below | a human, or an agent explicitly authorized to open frozen DataKit |
| GLO-15 near-match rung's *point* | catalog images — "check the photo, not the name" is a weak instruction when the photo is a tile | same R2 chore |
| Auth, onboarding | Sign in with Apple on the App ID ([GLO-50](https://linear.app/glossed/issue/GLO-50)) | the Apple Developer account holder |

The create rung's blocker is worth knowing precisely, because it is not
obvious from the outside and it is not a missing convenience.
`createPersonalProduct` inserts a row in `products`. `ShelfRepository.log` needs
a `variantID`, and `user_items.variant_id` is `not null`. **Nothing creates the
variant** — no DataKit call, no trigger; `variants.kind` merely defaults to
`'default'` for a row nobody inserts. So the last rung of the ladder would
produce a product that cannot be logged, which is the one thing the ladder
exists to do — and it would fail *quietly*: the create succeeds, the
personal-scope badge appears, and the shelf write fails a step later on a
product that now exists and is invisible. The fix is probably a
security-definer RPC inserting both atomically, which makes it a migration
ticket as well as a DataKit one.

The near-match rung is **buildable now** and degrades honestly:
`TypographicTile` is the floor of ADR 0004's fallback chain and landed in
[#48](https://github.com/seanbrasse/glossed/pull/48) precisely so it is not the
thing holding that rung up when someone gets to it.

Also open, and higher priority than its label suggests:
[GLO-59](https://linear.app/glossed/issue/GLO-59) — the recap agent has twice
posted a test stub instead of a recap while the check went green. The recap is
the review step this project leans on, so a silent miss means a PR merges with
no review while the check mark says otherwise. Fixing it means editing a
workflow, which agents may not do.

## 12. What the last two sessions got wrong, so you don't repeat it

**Session one — three failures, all one shape: acting on an assumption instead
of checking, and not saying out loud that it was an assumption.**

*The design.* The kit was linked from the day it was created. A 403 from
`WebFetch` was taken as "unreachable" and the whole submission ladder was built
from the primitives. → [GLO-62](https://linear.app/glossed/issue/GLO-62), §0.

*The handoff.* A `git push -q` failed silently and a docs PR merged empty.
**Check `git show --stat HEAD` before pushing, and the PR's file list after.**

*The blockers.* GLO-15's create rung was planned three times before anyone
checked whether the core could supply a `brandID` (it cannot) or whether a
created product could reach the shelf (it cannot). Both were findable in a
two-minute read. → [GLO-60](https://linear.app/glossed/issue/GLO-60).

**Session two — the same shape, twice, in smaller places.**

*A fix for a bug that was not there.* I measured a ~5pt drift off a screenshot,
concluded negative padding was widening the shelf, and rewrote it. The render
was pixel-identical: the measurement was eyeball noise. Reverted, with the
reasoning left in the source. **Measure with a test or with arithmetic, not with
your eye on a scaled screenshot.**

*A number used in two places, twice.* Packing the shelf reserved a 30pt slot and
then drew the object at 24. Nine items fitted, the shelf was still short, and the
rank stickers were back within touching distance — both of the things the slot
existed to prevent. It passed every test.

**What went right, and is worth copying:** reading the frame *against the schema
and the frozen core* before writing anything. Three of the seven tickets this
session opened came out of that step — GLO-63, GLO-66, GLO-67 — and each would
otherwise have surfaced halfway through an implementation that had to be undone.

The counterweight worth keeping: when a review flags something, **check it
rather than agree with it.** That is what found the actual defect twice.
