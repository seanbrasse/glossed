# Session handoff — Aug 29 2026 (session 8: the catalog tripled, the tree grew, everything else is Sean-gated)

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

**Nothing serves functions locally right now.** The mock-env
`functions serve` hazard from the last handoff is moot — both instances
died with their sessions. The edge runtime container has still NEVER
served functions on its own; start a clean session-scoped serve when you
need one, announce it like a simulator borrow, and never /dev/null its
output.

**Never `--delete-branch` in merge automation** (killed #159 through a
reused watcher script). Delete branches only after a stack fully lands, by
hand.

**Authorizations are per-session and all expired with session 8.** The
session had: self-merge on green (the shelf session merged #173–#189
under it), the migration slot for 0019 (claimed in writing, applied to
hosted at merge), and Sean rulings recorded on tickets — the category
tree (GLO-102 + GLO-81's makeup half), the OBF image standard (GLO-104),
the OBF brand mode's English-only rule (GLO-105), the bare filter chrome,
the plus-outside-nav, and GLO-100's wishlist sketch. Re-ask everything;
rulings on tickets stand. NO DataKit openings happened this stretch — the
core stayed frozen through eighteen PRs.

## 1. Where to start

Tracked in **Linear**: workspace [glossed](https://linear.app/glossed), team
**GLO**, project **GLOSSED — Phase 1: The Journal**.

**Everything unblocked is done. Every row below routes through Sean** —
the next session's first real act is asking, not building.

| Next | Why |
|---|---|
| The DataKit opening bundle | ONE ask covers three tickets: chips live-wiring (4 calls, [GLO-16](https://linear.app/glossed/issue/GLO-16)), like_state decode + updateLikeState ([GLO-87](https://linear.app/glossed/issue/GLO-87) slice 2, view migration slot is free), and a response-returning function call ([GLO-93](https://linear.app/glossed/issue/GLO-93) client wiring) |
| Beauty API key + Vercel project | The drugstore tier's REAL coverage (The Ordinary sits at 9 rows — its honest open-world ceiling) and the GLO-89→90/91 affiliate arc both start at Sean's keyboard |
| Workshop pass (Sean) | Accumulated: FitPromptCard, variant sheet 6-row/5.5 viewport, GLO-87 icons, bay-upright overlap, GLO-100's two open questions (wishlist log → fit prompt? toggle's home?), concealer-anchor call (flagged in the seed), new categories' wear-in numbers, essence→toner mapping |
| [GLO-85](https://linear.app/glossed/issue/GLO-85) queue consumer | 3,264 pending after the feeder; tonight's finding INVERTED the canary: only FIVE cross-source pairs (OBF-drugstore and Shopify-DTC barely intersect) — size the consumer for feed-arrival, not for tonight |
| [GLO-84](https://linear.app/glossed/issue/GLO-84) | Foreign-name decision now PARTIALLY sidestepped (brand mode is English-only by construction) but the category crawl still imports what it finds — the ruling still matters there |

**Done in session 8 — 18 PRs #172–#189, zero open, main verified at
`20bca4b`.** The catalog arc (both sessions): storefronts 12→64
(#172/#175/#177/#184 — GLO-94/97/99 + revlon), the colourpop
title-is-shade fix (#174, GLO-95), the category tree 8→22 (#183 GLO-102
skincare/hair + #186 GLO-81 makeup, both Sean-ruled), search-by-what-it-IS
(#181/#182, GLO-101 — migration 0019 hosted: product_type/tags/origin +
token-AND search_catalog), the OBF image standard (#185, GLO-104 — 800px
source floor, 588 purged, kept 0), OBF brand mode (#188, GLO-105 —
English-only drugstore pull, +279), brand consolidation (#189, GLO-106).
The app arc (shelf session): ladder fresh-trip fix (#173, GLO-96),
numeric shade sort (#176, GLO-98), bare filter chrome (#178/#179),
plus-outside-nav (#180), wishlist ghosts (#187, GLO-100 proposal).
Closed: GLO-94–99 + 100(proposal) + 101–106. The promo-name strip
(GLO-103) rode #183.

## 2. What exists

| Layer | State |
|---|---|
| Schema | **19 migrations**, all applied to hosted (0019 search-attrs at merge). **125 pgTAP assertions.** Slot free (like_state view migration is next in line). |
| Catalog data | **3,349 products / 9,019 variants / 7,625 images / 497 brands / 22 categories**, local-only; **3,264 pending merge_candidates**, image queue ZERO. Every image meets the standard (OBF's 588 sub-800px purged, GLO-104). Search knows what things ARE: product_type/tags/origin live on 1,836+ rows — "korean sunscreen", "lipgloss", "retinol" all answer. Restore recipe: §9 — now SIX scripts. Maya's shelf carries drive-drift rows — fine for dev; a pgTAP run wants a reset + ping. |
| `core/DataKit` | Frozen — and it STAYED frozen through all 18 of session 8's PRs (feature seams + app-layer composition covered everything). 37 tests. |
| `core/DesignSystem` | + Segmented bare chrome, plus-outside-nav FloatingNav. 38 tests. |
| `core/Tracking` | track() real (item_logged / item_status_changed / item_removed → `events`, psql-verified). 11 tests. |
| `features/Shelf` | + wishlist ghosts (GLO-100: want-to-try off by default, bookmark toggle, search always finds), bare domain filter. 96 tests. |
| `features/AddLadder` | + fresh-trip per presentation (GLO-96), numeric shade sort (GLO-98). 98 tests. |
| `app/` | Tracker wiring, fit-at-log seam + FitPromptCard (the prompt lives HERE, not in Shelf), catalogImageBase. |
| `web/landing/` | Static landing page for the affiliate applications. On main, NOT deployed (§7). |
| `scripts/` | shopify_import (fill + collapse + title-is-shade + promo strip), obf_import (category crawl + **--brands** drugstore mode), shopify_images, catalog_images (+ OBF 800px gate), obf_requalify, brand_merge (curated), merge_feeder. |
| `supabase/functions` | 6 functions, 56 deno tests, none deployed; nothing serves them locally right now (§0). |

The sentence that is true about all of it: **the app is live against the
local stack only** — hosted has all 19 migrations and no data, no
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

Driving the build kept catching what nothing else did — this stretch: the
40-shade sheet could strand you (pickable but confirm off-screen; drive the
EXTREME fixture, not the sole-variant case), the status write slammed the
sheet shut until defer-to-close, and Sean's own eyes caught the mock-image
regression within minutes of it appearing. psql after every driven write
remains the fastest truth check. For external APIs, the drive equivalent
is a mock upstream + the audit-trail count — `barcode_fill`'s budget gate
was proven by showing the mock's log stayed empty.

## 6. Open threads

| Thread | Where |
|---|---|
| The DataKit opening bundle (chips 4-call + like_state + response-invoke) — THE ask | GLO-16 / GLO-87 / GLO-93 |
| Beauty API sandbox key → function secret; then GLO-93 client wiring | GLO-93 / §7 |
| Vercel deploy of `web/landing/` → the channel URL → GLO-90/91 applications | GLO-89 / §7 |
| GLO-85 queue consumer, sized for FEED-arrival (tonight's inverted canary: 5 cross-source pairs total — OBF-drugstore and Shopify-DTC barely intersect) | GLO-85 → GLO-14 |
| Workshop accumulation: FitPromptCard, sheet 6-row/5.5, GLO-87 icons, bay-upright overlap, GLO-100's two questions, concealer-anchor, new wear-ins, essence→toner | §1 |
| Fit-at-log's matched-barcode door: no prompt, no event (no category on a bare variant lookup) | GLO-16 ticket note |
| Typeless storefronts (missha, murad, tatcha, supergoop at ~0 despite the tree) — feeds/Beauty-API bucket, not tree-gated | GLO-99 finding |
| OBF foreign names (category crawl only — brand mode sidesteps); krave maps 0 | GLO-84 / GLO-79 |
| `glossed.app` domain is TAKEN — tech/02's share-URL plan needs a new domain (glossed.beauty was $1.99 at check) | GLO-89 finding |

## 7. Blocked on a human, not on code

| Blocked thing | On what | Who |
|---|---|---|
| Landing-page deploy (→ Rakuten/Impact applications) | Vercel MCP token cannot create projects (403, team role). Create an empty project named `glossed` OR raise the integration's role; the deploy payload is one command away | Sean |
| Rakuten + Impact publisher accounts | Signups (GLO-90/91 carry the exact steps); need the channel URL above | Sean |
| Beauty API key | Free Sandbox+Barcode signup at thebeautyapi.com → `BEAUTY_API_KEY` secret | Sean |
| DataKit openings (chips 4-call; like_state + response-invoke) | Per-session authorization | Sean |
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

## 9. Local setup

```bash
make setup && make dev
supabase test db          # 125 assertions (fresh DB only — §4)
make functions-test       # 56 deno tests
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
