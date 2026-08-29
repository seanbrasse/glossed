# Session handoff — Aug 29 2026 (session 7 wrap: two-session mode, both queues settled)

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

**A `supabase functions serve` may still be running with a MOCK env.** The
barcode_fill drive ran one from the dev worktree with
`BEAUTY_API_KEY=test-key-123` and a fake upstream base; a second serve from
the other worktree may have raced it, and whichever bound second errored
silently into /dev/null. Both die with their sessions — but if functions
answer strangely, kill any serve you find and restart clean (or
`supabase stop/start` to re-bake the runtime, which has never served
functions on its own — the container predates them all).

**Never `--delete-branch` in merge automation** (killed #159 through a
reused watcher script). Delete branches only after a stack fully lands, by
hand.

**Authorizations are per-session and all expired with session 7.** The
session had: self-merge on green (12 PRs merged under it in the dev
session alone), DataKit openings (#147's updateStatus/strengthPct/
categoryID + #152's `invokeEdgeFunction`, one extended authorization), and
Sean rulings recorded on tickets (GLO-80 categoryID, GLO-72 rank_positions,
GLO-87 supersedes-pills + like_state-as-would-repurchase). Re-ask
everything; rulings on tickets stand.

## 1. Where to start

Tracked in **Linear**: workspace [glossed](https://linear.app/glossed), team
**GLO**, project **GLOSSED — Phase 1: The Journal**.

| Next | Why |
|---|---|
| [GLO-16](https://linear.app/glossed/issue/GLO-16) chips live-wiring | The whole chips+note surface is built and drivable in picker states — blocked ONLY on a DataKit opening (4 calls, the ask is on the ticket, still on Sean's desk). Wire inside GLO-87's tried gate (#160) |
| [GLO-93](https://linear.app/glossed/issue/GLO-93) client wiring | `barcode_fill` is on main (#170), driven against a mock, license-cleared. Needs Sean's free Sandbox+Barcode key (function secret) AND a response-returning function call in DataKit (`invokeEdgeFunction` is fire-and-forget by design) — bundle that ask with like_state |
| [GLO-87](https://linear.app/glossed/issue/GLO-87) slice 2 | Would-repurchase = a `like_state` rendering (Sean's ruling). Needs the view migration (slot is free) + a DataKit opening (decode + updateLikeState) — same opening ask as GLO-93's |
| [GLO-89](https://linear.app/glossed/issue/GLO-89)–[92](https://linear.app/glossed/issue/GLO-92) source arc | Landing page is on main (`web/landing/`, #166) but the Vercel deploy is blocked on Sean (§7). GLO-90/91 (Rakuten/Impact applications) wait on that URL; GLO-92 (Beauty API archive gate) is runnable free anytime |
| [GLO-85](https://linear.app/glossed/issue/GLO-85) adjudication | 364 pending pairs restored post-reset; `merge_feeder.ts --pending` is the surface; verdicts belong to GLO-14's function |
| Workshop pass (Sean) | FitPromptCard (no kit frame — built to G.OnbBuild's spirit), variant sheet's 6-row inline / 5.5-row viewport numbers, GLO-87's icon pair, bay left-align's upright overlap (#155 note) |

**Done since the #163 handoff — 7 PRs #164–#170, zero open, main verified
at `02b6a94`.** Shelf session: fit-at-log (#164/#165,
GLO-16's anchor-gated prompt), variant-sheet viewport cap (#167, GLO-88
closed), lifecycle events end-to-end (#168/#169 — `item_status_changed` /
`item_removed` in the enum, tech/06 registry, shelf firing, psql-verified;
GLO-72 closed). Dev session: landing page (#166, GLO-89), `barcode_fill`
(#170, GLO-93 slice 1). Earlier in session 7, same day: #145–#162 (see
git log; GLO-80/85/86 closed, GLO-56's strength gap closed).

## 2. What exists

| Layer | State |
|---|---|
| Schema | **18 migrations**, all applied to hosted. **121 pgTAP assertions.** Slot free (like_state view migration is next in line). |
| Catalog data | **1,114 products / 2,171 variants / 1,844 images**, local-only; **364 pending merge_candidates** (restored after the reset — the feeder is idempotent). Restore recipe: the FOUR scripts in §9 order (shopify_images is the one everyone forgets — Sean saw mocks when it was). Maya's shelf carries drive-drift rows (revlon colorstay finished + too_light, ouai oil, a soft-deleted fenty #190, 2 events rows) — fine for dev; a pgTAP run wants a reset + ping. |
| `core/DataKit` | Frozen — all session openings merged (CatalogHit images/categoryID, updateStatus, strengthPct, NearMatch, invokeEdgeFunction). 37 tests. |
| `core/DesignSystem` | Disabled buttons, ProductImage envelope + maxWidth. 38 tests. |
| `core/Tracking` | **track() is real** (item_logged, item_status_changed, item_removed all flow to `events`, psql-verified). 11 tests. |
| `features/Shelf` | Search, remove, buckets, chips+note (seamed), GLO-87 icons + tried-reveal + gated chips, the fit store/section, lifecycle events. 91 tests. |
| `features/AddLadder` | Five rungs, variant-pick sheet (capped viewport), real images, near-match reasons. 96 tests. |
| `app/` | Tracker wiring (AppSession/AppShell/TrackIngestPoster), fit-at-log seam + FitPromptCard (the prompt lives HERE, not in Shelf), catalogImageBase. |
| `web/landing/` | **New**: static landing page (pitch + privacy + FTC disclosure + driven screenshots) for the affiliate applications. On main, NOT deployed (§7). |
| `scripts/` | shopify_import (fill + collapse), obf_import, shopify_images, catalog_images, merge_feeder. |
| `supabase/functions` | **6 functions, 56 deno tests**, none deployed. `barcode_fill` (#170): scan-miss → Beauty API GTIN lookup → create-rung pre-fill, never a catalog insert; budget = own audit_records count, gate 95 vs the Sandbox 100 hard cap; license verdict verbatim on GLO-93. |

The sentence that is true about all of it: **the app is live against the
local stack only** — hosted has all 18 migrations and no data, no
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

## 4. Frozen or dangerous areas

Unchanged: `core/DataKit` (openings per-session), `supabase/migrations/`
(lock + apply-to-hosted), CI workflows, `ingest_jobs` claiming (the
state-filtered UPDATE **is** the lock — two concurrent consumers ran fine),
the image-host allowlist (barcode_fill's images.thebeautyapi.com is
deliberately NOT a rung — their license says display-direct, don't
re-host).

Standing: `supabase test db` runs against the **live local DB** — reset
before trusting a local red, ping the other session before resetting,
budget the four-script restore (~40 min).

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
| Chips live-wiring opening (4 calls) — THE ask | GLO-16 |
| Next DataKit opening bundle: like_state decode + updateLikeState + response-returning function call | GLO-87 / GLO-93 |
| Beauty API sandbox key → function secret; then GLO-93 client wiring | GLO-93 / §7 |
| Vercel deploy of `web/landing/` → the channel URL → GLO-90/91 applications | GLO-89 / §7 |
| Fit-at-log's matched-barcode door: no prompt, no event (no category on a bare variant lookup) — same gap as GLO-80's barcode door | GLO-16 ticket note |
| merge_candidates adjudication | GLO-85 → GLO-14 |
| Workshop numbers: FitPromptCard, sheet 6-row/5.5 viewport, GLO-87 icons, bay-upright overlap | §1 last row |
| lip category + tree workshop; OBF foreign names; krave maps 0 | GLO-81 / GLO-84 / GLO-79 |
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

## 9. Local setup

```bash
make setup && make dev
supabase test db          # 121 assertions (fresh DB only — §4)
make functions-test       # 56 deno tests
# catalog data — all four, in this order:
deno run --allow-net --allow-run --allow-env scripts/shopify_import.ts
deno run --allow-net --allow-run --allow-env scripts/obf_import.ts
deno run --allow-net --allow-run --allow-env scripts/shopify_images.ts
SUPABASE_SERVICE_ROLE_KEY=<legacy JWT from supabase status> \
  deno run --allow-net --allow-run --allow-env --allow-read --allow-write scripts/catalog_images.ts --limit 4000
# the merge queue's adjudication surface:
deno run --allow-run --allow-env scripts/merge_feeder.ts --pending
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
