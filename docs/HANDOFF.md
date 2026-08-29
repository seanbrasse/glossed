# Session handoff — Aug 29 2026 (session 11: the Phase-1 journal lane, and the state sweep that outperformed the test suite)

Where Phase 1 stands, what to do next, and what this session learned. Read
`docs/README.md` first for the design; this file is only about state.

**Two lanes ran concurrently all session and both merged into main.** This
file is written by the **Phase-1 journal lane** (shelf, sheet, product page,
ladder, the state sweep). The **Phase-1.5 lane** landed migrations 0033–0040,
five DataKit repositories, `docs/tech/07`, and — while this very file sat in
review — the privacy screen ([#259](https://github.com/seanbrasse/glossed/pull/259))
and the discover opening ([#261](https://github.com/seanbrasse/glossed/pull/261)).
Their [#263](https://github.com/seanbrasse/glossed/pull/263) is still open and is
**not this lane's to merge or speak for**. Where a number below belongs to them it
says so.

## 0. Read this first

**The local database is ELEVEN migrations behind the repo, and nothing warns
you.** Verified just now: `supabase_migrations.schema_migrations` holds **29**
rows while `supabase/migrations/` holds **40 files**. `affinity_for_user`
(0035) exists; `refresh_agg_variant_stats` (0036), `refresh_agg_rank_scores`
(0038) and `discover_feed` (0040) **do not**. The 1.5 lane has been applying
DDL to *hosted* as it lands, and the local stack drifted behind.

The consequence is precisely §5's trap wearing a new coat: **`supabase test db`
will red, and every red will be drift rather than defect.** Do not conclude
anything from a local pgTAP run, and do not "fix" a function that is simply
not applied here, until you have run `supabase db reset` (ping the other
session first — §4) and re-seeded (§9, ~50 min). This session did **not** run
pgTAP for exactly this reason, so **there is no current local assertion count
in this file.** Getting one is a reset, not a query.

**"Verify before you file" has a second half that cost more than the first: a
red you dismiss is a defect you own.** This stretch talked itself out of five
false defects (a stale `.build` cache, an unreachable scrim that was really a
status-bar tap, a "regression" that was a peer's migration, a page mock that
was a missing field, and an import "add 4" affordance that turned out to be
unbuilt-by-design) — and in the same stretch the 1.5 lane discovered that
`shelf_isolation` test 4, which **three sessions had agreed to treat as
drive-drift**, had been correctly reporting GLO-145's view leak the whole
time. It was the only thing in the repo detecting it.

So the rule runs both ways. Check before you file, **and** check before you
dismiss. "Known failure" is a claim that needs the same evidence as "new bug",
and a shared assumption is the easiest place for one to hide.

**Analytics fail SILENTLY, and the drop notices are now visible but only in
the log stream.** Nothing serves functions locally by default — the
edge-runtime container has never served them, and `supabase status` lists it
under *Stopped services*. `track_ingest` was probed this session and returned
**503**, so the Tracker is discarding every batch **by design** (tech/06 §2).
GLO-147 made each drop leave an `os.Logger` line on subsystem
`com.glossed.tracking` — but `print` reaches nobody, because our launch recipe
does not pass `--console`. **Before you conclude anything about events, curl
track_ingest, confirm 200, and read the log stream** (both commands in §9).

**After retargeting a stacked PR to main, CI's scope job can silently reuse a
stale decision and skip (or outright fail) the iOS job** — GLO-71's bug, hit
seven times to date; the preemptive routine has prevented a recurrence since.
A skipped check is not a passed check. The routine: rebase onto the base's
exact tip, retarget, **then** `git commit --amend --no-edit` for a fresh SHA
and push — the amend must come AFTER the retarget or the stale scope decision
survives. Confirm the iOS job actually queued before walking away. **A
docs-only PR skipping iOS is correct, not the bug** — the discriminator is
whether the PR touches `.swift` files, so check the file list, not the badge.

**A FULL DISK takes your shell away entirely, and it is what wedges Docker.**
This happened on Aug 29: the volume hit zero free bytes, and the Bash tool
stopped running *any* command — it must create an output file before it runs,
so even `rm -rf .build` returned `ENOSPC` instead of freeing the space. There
is no working around it from inside the session; a human has to clear the
volume. The same event left the Docker daemon split-brain (the db container
`healthy` per `ps`, `not running` per `exec`) and cost the other lane a
restart. **Check `df -h /` before a long build, and treat SwiftPM `.build`
directories across worktrees as the first thing to delete** — they are
regenerable and they are what fills it.

**Docker/colima can wedge under heavy image i/o, and the daemon then holds
CONTRADICTORY state** — `docker ps` said healthy while `inspect` said exited,
with i/o errors on the container's own metadata files. Trust neither, check
both; `colima restart` is the remedy when metadata i/o fails (volumes
survived; rule out disk-full first — it was 11%). After ANY killed queue
consumer: jobs it claimed stay orphaned as `running` — requeue them, and
crash-window `failed` rows with attempts=1 are infra casualties identifiable
by timestamp, also requeue. **Confirmed live on Aug 29** — the disk-full event
above reproduced the split-brain exactly as described, which is the first time
this note has caught its own case rather than described a past one.

**Never `--delete-branch` in merge automation** (killed #159 through a reused
watcher script). Delete branches only after a stack fully lands, by hand.

**Authorizations are per-session and all expired with this one.** This session
held **self-merge on green** (used on every PR below) and **one migration
authorization, granted by Sean on Aug 29 for GLO-150's `0033`**. It needed
**no DataKit opening** — everything it built routed around the frozen core.
Re-ask for anything you need; rulings on tickets stand.

## 1. Where to start

Tracked in **Linear**: workspace [glossed](https://linear.app/glossed), team
**GLO**, project **GLOSSED — Phase 1: The Journal**.

| Next | Why |
|---|---|
| [GLO-110](https://linear.app/glossed/issue/GLO-110) — finish the state sweep | **In progress and the highest-yield thing in the repo right now.** 26 cells driven; its own "what the sweep found" section names six findings — five merged fixes ([#236](https://github.com/seanbrasse/glossed/pull/236), [#237](https://github.com/seanbrasse/glossed/pull/237), [#238](https://github.com/seanbrasse/glossed/pull/238), [#242](https://github.com/seanbrasse/glossed/pull/242), [#260](https://github.com/seanbrasse/glossed/pull/260)) and one open ticket (GLO-172). The grid and what remains live in [docs/ux-state-sweep.md](docs/ux-state-sweep.md). Remaining: the ladder's search and near-match rungs, `product · thin`, `import · pick a source`, and `shelf · remove failed` (unit-tested; needs the local stack down, so pair it with the §0 reset) |
| [GLO-172](https://linear.app/glossed/issue/GLO-172) — accessibility text sizes | **High, and it needs a design call, not more code.** At accessibility-extra-large the shelf's control row overflows and clips the products. The obvious fix (wrap `controls` in a ScrollView) works completely *and* clips the view toggle at the DEFAULT size — because `sortPills`/`viewToggle` carry `.fixedSize()` and the row had been silently compressing to fit. `ViewThatFits` does not help; it picks by ideal size. Three candidate fixes are written on the ticket; **pick one with Sean** rather than re-deriving them |
| [GLO-156](https://linear.app/glossed/issue/GLO-156) — chip order | **Needs Sean, not code.** The per-category vocabulary means likes and dislikes now interleave alphabetically in the sheet. Grouping by valence is one line in `ShelfChipsModel`; *which group leads, and whether they should be separated rather than merely ordered*, is a feel question — the same class as the shelf label and the fit gate, both of which he ruled on directly. Render both against real chips and let him pick |
| [GLO-164](https://linear.app/glossed/issue/GLO-164) — the duplicated Fit ↔ FitAnswer mapping | Low, small, and self-contained. `Shelf` and `ProductPage` each carry a private copy of the same two switches. It cannot move to a feature (features never import features), so it is a DesignSystem or DataKit call — which makes it **an opening question, not a refactor** |
| [GLO-152](https://linear.app/glossed/issue/GLO-152) — product links | Decided (build now, swap to affiliate links later) and **routes through the 1.5 lane's migration slot** for `product_links`. Part 1 is script-only: `shopify_import.ts` never captured the `handle` that `/products.json` returns, so 2,202 URLs were thrown away. Verified against a live payload |
| [GLO-148](https://linear.app/glossed/issue/GLO-148) — `core/Media` | Both CLAUDE.md files document a package that **has never existed**. One-line doc fix, and it stops the next agent's sweep loop reporting "NO TESTS" for a directory that is not there |
| Beauty API key + Vercel project | Unchanged, still keyboard-minutes for Sean, still the long pole for GLO-90/91/93 |
| [GLO-85](https://linear.app/glossed/issue/GLO-85) queue consumer | Unchanged. **Do not start without Sean's direct word** |
| GLO-16's matched-barcode gap | A log from a matched barcode carries no category, so no fit prompt and no event. **Not drivable in the simulator** (no camera) — needs a device or a seam that fakes the scan |

**Done this stretch — 26 PRs merged into main between
[#234](https://github.com/seanbrasse/glossed/pull/234) and
[#262](https://github.com/seanbrasse/glossed/pull/262), across both lanes.**

This lane (Phase 1, journal): fit persists on the product page and stops being
offered where it cannot be answered ([#235](https://github.com/seanbrasse/glossed/pull/235),
[#236](https://github.com/seanbrasse/glossed/pull/236),
[#260](https://github.com/seanbrasse/glossed/pull/260) — GLO-47/165); a blank
shelf says *why* it is blank, four causes ([#237](https://github.com/seanbrasse/glossed/pull/237)
— GLO-166); the events partitions are born locked
([#239](https://github.com/seanbrasse/glossed/pull/239) — GLO-150, the one
authorized migration); the 40-shade sheet gets a fixture and its cap gets a
guard ([#242](https://github.com/seanbrasse/glossed/pull/242) — GLO-168); and
the state sweep in four rounds ([#254](https://github.com/seanbrasse/glossed/pull/254),
[#256](https://github.com/seanbrasse/glossed/pull/256),
[#257](https://github.com/seanbrasse/glossed/pull/257),
[#262](https://github.com/seanbrasse/glossed/pull/262) — GLO-110).

Earlier in the same stretch, also this lane: the sheet asks whether you would
buy it again (GLO-87), the item sheet is held to the screen (GLO-160), the
shelf's label band and scale-down (GLO-149/155), the live chip + note store
(GLO-16), the dead "full page" button becomes a real one (GLO-151), and
analytics drops became visible (GLO-147).

The 1.5 lane, for context only: migrations 0033–0040 (taste engine, four
aggregate writers, the discover read path), five DataKit repositories
(Privacy, Social, Safety, Browse), `inci_enrich`, and `docs/tech/07`.

## 2. What exists

| Layer | State |
|---|---|
| Schema | **40 migration files; 29 applied to the local DB (§0).** 0033–0040 landed this stretch, all but 0033 by the 1.5 lane. The slot is theirs — route DDL through them, do not open a second migration PR. **Hosted was not checked by this session**; the 1.5 lane applies there and is the authority on it |
| Catalog data | **3,206 products / 9,019 variants / 7,625 images / 497 brands / 22 categories**, local-only; **2,112 pending merge_candidates**, image queue ZERO. (Counted just now against the local DB.) Every image meets the standard (OBF's 588 sub-800px purged, GLO-104). Search knows what things ARE: product_type/tags/origin live on 1,836+ rows. Restore recipe: §9 — now SEVEN scripts. Maya's shelf carries drive-drift rows — fine for dev; a pgTAP run wants a reset + ping |
| `core/DataKit` | **Frozen. This lane needed no opening at all.** **83 tests** — up from 44 because the 1.5 lane spent its own openings on five repositories plus the discover models |
| `core/DesignSystem` | + `YesNoControl` (a question you can leave unanswered — `Segmented` always has one option selected, which is right for a status and wrong for a question), scaling `ProductSticker`. 42 tests |
| `core/Tracking` | track() real, and **a dropped batch now says so** — `os.Logger` on `com.glossed.tracking` in DEBUG, plus `droppedCount` (GLO-147). 15 tests |
| `features/Shelf` | + fit gated on tried (GLO-145), live chip + note store (GLO-16), "would you buy it again?" (GLO-87), a bounded scrolling sheet (GLO-160), the label band and scale-down (GLO-149/155), four named empty states (GLO-166). 133 tests |
| `features/ProductPage` | + the catalog image (GLO-153), and the fit answer now persists and is offered only where a `userItemID` exists to persist it to (GLO-47/165). 20 tests |
| `features/AddLadder` | + GLO-93's scan-miss fill (`BarcodeFilling`/`BarcodeFillSuggestion` live HERE, not in DataKit), the 40-shade fixture and its cap guard (GLO-168). 108 tests |
| `features/Privacy` | **New, and the ninth package** — landed by the 1.5 lane in #259 after this handoff was first written. Four surfaces, one derived summary. 11 tests |
| `features/Ranking` / `features/Import` | Untouched this stretch. 29 / 12 tests |
| `app/` | Tracker wiring, fit-at-log seam + FitPromptCard (the prompt lives HERE, not in Shelf), catalogImageBase, and `AppShellProductPage` — closing the page re-opens the sheet so it re-reads `item_fits` |
| `web/landing/` | Static landing page for the affiliate applications. On main, NOT deployed (§7) |
| `scripts/` | shopify_import, obf_import (+ `--brands`), shopify_images, catalog_images, obf_requalify, brand_merge, merge_feeder, **inci_enrich** (new, GLO-170) |
| `supabase/functions` | **7 functions, 82 deno tests, all passing, none deployed**; nothing serves them by default and the silence is dangerous (§0) |

**Verified totals, session 11 (every command actually run): 453 Swift tests
across 9 packages** — DataKit 83, DesignSystem 42, Tracking 15, Shelf 133,
AddLadder 108, Ranking 29, ProductPage 20, Import 12, **Privacy 11** — **plus
82 deno.** The first eight were counted on `69cd9e6`; DataKit and Privacy were
re-counted after #259 and #261 landed mid-review. **Nine, not eight** — if you
copy the sweep loop from §9, copy the current one. **pgTAP was NOT run and this file quotes no number for it**
(§0: the local DB is 11 migrations behind, so any result would be drift).
`core/Media` is NOT among the packages: it is named in both CLAUDE.md files but
**has never existed** ([GLO-148](https://linear.app/glossed/issue/GLO-148)).

The sentence that is true about all of it: **the app is live against the local
stack only, and the local stack is now behind the repo.** Hosted has the
schema and no data, no functions, no storage; the catalog's future sources
(feeds, Beauty API) are account-gated on Sean, not code-gated.

## 3. How this session worked

Unchanged: branches `feat/GLO-<n>-desc` (also `fix/`, `docs/`, `test/`), ≤5
files/400 lines (`size-override` + reason when the shape demands it), squash
merges, one migration PR at a time, drive-then-psql on everything, two lanes
coordinating by direct message with file-level ownership announced before
touching.

**The loop that worked, and produced six merged fixes in one stretch:**

1. **Pick a state, not a feature.** Open `docs/ux-state-sweep.md`, take an
   undriven cell. A state is small enough to finish and specific enough that
   "does it hold?" has a yes/no answer.
2. **Write down the promise before you look.** The cell's rule ("a failed
   parse must not list five misses") is decided from `docs/domain.md` and the
   copy, *before* driving — otherwise you rationalise whatever renders.
3. **Drive it.** `GLOSSED_SCREENS=1`, the debug picker, the canon simulator.
   Screenshot at 2.284× and convert to the 402×874 point frame before tapping.
4. **If it holds, record it as checked-and-clean with the promise quoted.** A
   clean cell is a finding: three of them turned out to be the same doctrine
   implemented independently, which no single code review could have shown.
5. **If it does not hold, file first and read back the id Linear assigned**
   (§8 — this bit twice), then build on `feat/GLO-<n>-desc`.
6. **Full sweep before the PR** — `swift test` in *every* package, not just
   the one you touched (§9).
7. **Open the PR with the visual plan filled in, watch CI, merge on green**
   — and check the *file list*, not the badge: iOS skipping on a docs-only PR
   is correct; iOS skipping on a Swift PR is GLO-71 (§0).

Carried forward and still true: **claim work in writing BEFORE building** —
lane crossings have been bloodless only because the claim-then-check protocol
ran first; **peer sockets go stale**, so use `ListAgents` for a live address
rather than one from your own transcript; **a relayed assignment is not an
assignment**; and **research-then-ticket for external services**, with
license language quoted verbatim on the ticket because posture is a
commitment, not a vibe.

## 4. Frozen or dangerous areas

Unchanged: `core/DataKit` (openings are per-session and must be asked for),
`supabase/migrations/` (lock + apply-to-hosted; **the slot is the 1.5 lane's**
and a second open migration PR is the failure mode the rule exists to
prevent), CI workflows, `ingest_jobs` claiming (the state-filtered UPDATE
**is** the lock), the image-host allowlist (barcode_fill's
images.thebeautyapi.com is deliberately NOT a rung — their license says
display-direct, don't re-host).

Standing: **brand merges are curated, never inferred** (`brand_merge.ts` — the
wrong-franchise trap is what an automatic matcher falls into), and **the OBF
image gate** (800px source floor) is a standard, not a bug — deleting it
re-admits phone photos.

Standing, and now sharper: `supabase test db` runs against the **live local
DB**, which is currently 11 migrations behind (§0). Reset before trusting a
local red, **ping the other session before resetting**, and budget the restore
(§9, seven scripts, ~50 min).

New: **the events partitions.** Migration 0033 fixed a real leak — `anon`
could SELECT every partition, demonstrated with `set role anon`, not inferred.
The parent was correctly locked, which is exactly what made it invisible:
partitions inherit neither RLS nor ACLs, and Supabase's default privileges
hand every new table to `anon`. `drop_expired_event_partitions()` now creates
them locked. **If you ever add a partitioned table, the parent's policy is not
the child's policy** — a missing check here stops being a bug and becomes a
data leak of `user_id` plus event names plus full props.

## 5. How work gets reviewed

Driving the build still catches what nothing else does. The full-sweep test
pass, verbatim:

1. `swift test` in **every** package (not just the one you touched),
2. `make functions-test`, then `supabase test db` **only against a fresh DB**,
3. build + install + drive the core loops on the canon simulator,
4. `psql` after every driven write,
5. **verify before filing — and before dismissing** (§0).

What it actually costs and where it fails: about an hour for a full pass. Its
failure modes are all silent — a drive proves nothing about events unless
functions are served (§0); a pgTAP red proves nothing unless the DB is at the
repo's migration head (§0); and a `.build` cache from before a core change
will report a package as broken when CI says it is fine (§8).

**The state sweep (GLO-110) is the newer instrument and is outperforming the
test pass per hour.** Its own findings section names six, of which five are
merged fixes. Every one was invisible to the automated suite, because they are
defects of *what is offered*, not of what is computed: a fit control that
could not save and did not say so, a blank shelf that would not say which of
four causes it was, a 40-shade case reachable only by finding a real 40-shade
product, and a fixture that silently lost a block to my own regex. Driving
this stretch also produced GLO-151 (a nav button wired to an empty default)
and GLO-160 (a control pushed off the bottom of the screen while still
rendered and hit-testable) before the grid existed. **A test asserts what a
function returns; only a drive asks whether the thing on screen should be
there at all.**

For external APIs the drive equivalent is a mock upstream + the audit count —
`barcode_fill`'s budget gate was proven by the mock's log staying empty.

## 6. Open threads

| Thread | Where |
|---|---|
| The state sweep is 26 cells in and unfinished; five named cells remain | [GLO-110](https://linear.app/glossed/issue/GLO-110) / [docs/ux-state-sweep.md](docs/ux-state-sweep.md) |
| The shelf is unusable at accessibility text sizes; three candidate fixes written, none picked | [GLO-172](https://linear.app/glossed/issue/GLO-172) |
| Chips render alphabetically, so likes and dislikes interleave — a feel question for Sean | [GLO-156](https://linear.app/glossed/issue/GLO-156) |
| The Fit ↔ FitAnswer mapping is duplicated in two features with no legal shared home | [GLO-164](https://linear.app/glossed/issue/GLO-164) |
| The local DB is 11 migrations behind the repo; no pgTAP number is trustworthy until it is reset | §0 |
| Beauty API sandbox key → function secret. Client wiring is DONE (#194); the key is all that stands between the wired path and a live drive | [GLO-93](https://linear.app/glossed/issue/GLO-93) / §7 |
| Vercel deploy of `web/landing/` → the channel URL → GLO-90/91 applications | [GLO-89](https://linear.app/glossed/issue/GLO-89) / §7 |
| GLO-85 queue consumer, sized for FEED-arrival (the inverted canary: 5 cross-source pairs total — OBF-drugstore and Shopify-DTC barely intersect) | [GLO-85](https://linear.app/glossed/issue/GLO-85) → GLO-14 |
| Workshop accumulation: FitPromptCard, sheet 6-row/5.5, GLO-87 icons, bay-upright overlap, GLO-100's two questions, concealer-anchor, new wear-ins, essence→toner | §1 |
| Fit-at-log's matched-barcode door: no prompt, no event (no category on a bare variant lookup), and not drivable without a camera | [GLO-16](https://linear.app/glossed/issue/GLO-16) |
| `core/Media` is documented in both CLAUDE.md files but has never existed | [GLO-148](https://linear.app/glossed/issue/GLO-148) |
| Hosted Supabase has the schema and zero reference rows — no category tree, no chip vocabulary | [GLO-158](https://linear.app/glossed/issue/GLO-158) |
| Typeless storefronts (missha, murad, tatcha, supergoop at ~0 despite the tree) — feeds/Beauty-API bucket, not tree-gated | GLO-99 finding |
| OBF foreign names (category crawl only — brand mode sidesteps); krave maps 0 | [GLO-84](https://linear.app/glossed/issue/GLO-84) / [GLO-79](https://linear.app/glossed/issue/GLO-79) |
| `glossed.app` domain is TAKEN — tech/02's share-URL plan needs a new domain (glossed.beauty was $1.99 at check) | GLO-89 finding |

## 7. Blocked on a human, not on code

| Blocked thing | On what | Who |
|---|---|---|
| [GLO-172](https://linear.app/glossed/issue/GLO-172)'s fix | **A design decision, not a slot.** Three candidate fixes are on the ticket; the correct one changes how the shelf's control row behaves at default size, which is Sean's call | Sean |
| [GLO-156](https://linear.app/glossed/issue/GLO-156) chip order | Same class — render both and let him pick | Sean |
| Landing-page deploy (→ Rakuten/Impact applications) | Vercel MCP token cannot create projects (403, team role). Create an empty project named `glossed` OR raise the integration's role; the deploy payload is one command away | Sean |
| Rakuten + Impact publisher accounts | Signups (GLO-90/91 carry the exact steps); need the channel URL above | Sean |
| Beauty API key | Free Sandbox+Barcode signup at thebeautyapi.com → `BEAUTY_API_KEY` secret | Sean |
| Any DataKit opening | Per-session authorization. This lane needed none and asked for none | Sean |
| Any migration slot | Per-migration. Sean authorized `0033` for GLO-150 on Aug 29 after it was flagged as not-purely-additive; that authorization is spent | Sean |
| GLO-85 queue consumer | Needs `ANTHROPIC_API_KEY` **and** Sean's direct word — a relayed hand-off of this lane was retracted once already | Sean |
| R2, function secrets, Apple/Twilio, GLO-71's real fix | Unchanged from #163 | Sean / any human |

## 8. What went wrong, so you don't repeat it

Sessions 1–5 (preserved): built to primitives with frames reachable;
`git push -q` hid a failure; planned against a core that couldn't supply;
fixed an absent bug; one number in two places; stacked-squash double-apply;
scope-job silent skip; green test testing its own decoder; unsigninable
seeded users; background branch switches; secrets in history; stale
simulator binaries; `--delete-branch` auto-closing stack children; piped
exit codes; view-local @State lying; wrong detector task; allowlist that
didn't grow; wrong-branch pipeline runs; wrong-franchise title matching;
record in-flight CI state.

Session 6 (preserved): the pipe ate the exit code AGAIN, twice; an amend
landed on the wrong branch; a dirty tree silently skipped a rebase in a
`&&` chain, three times; `swift test` builds for macOS; picker fixtures
don't host transitions; `supabase test db` is not hermetic;
`--delete-branch` recurred through a reused watcher script (#159); a
watcher's unconditional `echo MERGED` lied; an `ls` is not `git ls-tree`;
a blind plan-count replace no-op'd; the ping-before-reset pact broke the
day it was made; the restore is FOUR scripts; worktrees share refs.

**Session 7:** simulator screenshots are ~2.29× device points on the canon
16 Pro — a tap computed from screenshot pixels lands nowhere and fails
SILENTLY; convert to the 402×874 point frame first. The bundle id is
`com.glossed.app` — launching `co.glossed.app` from memory got
FBSOpenApplicationServiceErrorDomain 4; read project.yml, don't recall.
Bash cwd persists across tool calls — a lingering `cd features/AddLadder`
made `make lint` fail with a false red that pattern-matches a real one
(this bit BOTH sessions repeatedly; run make from repo root explicitly). A
state can LOOK interactive while being unfinishable — the 40-shade sheet's
confirm sat off-screen for hours as "polish"; drive the extreme fixture.
Two `functions serve` instances raced and the loser errored into
/dev/null — announce a serve like a simulator borrow and never /dev/null
its output; a mocked env answering another session's drive is the
Sean-saw-mocks trap wearing a new coat. ShelfModel hit the 300-line
ceiling twice — stored properties can't move to extensions, so extract
computed projections (ShelfShownState.swift), and plan extractions around
the stored props; `make format` auto-fixes ACL style errors — run it
before hand-editing. Base64 images do not fit through tool-call plumbing —
a 90KB payload persisted to a file whose single LINE exceeded the read
cap; compress to purpose (460px jpeg) before encoding, and check the token
math before building the payload. A third-party MCP's write permissions
are not your permissions — Vercel accepted every read and 403'd project
creation twice (two different endpoints) — probe the cheapest write early
instead of building the full payload first. And a generated `.xcodeproj`
belongs to the branch that generated it: a stale project file "couldn't
find" a file that was right there (regenerate with xcodegen after
switching branches, before trusting a build error).

**Session 8:** a dry-run that WRITES — brand_merge's first draft inserted
into merge_candidates before checking the dry-run flag; a dry run must be
read-only by construction, gate the writes, not the report. A ticket
referenced in a PR is not a ticket that exists — GLO-106 rode a merged PR
before anyone had filed it (caught when the status update bounced); file
first, reference second. `psql ... returning` row-counting through string
splits picked up a stray line and reported "1 queued" when the truth was
0 — filter to the exact row value, and when a log claims a write, verify
the table. OBF's crowd category tags are junk for popular brands
("en:Cafffeine", empty — The Ordinary went 14→0 on tags alone); their
NAMES are clean, so map from names with tight rules and never a generic
cream/lotion catch. Stored image dims are not source quality — the
pipeline caps at 512 and cutouts crop tight, so measure the SOURCE (sips)
when quality is the question. Job states are `queued`, not `pending` — a
wrong state name in a count query silently returns 0 and reads as "all
done". `===` in a zsh line is a glob, not a separator. The colima wedge +
contradictory-daemon-state checklist graduated to §0. Probe a third-party
MCP's cheapest WRITE before building payloads (Vercel: reads fine, two
create endpoints 403). The word-boundary regex scar bit TWICE in one
night ('lippie', 'Lips') — when an unmapped tally shows a big family,
suspect the boundary before the store. One products.json page answers a
store's convention — probe BEFORE the host joins the map, and test clever
inferences against a live payload (naturium: the general (brand,type)
collapse would have eaten nine distinct serums). And claim work in
writing BEFORE building — two lane-crossings tonight, both bloodless only
because the claim ran first.

**Session 9:** *Three false defects in one hour, all killed by checking
first — this is the section's whole thesis.* (a) Two packages "failed to
compile" on main; the cause was **stale `.build` caches** holding a
DataKit module from before #192 added `Chips.swift` — `rm -rf .build`
and both pass, CI agreed all along. Clean before believing a package is
broken. (b) Two pgTAP reds were drive-drift (§4), identified by checking
row timestamps and `is_seeded`, not by re-running. (c) Shelf status
changes emitted no events — **nothing was serving functions**, so the
Tracker was correctly discarding batches; the fix was a serve, not a
patch. In all three the wrong move was cheap and available. *A silent
`cd` in a sweep loop turns "missing" into "empty":* `for p in …; do (cd
$p 2>/dev/null && swift test); done` reported "core/Media: NO TESTS"
for a package that **does not exist** (GLO-148) — if a loop can silently
skip, make it print what it skipped. *Screenshot pixels ≠ points, again*
— the 918-wide capture is 2.284× the 402pt frame; every tap this session
was computed by dividing, and the one time it was not, the tap landed on
the wrong row. *A peer socket goes stale when its session ends* — reusing
an address from your own transcript gets ENOENT; `ListAgents` first.
*A relayed assignment is not an assignment* — "Sean handed you the
catalog lane" was retracted an hour later; the work already done got
disclosed to Sean rather than buried, and the bigger item (the LLM
adjudicator) had correctly not been started.


**Sessions 10–11 (this stretch):** *The same ticket number, invented twice.*
I wrote `GLO-154` into code and a branch name **before filing it**, and the
number was independently claimed by the 1.5 lane; the real ticket came back
as GLO-155 and every reference had to be corrected. Then it recurred an hour
later — I wrote `GLO-162`, Linear assigned **GLO-164**, and it was caught only
by a force-push before anyone read it. The shape: **file first, read back the
id Linear actually assigned, then write it into code.** Never derive the next
number by incrementing the last one you saw; two lanes are filing into the
same counter. *A mechanical edit reported a count and I read it as the right
count.* GLO-165's regex "rewrote 3 call sites" — but it matched only sites
carrying `evidence:`, so the `failure: .offline` fixture silently lost its fit
block, and I shipped the regression my own fix introduced (repaired in #260).
**When a bulk edit reports what it changed, enumerate what it did NOT match**;
the count of hits tells you nothing about the misses. *I built a fix for a
scrim that was never broken.* Taps at y=25 and y=40 did not dismiss the sheet,
so I wrote a fix; y=55 works, because **the top ~50pt of the simulator screen
is the status bar and the system takes the tap**. Move the tap before you
believe a hit-testing bug. Discarded the fix, filed nothing. *A fix can be
completely correct and still be wrong.* GLO-172's obvious repair — wrap
`controls` in a ScrollView — fixed the accessibility overflow entirely and
clipped the view toggle at the **default** size, because `sortPills` and
`viewToggle` carry `.fixedSize()` and the row had been silently *compressing*
to fit all along. `ViewThatFits` does not rescue it; it picks by ideal size.
**A container that currently fits may be fitting by compression — check the
default size before you change its axis.** Reverted, three candidates written
on the ticket. *A PR body is a claim and needs the same verification as code.*
#235's body said a nil `userItemID` left the fit control "read-only"; it only
stopped it persisting — the control still moved under the user's finger, which
is the no-fake-writes rule broken in the exact place the body claimed it was
honoured. Caught before merge, body corrected, GLO-165 filed. *Three attempts
to bound the item sheet, all reverted* (GLO-160): chrome-on-the-ScrollView
makes a short sheet full-height; `.fixedSize(vertical:)` does **not** mean
"hug content up to a limit" — it makes the scroll view take its full content
height and defeats scrolling entirely; chrome-behind-content floats the card
mid-screen. What worked was measuring the content with a preference key and
clamping in one direction only. *`simctl ui <udid> content-size` is not a
flag; it is `content_size`* — the underscore is the difference between an
accessibility drive and an error. *The stale `.build` scar recurred* —
`features/AddLadder` reported `error: fatalError` on a clean tree; `rm -rf
.build` and its 108 tests passed. *And a rebase conflicted with my own
already-merged doc PR* — the cheap move is `git rebase --abort`, re-branch off
current main, and reapply; resolving a conflict against yourself is slower and
riskier than redoing a small edit. *And this handoff grew a stale row inside
fifteen minutes.* Between writing it and its PR going green, the 1.5 lane
landed two PRs, one of which added a **ninth Swift package** — so §2's table,
§9's sweep loop and the header's "their PRs are still open" were all wrong
before anyone read them. The loop in §9 would have skipped `features/Privacy`
in silence, which is the §8 scar from session 9 recurring against the very
document that records it. **A handoff written while other lanes are merging is
stale on arrival: re-check its counts at merge time, not just at write time**,
and give any enumerating loop an explicit "MISSING" branch so the next drift
announces itself.

## 9. Local setup

```bash
make setup && make dev
# the full sweep (§5) — run ALL of these, not just the package you touched:
for p in core/DataKit core/DesignSystem core/Tracking features/Shelf \
         features/AddLadder features/Ranking features/ProductPage \
         features/Import features/Privacy; do
  [ -d "$p" ] || { echo "MISSING: $p"; continue; }   # never skip silently (§8)
  (cd $p && swift test)   # 453 total; rm -rf .build first if a package "won't compile" (§8)
done
make functions-test       # 82 deno tests
# supabase test db        # DO NOT trust the result until you reset (§0): the local
#                         # DB is at migration 0029 and the repo is at 0040.
docker exec supabase_db_glossed psql -U postgres -tAc \
  "select count(*) from supabase_migrations.schema_migrations;"   # tells you how far behind
```

**`psql` is not on this machine's PATH.** Every psql line in this file goes
through `docker exec supabase_db_glossed psql -U postgres` — reaching for a
bare `psql` gets `command not found` and reads like a stack problem. The
variant tables are `variants` and `variant_images`, **not**
`product_variants`/`product_images`, and merge_candidates' column is `state`,
not `status`.

```bash
# before trusting ANY claim about events (§0):
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  http://127.0.0.1:54321/functions/v1/track_ingest \
  -H 'Content-Type: application/json' -d '{"events":[]}'
# 503 = nothing is serving (this is the default state — `supabase status` lists
# supabase_edge_runtime_glossed under "Stopped services"). Start a session-scoped
# `supabase functions serve`, announce it like a simulator borrow, never /dev/null
# its output. Then read the drop notices GLO-147 leaves — the ONLY way to see
# them, because `print` needs `simctl launch --console` and the recipe below does not:
xcrun simctl spawn 0E1EF64B-E2E3-4A51-B322-29BBEFCEEFE1 log show --last 5m \
  --style compact --debug --info \
  --predicate 'subsystem == "com.glossed.tracking"'
# a line per dropped batch, with the real reason: httpError(code: 503, ...).
# NO lines + rows in `events` = instrumentation works. NO lines + no rows =
# nothing was tracked, which is a code bug. That distinction is the whole point.
```

```bash
# catalog data — SEVEN scripts, in this order (~50 min):
deno run --allow-net --allow-run --allow-env scripts/shopify_import.ts
deno run --allow-net --allow-run --allow-env scripts/obf_import.ts
deno run --allow-net --allow-run --allow-env scripts/obf_import.ts --brands
deno run --allow-net --allow-run --allow-env scripts/shopify_images.ts
SUPABASE_SERVICE_ROLE_KEY=<legacy JWT from supabase status> \
  deno run --allow-net --allow-run --allow-env --allow-read --allow-write scripts/catalog_images.ts --limit 6000
deno run --allow-run --allow-env scripts/brand_merge.ts
deno run --allow-run --allow-env scripts/inci_enrich.ts   # GLO-170: inci_raw -> attributes
# the merge queue's adjudication surface:
deno run --allow-run --allow-env scripts/merge_feeder.ts --pending
# (obf_requalify.ts is a one-off, already applied — rerun only if OBF images
# somehow re-enter under the 800px floor)
```

**The simulator canon: iPhone 16 Pro (iOS 18.0), UDID
`0E1EF64B-E2E3-4A51-B322-29BBEFCEEFE1` — one booted device, always;** shut
down strays, borrow with a ping when two lanes run. Bundle id
`com.glossed.app` (read `project.yml`, don't recall it). **Screenshot pixels
are 2.284× device points** — the 918-wide capture maps to a 402×874 point
frame, and a tap computed from raw pixels lands nowhere and fails silently.
**The top ~50pt is the status bar and the system eats the tap** (§8). Launch:
`supabase start`, then `SIMCTL_CHILD_SUPABASE_PUBLISHABLE_KEY=<from supabase
status>` + `simctl terminate/install/launch`. Sign-in fails → reset (with the
ping). `GLOSSED_SCREENS=1` opens the debug screen picker — **this is how every
state in the sweep was driven**, and adding a fixture there is usually cheaper
than reproducing a state by hand. Dynamic Type:
`xcrun simctl ui <udid> content_size accessibility-extra-large` (underscore,
§8). The local storage API wants the **legacy JWT** service key, not
`sb_secret_…`.
