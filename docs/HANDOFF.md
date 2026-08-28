# Session handoff — Aug 28 2026 (session 6, merge-as-you-go)

Where Phase 1 stands, what to do next, and what this session learned. Read
`docs/README.md` first for the design; this file is only about state.

## 0. Read this first

**After retargeting a stacked PR to main, CI's scope job can silently reuse a
stale decision and skip the iOS job** (GLO-71's bug, hit three times this
session — #131, #133, #139). A skipped check is not a passed check. The
routine that works: rebase onto the base's exact tip, push, **check that the
iOS job actually queued**; if it shows `skipping`, `git commit --amend
--no-edit` for a fresh SHA and push again — the new run re-evaluates scope
correctly. Read WHICH jobs ran before merging, every time.

**Authorizations are per-session and all expired with this one.** Session 6
had: self-merge on green ("Merge as you go" — 15 PRs merged under it), one
DataKit opening (CatalogHit image fields, from Sean's search-images ask).
Re-ask before merging or touching the frozen core.

## 1. Where to start

Tracked in **Linear**: workspace [glossed](https://linear.app/glossed), team
**GLO**, project **GLOSSED — Phase 1: The Journal**.

| Next | Why |
|---|---|
| [GLO-85](https://linear.app/glossed/issue/GLO-85) remaining halves | The shade collapse merged (#142); still open: the merge-candidates feeder (similarity band → queue, never auto-merge) and the adjudication path. The measurements and the wrong-franchise warning are on the ticket |
| [GLO-72](https://linear.app/glossed/issue/GLO-72) status half | Remove is merged and driven; status change is hard-blocked on a DataKit opening (`updateStatus(itemID:to:)`) — re-ask, and bundle GLO-56's `strength_pct` decode into the same opening. The rank_positions decision for removed ranked items also waits on Sean (proposal on the ticket) |
| [GLO-80](https://linear.app/glossed/issue/GLO-80) first track() calls | Nothing calls the tracker; the ticket carries the real design question (who owns the Tracker; where `item_logged`'s categoryID comes from — the pick path only has a slug) |
| [GLO-16](https://linear.app/glossed/issue/GLO-16) remainder | Logging sheet + variant pick shipped (#128/#129). Still open: chips/notes/status on the item sheet, fit-at-log-time on the ladder path, capture flow, cutout pipeline (R2-blocked) |
| [GLO-84](https://linear.app/glossed/issue/GLO-84) follow-up decision | The digit-name filter merged; the OBF foreign-language-names question is noted there for Sean |
| [GLO-63](https://linear.app/glossed/issue/GLO-63) item 3 | Near-match RPC with a reason. Migration slot is free again (0016 merged + hosted) |

**Done in session 6 (do not re-do), 15 PRs #128–#142, zero open at handoff:**
the **variant-pick logging sheet** (#128/#129 — the search dead-end is gone;
GLO-56's pick has an owner); **shelf item remove** (#130/#131, GLO-72's
authorization-free half); **disabled buttons** (#132, GLO-76 closed, the
kit's own 45% recipe); **find-on-shelf search** (#133/#134, GLO-73 —
matching rule + field, no autocorrect); **Shopify catalog fill** (#135,
GLO-81 closed — 12 storefronts, the `lip` category added to the seed,
flagged for tree workshop); **size buckets** (#136/#137, GLO-82 — S/M/L
44/60/78 with width caps; 4 larges per shelf guaranteed by test);
**search-result images** (#138/#139/#140, GLO-83 closed — migration 0016
merged **and applied to hosted**, CatalogHit opening, rows + variant sheet
draw real cutouts); **GTIN-as-name filter** (#141, GLO-84 closed);
**per-shade collapse** (#142 — fenty 562 rows → 61 products with shade
variants).

## 2. What exists

| Layer | State |
|---|---|
| Schema | **16 migrations**, all applied to hosted (0016 applied via Supabase MCP immediately after merge). **116 pgTAP assertions.** Slot free. |
| Catalog data | **~1,114 products / ~2,171 variants** local-only (shopify + obf + seed), post-collapse; sources gated against exact dupes and digit names. Image pipeline refilling storage in the background at handoff (~1.6k queued) — images arrive as it drains; the mock floor covers the gap. |
| `core/DataKit` | Frozen again — session-6 opening (CatalogHit image fields) merged. 34 tests. |
| `core/DesignSystem` | + disabled button state, ProductImage aspect envelope + per-call `maxWidth`. 38 tests. |
| `core/Tracking` | Exists; **still nothing calls `track()`** (GLO-80). 10 tests. |
| `features/Shelf` | Live: search field, remove on the sheet, S/M/L size buckets, real images. 75 tests. |
| `features/AddLadder` | All five rungs + variant-pick sheet + real images on rows and sheet. 93 tests. |
| `app/` | DEBUG shell unchanged in shape; ladder now gets `catalogImageBase` from the session. |
| `scripts/` | + `shopify_import.ts` (catalog fill + shade collapse). Both importers reject digit-only names. |
| `supabase/functions` | 5 functions, 49 deno tests, none deployed (secrets — §7). |

The sentence that is true about all of it: **the app is live against the
local stack only** — hosted has all 16 migrations but no catalog data, no
functions, no storage; nothing user-facing exists outside DEBUG builds.

## 3. How this session worked

Unchanged: branches `feat/GLO-<n>-desc` (also `fix/`), ≤5 files/400 lines
(`size-override` + reason when justified — #129), squash merges, stacked PRs
retarget-then-restack (now with §0's fresh-SHA step), one migration PR at a
time applied to hosted immediately, `origin/main` rebuilt after stacks.

The loop that kept working: check the kit first and record the frame absence,
model PR then UI PR, picker states incl. failures, **drive it on the
simulator**, verify DB effects in psql, restack, merge on green, rebuild
main. Sean steered live mid-session (buckets, search images, the bug report)
— tickets were created/updated in Linear at each turn, which is what made
the pivots cheap.

## 4. Frozen or dangerous areas

Unchanged: `core/DataKit` (openings are per-session asks), `supabase/
migrations/` (lock + apply-to-hosted), CI workflows (GLO-71 is a human's),
`ingest_jobs` claiming (the state-filtered UPDATE **is** the lock), the
image-host allowlist in `catalog_images.ts` (one host per rung).

New: **`supabase test db` runs against the live local DB, not a fresh
container.** A session that has logged/removed items or re-imported the
catalog will fail state-dependent pgTAP tests that pass in CI. Reset before
trusting a local red — and know that reset costs the imported catalog and
its images (scripts restore ~40 min in the background; three resets this
session).

## 5. How work gets reviewed

Driving the build still catches what nothing else does. This session: the
empty-variants sheet showed an unpressable CTA (fixed pre-PR); the remove
confirm-line truncated instead of wrapping; the simulator autocorrected
"fenty" → "Fentyen" in the search field (a search that corrects is a shelf
claiming you own nothing); Sean's own drive caught the GTIN-as-name row
(GLO-84). psql after every driven write remains the fastest truth check.
None of these had a failing test.

## 6. Open threads

| Thread | Where |
|---|---|
| Merge-candidates feeder + adjudication | GLO-85 |
| `updateStatus` opening + rank_positions decision | GLO-72 |
| First `track()` calls + categoryID question | GLO-80 |
| Chips/notes/status on item sheet; fit-at-log; capture flow | GLO-16 |
| `lip` category + the tree workshop; per-kind mm table + bucket thresholds | GLO-81 / GLO-82 (Sean workshops) |
| OBF foreign-language names | GLO-84 (note) |
| Variant sheet shared with Import (features can't import features) | GLO-56 |
| krave maps 0 products (product_type mismatch) | GLO-79 comment |

## 7. Blocked on a human, not on code

| Blocked thing | On what | Who |
|---|---|---|
| Best image source (feeds) + catalog spine | Rakuten/Impact applications — still "reach" by choice; value rose again (also the Sephora/Ulta catalog) | Sean |
| R2 (prod storage) | Cloudflare provisioning (GLO-48) | Sean |
| Function deploys | `INGEST_SECRET`, `ANTHROPIC_API_KEY` secrets | Sean |
| Real auth + TestFlight | Apple Developer + Twilio (GLO-23/GLO-50), deferred by choice | Sean |
| GLO-71 CI scope fix | Workflow edit — the §0 workaround exists but the fix is a human's | Any human; agents barred |
| DataKit openings (`updateStatus`, `strength_pct`) | Per-session authorization | Sean |
| Beauty API archive | PRD says wait for hit-rate data | Sean |

## 8. What went wrong, so you don't repeat it

Sessions 1–5 (preserved): built to primitives when frames were reachable;
`git push -q` hid a failure; planned against a core that couldn't supply the
data; fixed a bug that wasn't there; one number in two places; stacked
squash double-apply (→ build main after stacks); scope-job silent skip (→
read which jobs ran); green test testing its own decoder; seeded users that
could never sign in; a background task switched branches mid-flight; secrets
must be squashed out of history; stale simulator binaries; `--delete-branch`
on a stack parent auto-closes the child PR; piping build/lint into
`tail`/`grep` eats the exit code; a view-local `@State` copy lied on screen;
hand-pose vs person-segmentation (question the detector's task definition);
the allowlist that didn't grow; ran pipeline scripts from the wrong branch;
title-matching picked the wrong franchise; record in-flight CI state in the
handoff instead of re-watching.

**Session 6:** *The pipe ate the exit code again* — `make lint | tail` let a
file-length violation commit; the same trap the handoff already warned
about; check `$?` on the bare command, always. *An amend landed on the wrong
branch* (cut the child branch, then fixed the parent's lint — the amend
rewrote the child; repoint with `git branch -f`, and never fix a parent
after cutting its child without checking `--show-current`). *A dirty working
tree silently skipped a rebase in a `&&` chain* — twice; the chain's later
steps then "succeeded" against the unrebased branch, and #140 nearly went up
reverting merged work. Rebase with a clean tree, and verify the rebase line
actually says "Successfully rebased". *`swift test` builds packages for
macOS* — `.textInputAutocapitalization` compiled fine in the iOS app build
and failed CI's package build; run `swift test` in the package, not just
`xcodebuild`, before pushing UI with platform-gated modifiers. *The picker's
fixture rungs don't host flow transitions* — tapping "none of these" in a
single-rung picker state moves the ladder but not the screen; drive
transitions in the shell. *Retarget scope-skip* (→ §0). *`supabase test db`
is not hermetic* (→ §4).

## 9. Local setup

```bash
make setup && make dev
supabase test db          # 116 assertions (fresh DB only — §4)
make functions-test       # 49 deno tests
# catalog data (order matters: shopify first claims the good names):
deno run --allow-net --allow-run --allow-env scripts/shopify_import.ts
deno run --allow-net --allow-run --allow-env scripts/obf_import.ts
SUPABASE_SERVICE_ROLE_KEY=<legacy JWT from supabase status> \
  deno run --allow-net --allow-run --allow-env --allow-read --allow-write scripts/catalog_images.ts --limit 2500
```

**The simulator canon: iPhone 16 Pro (iOS 18.0), UDID
`0E1EF64B-E2E3-4A51-B322-29BBEFCEEFE1` — one booted device, always.** All of
session 6's drives, screenshots and psql-verified flows ran there. Sessions
4–5 used an iPhone 16 Plus (iOS 18.2); its leftover booted instance
misdirected a screenshot this session — `xcrun simctl shutdown <udid>` any
second device before starting. No simulator is "more accurate": the shelf
measures its width per device and bay capacity differs with it (GLO-68), so
screenshots only compare on the same device — which is the whole reason for
a canon. The size-bucket 4-larges guarantee targets the narrowest class
(375pt) and is held by test, not by the device you happen to drive.

Launch: `supabase start`, then
`SIMCTL_CHILD_SUPABASE_PUBLISHABLE_KEY=<from supabase status>` +
`simctl terminate/install/launch`. Sign-in fails → `supabase db reset`
first. `GLOSSED_SCREENS=1` opens the screen picker. The local storage API
wants the **legacy JWT** service key (`eyJ…`), not `sb_secret_…`.
