# Session handoff — Aug 28 2026 (sessions 4–5, ending mid-merge)

Where Phase 1 stands, what to do next, and what this session learned. Read
`docs/README.md` first for the design; this file is only about state.

## 0. Read this first

**The merge sequence completed in-session**: #121, #123, and #126 all merged
green (real iOS runs where the diff warranted one), `origin/main` rebuilt and
verified, [GLO-74](https://linear.app/glossed/issue/GLO-74) closed, **zero
open PRs** at handoff. The catalog scripts now live on `main` under
`scripts/`.

**A skipped CI check is still not a passed check**
([GLO-71](https://linear.app/glossed/issue/GLO-71) remains unfixed): rebase
onto the base's exact tip, read WHICH jobs ran. Every merge across these two
sessions was verified this way — all iOS runs were real (5m53s–10m33s).

**Local dev needs no scheme editing:** `supabase start`, then launch with
`SIMCTL_CHILD_SUPABASE_PUBLISHABLE_KEY=<from supabase status>` +
`simctl terminate/install/launch`. If sign-in fails: `supabase db reset`
first. `GLOSSED_SCREENS=1` opens the screen picker instead of the app.

## 1. Where to start

Tracked in **Linear**: workspace [glossed](https://linear.app/glossed), team
**GLO**, project **GLOSSED — Phase 1: The Journal**.

| Next | Why |
|---|---|
| [GLO-79](https://linear.app/glossed/issue/GLO-79) source ladder, next rungs | The Shopify rung shipped and proved the thesis (studio shots mask clean). Next: widen the curated store list; fix title-matching's wrong-franchise risk (it picked fenty's *powder* over the liquid — prefer exact name+shade, else hand-check); og:image lands with GLO-19; feeds when Sean flips Rakuten from reach |
| [GLO-16](https://linear.app/glossed/issue/GLO-16) logging sheet / variant pick | The biggest remaining unlock: search/near-match picks dead-end at an interim card until it exists. **Unblocked** — Sean's no-frames ruling (§6): build from the design system, workshop at review |
| [GLO-72](https://linear.app/glossed/issue/GLO-72) status change + remove | Same ruling; `remove()` exists in DataKit, `updateStatus` needs a core opening (re-ask) |
| [GLO-73](https://linear.app/glossed/issue/GLO-73) shelf search | Same ruling |
| Event wiring | `core/Tracking` + `events` + `track_ingest` exist; **nothing calls `track()` yet** |
| [GLO-63](https://linear.app/glossed/issue/GLO-63) item 3 | Near-match RPC with a reason. Migration slot free (0015 merged + hosted) |
| [GLO-76](https://linear.app/glossed/issue/GLO-76) disabled buttons | Small DesignSystem PR; visible on the create form |

**Done in sessions 4–5 (do not re-do):** fit persistence end-to-end
(#110/#112); migration 0014 + `PersonalProductDraft.variant` (#113/#114,
GLO-75 closed); the create rung (#115/#116) — **all five ladder rungs
exist**; the **app shell** (#118/#119, GLO-77 closed): DEBUG builds
cold-launch signed in as the seeded user, three tabs + plus drawer, the
drawer's *add a product* runs the whole ladder as one flow, adding a product
refreshes the shelf; **the catalog is real** (GLO-78: 435 brands / 788
products / 788 variants with GTINs from Open Beauty Facts); **the image
pipeline is real** (588 clean cutouts + 5 Shopify studio images on local
storage; migration 0015 exposes them; `ProductImage` renders the fallback
chain; the shelf shows real product photos). Handoffs #117/#120 merged;
migrations 14 and 15 applied to hosted immediately after merge.

## 2. What exists

| Layer | State |
|---|---|
| Schema | **15 migrations**, all applied to hosted. **114 pgTAP assertions.** Slot free. |
| Catalog data | **435 brands / 788 products / 788 variants with real GTINs** (`source='obf'`), local only — hosted has schema, not data. **593 catalog images** in the local `catalog` storage bucket (588 OBF clean-gated + 5 Shopify studio); 200 OBF images rejected by the person gate. |
| `core/DataKit` | Frozen again — all session openings merged. 33 tests. |
| `core/DesignSystem` | + `ProductImage` (fallback chain) + shared `ProductSticker`. 38 tests. |
| `core/Tracking` | Exists; nothing calls `track()`. 10 tests. |
| `core/Media` | Does not exist — user cutouts are GLO-16 PR 1. |
| `features/Shelf` | Live screen: real images, volume-scaled, centred planks, contact shadows, persisting fit section. 58 tests. |
| `features/AddLadder` | All five rungs + `LadderFlowView` (one trip). 86 tests. |
| `app/` | **A real app in DEBUG**: `AppShell` + `AppSession` (dev sign-in, local stack), tabs, drawer, ladder, live shelf. Release builds keep the placeholder until GLO-18/GLO-23. |
| `scripts/` | `obf_import.ts` (catalog fill), `catalog_images.ts` (download → Vision cutout + person gate → storage), `shopify_images.ts` (studio-image rung), `CatalogCutout` (Swift/Vision tool). |
| `supabase/functions` | 5 functions, 49 deno tests, none deployed (secrets — §7). |

The sentence that is true about all of it: **the app is live against the
local stack only** — hosted has migrations but no catalog data, no functions,
no storage bucket; nothing user-facing exists outside DEBUG builds.

## 3. How this session worked

Unchanged: branches `feat/GLO-<n>-desc`, ≤5 files/400 lines
(`size-override` + written reason when tests/pipelines justify — #115, #121),
squash merges, stacked PRs retarget-then-restack, one migration PR at a time
applied to hosted immediately, `origin/main` built after stacks. Authorizations
are **per-session** and were granted for these: self-merge on green, DataKit
openings (draft variant; ShelfRow fields). Re-ask next session.

The loop that keeps working: frame first (as source, via the browser pane —
`docs/DESIGN.md`; where no frame exists, Sean's ruling in §6 applies), model
first, view to the frame, picker states incl. failures, **drive it on the
simulator**, verify DB effects in psql, restack, merge, rebuild main.

## 4. Frozen or dangerous areas

Unchanged: `core/DataKit` (openings are per-session asks), `supabase/
migrations/` (lock + apply-to-hosted), CI workflows (GLO-71 is a human's),
`ingest_jobs` claiming (the state-filtered UPDATE **is** the lock — both
pipeline scripts use it; do not "improve" it).

New: **image-host allowlist** in `catalog_images.ts` — one host per source
rung. A queued URL on an unknown host is a bug or an injection; widen the
list only when adding a rung (the Shopify rung forgot this and failed 5 jobs
until the allowlist grew).

## 5. How work gets reviewed

Driving the build catches what nothing else does. This session: the floating
nav rendered **on top of** the item sheet (shell bug); the category select
held a view-local copy of the pick and lied after a failed write; disabled
buttons look enabled (GLO-76); OBF's crowd photos put **hands** on the shelf.
None of these had a failing test. The manual recap workflow was again unused;
psql after every driven write (`item_fits`, `failed_searches`, `products`)
is the fastest truth check.

## 6. Decisions made these sessions (by Sean, in-session)

| Decision | Answer | Consequence |
|---|---|---|
| Self-merge on green? | Yes, per-session | 12 PRs merged across sessions 4–5; re-ask |
| Frames for missing UI? | **"I won't be adding frames — build from the design system"**, workshop at review | Frame-*blocked* is over for absent frames; kit-framed screens still build to the frame exactly |
| Real auth now? | Defer — "wire the app as if it works" | Dev session ships; GLO-23 carries the setup list (Apple Developer + Twilio) |
| Rakuten/Impact? | Reach, not blocker | `feed_diff` stays on fixtures; **flipping this also unlocks the best image source** (GLO-79 rung 1) |
| OBF images? | Retired after seeing them — "good ingredient source, bad image source" | Person gate added (25% of OBF images had people); source ladder filed (GLO-79); Shopify rung shipped same-day |
| Shelf layout | Centre the planks; commit to the shelf (contact shadows); scale must track size | All shipped in the adoption branch |

## 7. Blocked on a human, not on code

| Blocked thing | On what | Who |
|---|---|---|
| Best image source (feeds) + real catalog spine | Rakuten/Impact applications — **currently "reach" by choice; the application hour also buys studio images** | Sean |
| R2 (prod storage) | Cloudflare provisioning (GLO-48) — dev runs on local Supabase storage meanwhile | Sean |
| Function deploys | `INGEST_SECRET`, `ANTHROPIC_API_KEY` secrets | Sean |
| Real auth + TestFlight | Apple Developer + Twilio setup (GLO-23/GLO-50), deferred by choice | Sean |
| GLO-71 CI scope fix | Workflow edit | Any human; agents barred |
| Beauty API archive (images rung 2) | Licensed, quote-based — PRD says don't buy until hit-rate says | Sean |

## 8. What went wrong, so you don't repeat it

Sessions 1–3 (preserved): built to primitives when frames were reachable;
`git push -q` hid a failure; planned against a core that couldn't supply the
data; fixed a bug that wasn't there; one number in two places; stacked
squash double-apply (→ build main after stacks); scope-job silent skip (→
read which jobs ran); green test testing its own decoder; seeded users that
could never sign in (a fixture nothing consumes is not known to work); a
background task switched branches mid-flight (never background branch
switches); secrets must be squashed out of history; stale simulator binaries
(terminate+install+launch, md5 when in doubt).

**Session 4:** `--delete-branch` on a stack parent auto-closes the child PR,
unrecoverably (#111 → recreated). Piping build/lint into `tail`/`grep` eats
the exit code — twice a failed lint committed anyway; check `$?` on the bare
command. A view-local `@State` copy of model state lied on screen (category
select); bind to the model.

**Session 5:** *The wrong detector shape:* hand-pose found **nothing** in a
photo that was 60% arm — it wants articulated joints. Person *segmentation*
separated cleanly (hands 0.75–60% of pixels, clean products exactly 0).
When a detector fails, question the detector's task definition before the
threshold. *The allowlist that didn't grow:* adding the Shopify rung without
widening the image-host allowlist dead-lettered 5 good jobs. *Ran pipeline
scripts from the wrong branch* — mid-stack, scripts existed on one branch
only; `git branch --show-current` before running repo scripts.
*Title-matching picked the wrong product in a franchise* (fenty powder vs
liquid): shortest-containing is not exact; prefer name+shade equality and
route the rest to hand-check. *Crowd-photo quality is a data fact, not a
styling problem:* 25% of OBF beauty images contain people; no amount of
cutout tuning fixes the source. And a process one: when the human interrupts
a CI watch, **record the in-flight state in the handoff instead of
re-watching** — that is what §0 is.

## 9. Local setup

```bash
make setup && make dev
supabase test db          # 114 assertions
make functions-test       # 49 deno tests
# catalog data:
deno run --allow-net --allow-run --allow-env scripts/obf_import.ts
SUPABASE_SERVICE_ROLE_KEY=<legacy JWT from supabase status> \
  deno run --allow-net --allow-run --allow-env --allow-read --allow-write scripts/catalog_images.ts
```

Note: the local **storage API wants the legacy JWT** service key
(`eyJ…` from `supabase status`), not the new `sb_secret_…` form.
