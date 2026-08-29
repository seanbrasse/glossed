# Session handoff — Aug 28–29 2026 (session 6, both halves: solo run + two-session mode)

Where Phase 1 stands, what to do next, and what this session learned. Read
`docs/README.md` first for the design; this file is only about state.

## 0. Read this first

**After retargeting a stacked PR to main, CI's scope job can silently reuse a
stale decision and skip (or outright fail) the iOS job** — GLO-71's bug, hit
SEVEN times across both sessions today. A skipped check is not a passed
check. The routine: rebase onto the base's exact tip, retarget, **then**
`git commit --amend --no-edit` for a fresh SHA and push — the amend must
come AFTER the retarget or the stale scope decision survives. Confirm the
iOS job actually queued before walking away.

**Never `--delete-branch` in merge automation.** A reused watcher script
carried it onto a stack parent and auto-closed the child PR (#159,
unrecoverable — recreated as #161); the same trap as session 4, now proven
to recur through scripts. Delete branches only after a stack fully lands,
by hand.

**Two sessions can run this repo at once, and did.** Worktrees share git
refs and one local DB. What made it work: file-level ownership announced
before touching anything, ping-before-`supabase db reset` (broken once —
it cost the other session's live data), separate simulators or explicit
borrow-pings, and treating a peer-relayed ruling from Sean as actionable
but veto-able. What didn't: assuming; an `ls` is not `git ls-tree`, and a
"duplicate file on main" accusation built on a worktree leftover was wrong.

**Authorizations are per-session and all expired.** Session 6 had:
self-merge on green ("Merge as you go" — 33 PRs merged under it across
both sessions), DataKit openings (CatalogHit image fields; #147's
updateStatus/strengthPct/categoryID; NearMatch via GLO-63's own framing).
Re-ask everything.

## 1. Where to start

Tracked in **Linear**: workspace [glossed](https://linear.app/glossed), team
**GLO**, project **GLOSSED — Phase 1: The Journal**.

| Next | Why |
|---|---|
| [GLO-16](https://linear.app/glossed/issue/GLO-16) chips live-wiring | The whole chips+note surface is built, tested and drivable in picker states behind `ShelfChipStore` — blocked ONLY on a DataKit opening (chips read, remove, vocabulary read, note update; `applyChip` exists). The ask is on the ticket. GLO-87 gated chips on "tried" (#160) — wire inside that gate |
| [GLO-87](https://linear.app/glossed/issue/GLO-87) remaining slices | Slice 1 merged (#160: want/tried icons, tried-reveal, chips gating). Would-repurchase needs `like_state` on the shelf view (a migration, queued behind an opening the dev session hadn't asked for yet) |
| [GLO-16](https://linear.app/glossed/issue/GLO-16) fit-at-log | Buildable since #147 (hits carry `categoryID`) but needs one architecture decision first: the `Fit`↔`FitAnswer` translation lives in features/Shelf and AddLadder would be its second consumer — features can't import features, so it moves to core or gets an interface |
| [GLO-85](https://linear.app/glossed/issue/GLO-85) adjudication path | 364 pending pairs in `merge_candidates`; `scripts/merge_feeder.ts --pending` is the surface; verdict application belongs to GLO-14's function |
| [GLO-72](https://linear.app/glossed/issue/GLO-72) events AC | `item_status_changed`/`item_removed` aren't in the Event enum; belongs with the next Tracking enum PR |
| [GLO-84](https://linear.app/glossed/issue/GLO-84) note | OBF foreign-language names — a Sean decision recorded on the ticket |

**Done in session 6 — 33 PRs #128–#162 (two sessions), zero open at
handoff.** This session's half: variant-pick logging sheet (#128/#129),
remove (#130/#131), disabled buttons (#132), shelf search (#133/#134),
Shopify catalog fill (#135, GLO-81), size buckets → S/M/L ruling
(#136/#137, GLO-82), search-result images (#138–#140, GLO-83, 0016
hosted), GTIN-name filter (#141, GLO-84), shade collapse (#142), chips+note
seam (#148–#150), status model (#156; the pills PR #157 was **closed
unmerged**, superseded by GLO-87 — the branch holds salvage), near-match
reasons (#158/#161/#162, GLO-63, 0018 hosted), handoffs (#143/#144). The
dev session's half: merge feeder (#145), GLO-80 track() end-to-end
(#151–#153, 0017 hosted), #147's DataKit opening, pickLabel strength
(#154), bay left-align (#155, Sean's ask), GLO-87 slice 1 (#160).

## 2. What exists

| Layer | State |
|---|---|
| Schema | **18 migrations**, all applied to hosted (0016/0017/0018 applied via Supabase MCP immediately after merge). **121 pgTAP assertions.** Slot free (the dev session's like_state view migration is next in line). |
| Catalog data | **1,114 products / 2,171 variants / 1,844 images**, local-only, collapsed shape, zero digit names, image queue drained. Restore recipe when a reset costs it: shopify_import → obf_import → **shopify_images (easy to forget — Sean saw mocks when it was)** → catalog_images; two catalog_images consumers are safe (the queue's UPDATE is the lock). |
| `core/DataKit` | Frozen again — session-6 openings all merged (CatalogHit images + categoryID, updateStatus, strengthPct, NearMatch). 37 tests. |
| `core/DesignSystem` | Disabled buttons, ProductImage aspect envelope + maxWidth. 38 tests. |
| `core/Tracking` | **track() is real**: item_logged flows ladder→tracker→track_ingest→events (dev session, verified in psql). Enum still lacks the GLO-72 events. 10 tests. |
| `features/Shelf` | Search, remove, S/M/L buckets, chips+note (seamed), status model, GLO-87 icons + tried-reveal + gated chips. 86 tests. |
| `features/AddLadder` | Five rungs, variant-pick sheet, real images, **near-match reasons + complete match cards**. 96 tests. |
| `app/` | Tracker wiring (AppSession/AppShell/TrackIngestPoster), catalogImageBase environment. |
| `scripts/` | + `shopify_import.ts` (fill + collapse), `merge_feeder.ts` (--pending is the adjudication surface). Importers reject digit names. |
| `supabase/functions` | 5 functions, 49 deno tests, none deployed. **The local edge runtime never served them** — a session-scoped `functions serve` covered it today and died with that session; a full `supabase stop/start` re-bakes the runtime at a quiet moment. |

The sentence that is true about all of it: **the app is live against the
local stack only** — hosted has all 18 migrations and no data, no
functions, no storage.

## 3. How this session worked

Unchanged: branches `feat/GLO-<n>-desc`, ≤5 files/400 lines
(`size-override` + reason when the shape demands it — #129, #162's enum
ripple), squash merges, one migration PR at a time applied to hosted
immediately, main rebuilt after stacks, drive-then-psql on everything.

New: **two sessions in parallel** (see §0), coordinated by direct
session-to-session messages; Linear was the shared ledger and every pivot
(Sean steered live five times: buckets ruling, search images, the GLO-84
bug report, the dedupe question, GLO-87) was written to the ticket at the
turn it happened, which is what made a mid-CI supersession (#157) cost
one closed PR and nothing else.

## 4. Frozen or dangerous areas

Unchanged: `core/DataKit` (openings per-session), `supabase/migrations/`
(lock + apply-to-hosted), CI workflows, `ingest_jobs` claiming (the
state-filtered UPDATE **is** the lock — two concurrent consumers ran fine
on exactly this design), the image-host allowlist.

Standing: `supabase test db` runs against the **live local DB** — reset
before trusting a local red, ping the other session before resetting, and
budget the restore (§2 recipe, ~40 min).

## 5. How work gets reviewed

Driving the build kept catching what nothing else did: the immediate
reload after a status write slammed the sheet shut (→ defer-to-close); the
note editor expanded to fill the screen (TextEditor takes every point
offered); the simulator autocorrected the search field; Sean's own drive
caught the GTIN-as-name row and the missing seed images. psql after every
driven write remains the fastest truth check. None of these had a failing
test.

## 6. Open threads

| Thread | Where |
|---|---|
| Chips live-wiring opening (4 calls) | GLO-16 — the one ask on Sean's desk |
| GLO-87 would-repurchase (`like_state` view migration + opening) | GLO-87 / dev session |
| Fit-at-log + the Fit↔FitAnswer translation home | GLO-16 |
| merge_candidates adjudication | GLO-85 |
| GLO-72 events in the Tracking enum | GLO-72 / GLO-80 note |
| Variant sheet full-height with 14+ shades (cap + inner scroll) | GLO-85 note → GLO-16 sheet |
| lip category + tree workshop; bucket numbers; search-toggle placement | GLO-81/82/73 (Sean workshops) |
| OBF foreign-language names; krave maps 0 | GLO-84 note / GLO-79 comment |
| Edge runtime re-bake (`supabase stop/start`) | §2 |

## 7. Blocked on a human, not on code

Unchanged from the last handoff: Rakuten/Impact (the hour that buys the
best images AND the catalog spine), R2 (GLO-48), function secrets,
Apple/Twilio (GLO-23/50), GLO-71's real fix, Beauty API. Plus the two
per-session re-asks in §0 and the chips opening in §6.

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

**Session 6, first half:** the pipe ate the exit code AGAIN (twice — a
file-length violation and a large-tuple violation both committed before
lint was checked bare); an amend landed on the wrong branch after cutting
its child; a dirty tree silently skipped a rebase inside a `&&` chain —
three separate times, once nearly shipping a PR that reverted merged work
(verify the "Successfully rebased" line, rebase with a clean tree);
`swift test` builds packages for macOS (platform-gated modifiers compile
in the iOS app and fail CI); picker fixture rungs don't host flow
transitions; `supabase test db` is not hermetic.

**Session 6, second half (two-session mode):** `--delete-branch` recurred
through a REUSED WATCHER SCRIPT and killed #159 (the trap survives as long
as the flag lives in any automation); a watcher's unconditional
`echo MERGED` lied about a failed merge (echo only inside the success
branch); two watchers raced one PR (harmless here, but arm exactly one);
I accused the peer of duplicating a file on main from an `ls` of my own
worktree — **an `ls` is not `git ls-tree`**; a blind `str.replace` of a
pgTAP plan count no-op'd silently because the peer had already bumped it
(read the current value, then edit); I broke the ping-before-reset pact I
proposed, and the restore forgot `shopify_images.ts` until Sean saw mocks
— the restore is FOUR scripts, not three; worktrees share refs, so a
branch you never pushed is visible to every session on the machine.

## 9. Local setup

```bash
make setup && make dev
supabase test db          # 121 assertions (fresh DB only — §4)
make functions-test       # 49 deno tests
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
shut down strays before starting, and if two sessions run, borrow with a
ping. Launch: `supabase start`, then
`SIMCTL_CHILD_SUPABASE_PUBLISHABLE_KEY=<from supabase status>` +
`simctl terminate/install/launch`. Sign-in fails → reset (with the ping).
`GLOSSED_SCREENS=1` opens the picker. The local storage API wants the
**legacy JWT** service key, not `sb_secret_…`.
