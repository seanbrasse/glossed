# Session handoff — Aug 29 2026 (session 9: the core opened and refroze, the scan path closed, Phase 1 got tested)

Where Phase 1 stands, what to do next, and what this session learned. Read
`docs/README.md` first for the design; this file is only about state.

## 0. Read this first

**After retargeting a stacked PR to main, CI's scope job can silently reuse a
stale decision and skip (or outright fail) the iOS job** — GLO-71's bug, hit
seven times to date; the routine run preemptively on every retarget since
(four more this stretch) has prevented a recurrence. A skipped check is not
a passed check. The routine: rebase onto the base's exact tip, retarget,
**then** `git commit --amend --no-edit` for a fresh SHA and push — the
amend must come AFTER the retarget or the stale scope decision survives.
Confirm the iOS job actually queued before walking away.

**Docker/colima can wedge under heavy image i/o, and the daemon then holds
CONTRADICTORY state** — `docker ps` said healthy while `inspect` said
exited, with i/o errors on the container's own metadata files. Trust
neither, check both; `colima restart` is the remedy when metadata i/o
fails (volumes survived; rule out disk-full first — it was 11%). After ANY
killed queue consumer: jobs it claimed stay orphaned as `running` —
requeue them, and crash-window `failed` rows with attempts=1 are infra
casualties identifiable by timestamp, also requeue. (Session 8's wedge
recovered with zero data loss on exactly this checklist.)

**Analytics fail SILENTLY and invisibly, and it is now a ticket
([GLO-147](https://linear.app/glossed/issue/GLO-147)).** Nothing serves
functions locally by default — the edge-runtime container has never
served them — so `track_ingest` 503s and the Tracker drops every batch
**by design** (tech/06 §2). Nothing surfaces that: no console error, no
UI trace, no row. A drive looks identical whether instrumentation works
or is stone dead. Session 9 nearly filed a false bug on exactly this.
**Before you conclude anything about events, `curl` track_ingest and
confirm 200.** Start a clean session-scoped serve when you need one,
announce it like a simulator borrow, never /dev/null its output.

**"Verify before you file" has a second half that cost more than the
first: a red you dismiss is a defect you own.** Session 10 talked itself
out of four false defects (a stale `.build` cache, an unreachable
scrim that was really a status-bar tap, a "regression" that was a
peer's migration, and a page mock that turned out to be a missing
field) — and in the same session the 1.5 lane discovered that
`shelf_isolation` test 4, which THREE sessions had agreed to treat as
drive-drift, had been correctly reporting GLO-145's view leak the whole
time. It was the only thing in the repo detecting it.

So the rule runs both ways. Check before you file, **and** check before
you dismiss. "Known failure" is a claim that needs the same evidence as
"new bug", and a shared assumption is the easiest place for one to hide.
Current baseline is the 1.5 lane's to state, not this file's — ask them.

**A control that cannot be reached is not shipped.** The item sheet had
no height bound and did not scroll; on `main` it ended *exactly* on the
bottom edge of a 16 Pro, so the next section added pushed
`remove from shelf` off the screen while leaving it rendered and
hit-testable (GLO-160, fixed in #228). Two things to know if you touch
that sheet: the card must be drawn behind the **content**, not behind
the scroll view — on the scroll view a short sheet becomes a full-height
panel — and `.fixedSize(vertical:)` does **not** mean "hug content up to
a limit"; it makes the scroll view take its full content height and
defeats scrolling entirely. Both cost an attempt each.

**Never `--delete-branch` in merge automation** (killed #159 through a
reused watcher script). Delete branches only after a stack fully lands, by
hand.

**Authorizations are per-session and all expired with session 10.** Session
10 held self-merge on green and used it eleven times; it needed **no DataKit
opening and no migration slot** — everything it built routed around both.
Re-ask for anything you need.

**Superseded — the old session-9 note, kept only for the shape of it:** The
session had: self-merge on green, and **the DataKit opening bundle was
GRANTED and is now SPENT** — #192 landed chips (4 calls), `likeState` /
`updateLikeState`, and `invokeEdgeFunctionForData`; the core is **frozen
again**. Re-ask everything; rulings on tickets stand.

## 1. Where to start

Tracked in **Linear**: workspace [glossed](https://linear.app/glossed), team
**GLO**, project **GLOSSED — Phase 1: The Journal**.

**The DataKit ask is SPENT — don't re-ask for it.** #192 delivered all
three members and the core refroze. What is left splits cleanly: one
real bug with a feature half anyone can take, and a pile that routes
through Sean.

| Next | Why |
|---|---|
| [GLO-156](https://linear.app/glossed/issue/GLO-156) — chip order | **Needs Sean, not code.** The per-category vocabulary (GLO-154) means likes and dislikes now interleave alphabetically in the sheet. Grouping by valence is one line in `ShelfChipsModel`; *which group leads, and whether they should be separated rather than merely ordered*, is a feel question — the same class as the shelf label and the fit gate, both of which he ruled on directly. Render both against real chips and let him pick |
| [GLO-152](https://linear.app/glossed/issue/GLO-152) — product links | Decided (build now, swap to affiliate links later) and **route through the 1.5 lane's migration slot** for `product_links`. Part 1 is script-only: `shopify_import.ts` never captured the `handle` that `/products.json` returns, so 2,202 URLs were thrown away. Verified against a live payload |
| [GLO-151](https://linear.app/glossed/issue/GLO-151)'s neighbours | The product page is reachable now and is the least-driven screen in the app. `rank it` on it is still a dismissal; the leaderboard button goes nowhere |
| Beauty API key + Vercel project | Unchanged, still keyboard-minutes for Sean, still the long pole for GLO-90/91/93 |
| [GLO-85](https://linear.app/glossed/issue/GLO-85) queue consumer | Unchanged. **Do not start without Sean's direct word** |
| GLO-16's matched-barcode gap | A log from a matched barcode carries no category, so no fit prompt and no event. **Not drivable in the simulator** (no camera), which is why session 10 left it — needs a device or a seam that fakes the scan |

**Done in session 9 — 3 PRs #191/#192/#194, main verified at `9688e0a`,
one PR open that is NOT ours ([#193](https://github.com/seanbrasse/glossed/pull/193), the Phase 1.5 spec).**
[#191](https://github.com/seanbrasse/glossed/pull/191) westman's hyphen
shades (GLO-113 — 167 flat rows → 24 lines, and the merge queue fell
3,264 → 2,112 because that one family was a third of it);
[#192](https://github.com/seanbrasse/glossed/pull/192) the DataKit
opening bundle; [#194](https://github.com/seanbrasse/glossed/pull/194)
GLO-93's client half (a scanned miss asks the fill, one budgeted call
inside the frame-dedupe, fails closed on every branch). Then a **full
Phase 1 test pass** — see §5 — which produced GLO-145/146/147/148.

## 2. What exists

| Layer | State |
|---|---|
| Schema | **32 migrations** (0020–0032 landed in session 10 by the Phase-1.5 lane: privacy core, public read layer, handles, swatches, reports, and **GLO-145's `user_shade_anchor` status filter**). Slot is held by the 1.5 session — route DDL through them, do not open a second migration PR. |
| Catalog data | **3,203 products / 9,019 variants / 7,625 images / 497 brands / 22 categories**, local-only; **2,112 pending merge_candidates**, image queue ZERO. (Products fell from 3,349 because GLO-113 collapsed westman's 167 rows into 24 real lines — a drop that is a *gain*.) Every image meets the standard (OBF's 588 sub-800px purged, GLO-104). Search knows what things ARE: product_type/tags/origin live on 1,836+ rows — "korean sunscreen", "lipgloss", "retinol" all answer. Restore recipe: §9 — now SIX scripts. Maya's shelf carries drive-drift rows — fine for dev; a pgTAP run wants a reset + ping. |
| `core/DataKit` | **Frozen, and session 10 needed no opening at all** — #192's members turned out to cover the live chip store, the repurchase signal and the product page. 44 tests. |
| `core/DesignSystem` | + `YesNoControl` (a question you can leave unanswered — `Segmented` always has one option selected, which is right for a status and wrong for a question), scaling `ProductSticker`. 42 tests. |
| `core/Tracking` | track() real, and **a dropped batch now says so** — `os.Logger` on `com.glossed.tracking` in DEBUG, plus `droppedCount` (GLO-147). 15 tests. |
| `features/Shelf` | + fit gated on tried (GLO-145), live chip + note store (GLO-16), "would you buy it again?" (GLO-87), a bounded scrolling sheet (GLO-160), the shelf's label band and scale-down (GLO-149/155). 126 tests. |
| `features/AddLadder` | + GLO-93's scan-miss fill (`BarcodeFilling`/`BarcodeFillSuggestion` live HERE, not in DataKit — the core carries opaque bytes so the next function isn't another opening). 104 tests. |
| `app/` | Tracker wiring, fit-at-log seam + FitPromptCard (the prompt lives HERE, not in Shelf), catalogImageBase. |
| `web/landing/` | Static landing page for the affiliate applications. On main, NOT deployed (§7). |
| `scripts/` | shopify_import (fill + collapse + title-is-shade + promo strip), obf_import (category crawl + **--brands** drugstore mode), shopify_images, catalog_images (+ OBF 800px gate), obf_requalify, brand_merge (curated), merge_feeder. |
| `supabase/functions` | 6 functions, 56 deno tests, none deployed; nothing serves them by default and the silence is dangerous (§0, GLO-147). |

**Verified totals, session 10 (each command actually run): 386 Swift tests
across 8 packages** — DataKit 44, DesignSystem 42, Tracking 15, Shelf 126,
AddLadder 104, Ranking 29, ProductPage 14, Import 12 — **plus 82 deno.**
pgTAP is the 1.5 lane's number and moved all session; ask them rather than
quoting a stale one. `core/Media` is NOT among them: it is named in
both CLAUDE.md files but **has never existed** (GLO-148).

The sentence that is true about all of it: **the app is live against the
local stack only** — hosted has all 32 migrations and no data, no
functions, no storage; and the catalog's future sources (feeds, Beauty
API) are all account-gated on Sean, not code-gated.

## 3. How this session worked

Unchanged: branches `feat/GLO-<n>-desc`, ≤5 files/400 lines
(`size-override` + reason when the shape demands it), squash merges, one
migration PR at a time applied to hosted immediately, main rebuilt after
stacks, drive-then-psql on everything, two sessions coordinating by direct
messages with file-level ownership announced before touching.

New this stretch: **research-then-ticket for external services** — the
Rakuten/Impact/Beauty API arc was read from primary docs in-session (their
FAQ language is quoted verbatim on GLO-93 because license posture is a
commitment, not a vibe), turned into four tickets (GLO-90–93), and only
then built. The Beauty API's own docs reshaped the build twice: their
category granularity killed the auto-insert plan, and their image guidance
kept API images out of the cutout pipeline.

Session 8's additions: **Sean steered live all night** (ten-plus rulings —
tree, images, brand mode, filter chrome, nav, wishlist), and every ruling
became a ticketed build the same hour with the veto trail on the ticket.
**Claim work in writing BEFORE building** — his directives crossed the
two sessions' lanes twice (GLO-87/#157 earlier, GLO-97 tonight) and both
resolved bloodlessly only because the claim-then-check protocol ran
first. And **probe a store's convention before it joins the map** — one
page of products.json answers title-is-shade / "(Shade)"-suffix /
typeless, and testing a clever inference against a live payload (the
naturium counter-example) is the template.

Session 9's addition: **FOUR sessions ran at once, and peer sockets go
stale.** A session that ends leaves a dead socket path; messaging it
fails with ENOENT. Use `ListAgents` to get live addresses rather than
reusing one from earlier in your own transcript. The protocol that held:
announce the claim (files + tickets + whether you hold the slot or the
simulator) BEFORE building, and answer other sessions' claims
explicitly. It caught a duplicate GLO-97 run and a second handoff, both
before either wasted work. **A relayed assignment is not an assignment** —
session 9 was told (in good faith) that Sean had handed over the catalog
lane, and the relay was retracted an hour later; work started on it was
disclosed to Sean rather than quietly kept.

## 4. Frozen or dangerous areas

Unchanged: `core/DataKit` (openings per-session), `supabase/migrations/`
(lock + apply-to-hosted), CI workflows, `ingest_jobs` claiming (the
state-filtered UPDATE **is** the lock — two concurrent consumers ran fine),
the image-host allowlist (barcode_fill's images.thebeautyapi.com is
deliberately NOT a rung — their license says display-direct, don't
re-host).

New: **brand merges are curated, never inferred** (`brand_merge.ts` — the
wrong-franchise trap is what an automatic matcher falls into; new
spellings get added to its map by hand), and **the OBF image gate**
(800px source floor) is a standard, not a bug — deleting it re-admits
phone photos.

Standing: `supabase test db` runs against the **live local DB** — reset
before trusting a local red, ping the other session before resetting,
budget the restore (§9, now six scripts, ~50 min).

## 5. How work gets reviewed

Driving the build still catches what nothing else does, and session 9
added a **full-sweep test pass** worth repeating verbatim:

1. `swift test` in **every** package (not just the one you touched),
2. `make functions-test`, then `supabase test db`,
3. build + install + drive the core loops on the canon simulator,
4. `psql` after every driven write,
5. **verify before filing.** Three "defects" evaporated on inspection
   this session: two packages that "failed to compile" (stale `.build`
   caches — clean and they pass), two pgTAP reds (drive-drift, §4), and
   missing analytics events (nothing was serving functions, §0). One
   survived inspection and became GLO-145.

The pass found one high-severity bug the whole automated suite missed
(GLO-145: never-worn shade evidence), which is the argument for the
drive. It cost about an hour. Its failure mode is that a drive proves
nothing about events unless functions are actually served (§0).

For external APIs the drive equivalent is a mock upstream + the audit
count — `barcode_fill`'s budget gate was proven by the mock's log
staying empty.

## 6. Open threads

| Thread | Where |
|---|---|
| ~~The DataKit opening bundle~~ **SPENT** (#192). What it unblocked and nobody has built yet: chips LIVE-wiring in the sheet (GLO-16) and GLO-87 slice 2's would-repurchase UI | GLO-16 / GLO-87 |
| Beauty API sandbox key → function secret. Client wiring is DONE (#194); the key is all that stands between the wired path and a live drive | GLO-93 / §7 |
| Vercel deploy of `web/landing/` → the channel URL → GLO-90/91 applications | GLO-89 / §7 |
| GLO-85 queue consumer, sized for FEED-arrival (tonight's inverted canary: 5 cross-source pairs total — OBF-drugstore and Shopify-DTC barely intersect) | GLO-85 → GLO-14 |
| Workshop accumulation: FitPromptCard, sheet 6-row/5.5, GLO-87 icons, bay-upright overlap, GLO-100's two questions, concealer-anchor, new wear-ins, essence→toner | §1 |
| Fit-at-log's matched-barcode door: no prompt, no event (no category on a bare variant lookup) | GLO-16 ticket note |
| Fit is offered on never-worn items and reaches the anchor view — UI half unblocked, view half needs the slot | GLO-145 |
| Analytics drop invisibly; a DEBUG-only signal would make drives falsifiable | GLO-147 |
| `core/Media` is documented in both CLAUDE.md files but has never existed | GLO-148 |
| Typeless storefronts (missha, murad, tatcha, supergoop at ~0 despite the tree) — feeds/Beauty-API bucket, not tree-gated | GLO-99 finding |
| OBF foreign names (category crawl only — brand mode sidesteps); krave maps 0 | GLO-84 / GLO-79 |
| `glossed.app` domain is TAKEN — tech/02's share-URL plan needs a new domain (glossed.beauty was $1.99 at check) | GLO-89 finding |

## 7. Blocked on a human, not on code

| Blocked thing | On what | Who |
|---|---|---|
| Landing-page deploy (→ Rakuten/Impact applications) | Vercel MCP token cannot create projects (403, team role). Create an empty project named `glossed` OR raise the integration's role; the deploy payload is one command away | Sean |
| Rakuten + Impact publisher accounts | Signups (GLO-90/91 carry the exact steps); need the channel URL above | Sean |
| Beauty API key | Free Sandbox+Barcode signup at thebeautyapi.com → `BEAUTY_API_KEY` secret | Sean |
| GLO-145's view half (exclude `want_to_try` from `user_shade_anchor`) | The migration slot is Sean's to grant — session 9 offered to cut it and was told the slot is his call, not free real estate | Sean |
| Any DataKit opening | Per-session authorization. Session 9's bundle is spent and the core refroze | Sean |
| GLO-85 queue consumer | Needs `ANTHROPIC_API_KEY` **and** Sean's direct word — a relayed hand-off of this lane was retracted | Sean |
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

## 9. Local setup

```bash
make setup && make dev
# the full sweep (§5) — run ALL of these, not just the package you touched:
for p in core/DataKit core/DesignSystem core/Tracking features/Shelf \
         features/AddLadder features/Ranking features/ProductPage features/Import; do
  (cd $p && swift test)   # 345 total; rm -rf .build first if a package "won't compile" (§8)
done
supabase test db          # 125 assertions (fresh DB only — §4)
make functions-test       # 56 deno tests
# before trusting ANY claim about events (§0):
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  http://127.0.0.1:54321/functions/v1/track_ingest \
  -H "Authorization: Bearer <anon JWT>" -H 'Content-Type: application/json' -d '{"events":[]}'
# 503 = nothing is serving; start `supabase functions serve` (announce it) before concluding
# and read the drop notices the Tracker now leaves (GLO-147) — the ONLY way to
# see them, because `print` needs `simctl launch --console` and our recipe below
# does not use it:
xcrun simctl spawn 0E1EF64B-E2E3-4A51-B322-29BBEFCEEFE1 log show --last 5m \
  --style compact --debug --info \
  --predicate 'subsystem == "com.glossed.tracking"'
# a line per dropped batch, with the real reason: httpError(code: 503, ...).
# NO lines + events in `events` = instrumentation works. NO lines + no events =
# nothing was tracked, which is a code bug. That distinction is the whole point.
# catalog data — SIX scripts, in this order:
deno run --allow-net --allow-run --allow-env scripts/shopify_import.ts
deno run --allow-net --allow-run --allow-env scripts/obf_import.ts
deno run --allow-net --allow-run --allow-env scripts/obf_import.ts --brands
deno run --allow-net --allow-run --allow-env scripts/shopify_images.ts
SUPABASE_SERVICE_ROLE_KEY=<legacy JWT from supabase status> \
  deno run --allow-net --allow-run --allow-env --allow-read --allow-write scripts/catalog_images.ts --limit 6000
deno run --allow-run --allow-env scripts/brand_merge.ts
# the merge queue's adjudication surface:
deno run --allow-run --allow-env scripts/merge_feeder.ts --pending
# (obf_requalify.ts is a one-off, already applied — rerun only if OBF
# images somehow re-enter under the 800px floor)
```

**The simulator canon: iPhone 16 Pro (iOS 18.0), UDID
`0E1EF64B-E2E3-4A51-B322-29BBEFCEEFE1` — one booted device, always;**
shut down strays, borrow with a ping when two sessions run. Bundle id
`com.glossed.app`. Screenshot pixels ≠ points (§8). Launch:
`supabase start`, then
`SIMCTL_CHILD_SUPABASE_PUBLISHABLE_KEY=<from supabase status>` +
`simctl terminate/install/launch`. Sign-in fails → reset (with the ping).
`GLOSSED_SCREENS=1` opens the picker. The local storage API wants the
**legacy JWT** service key, not `sb_secret_…`. Functions are served only
by a session-scoped `supabase functions serve` (§0 — check for a stale one
with a mock env before trusting function behavior).
