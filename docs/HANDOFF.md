# Session handoff — Aug 28 2026 (fourth session)

Where Phase 1 stands, what to do next, and the decisions a new session would
otherwise have to rediscover. Read `docs/README.md` first for the design; this
file is only about state.

## 0. Silent failures and standing traps

**CI's scope job can skip every real check and stay green
([GLO-71](https://linear.app/glossed/issue/GLO-71), still unfixed).** The
scope step fetches the PR's base with `--depth=1`; if the base has advanced at
all, `git diff BASE...HEAD` dies with `no merge base`, indistinguishable from
"no changes", and every real job is skipped — five green checks, no build.
**A skipped `build · test (iOS)` on a Swift PR is unproven, not green** —
rebase onto the base's exact tip and read WHICH jobs ran. All six of this
session's merges were verified this way; every iOS run was real (5m53s–10m33s).

**Merging a stacked PR's parent with `--delete-branch` closes the child.**
GitHub closes an open PR when its base branch is deleted, and it cannot be
reopened (#111 → recreated as #112). The sequence that works: merge the parent
*keeping* its branch → retarget the child to main → rebase the child onto the
squash → force-push → delete the parent's branch last.

**Piping a build/lint command into `tail`/`grep` erases its exit code.** Twice
this session a `make lint && git commit` chain committed through a lint
failure because the `| tail -1` in the middle made the failure exit 0. Check
`$?` on the bare command, or commit in a separate step after reading output.

**The local DB predates the current seed until you reset it.** First LIVE
sign-in of the session failed with GoTrue's "Database error querying schema" —
the handoff's own §8 trap from last session. `supabase db reset` fixed it.
When the LIVE picker state errors, reset before debugging the stack.

## 1. Where to start

Tracked in **Linear**: workspace [glossed](https://linear.app/glossed), team
**GLO**, project **GLOSSED — Phase 1: The Journal**.

| Next | Why |
|---|---|
| [GLO-16](https://linear.app/glossed/issue/GLO-16) logging sheet / variant pick | **Unblocked** — Sean ruled (this session, §6) that no frames are coming for missing UI: build from the design system, he workshops at PR review. This is GLO-56's owner and the handoff point search/near-match/import all need |
| [GLO-72](https://linear.app/glossed/issue/GLO-72) item lifecycle | Status change + remove, same no-frame ruling. `ShelfRepository.remove` already exists; `updateStatus` needs a core opening (re-ask) |
| [GLO-73](https://linear.app/glossed/issue/GLO-73) shelf search | Same ruling — build it, workshop it |
| [GLO-74](https://linear.app/glossed/issue/GLO-74) image render chain | The render half of real product images: DataKit exposure (core opening) + a fallback-chain component (cutout → catalog image → mock). Component can land now against fixtures |
| Event wiring | `core/Tracking` + `events` + `track_ingest` all exist and **nothing calls `track()` yet** — wire per-feature while surfaces are fresh |
| [GLO-63](https://linear.app/glossed/issue/GLO-63) item 3 | Near-match RPC with a reason. **Migration slot free** (0014 merged + hosted) |
| GLO-15 leftovers | XCUITest journey (search-miss → scan-miss → near-miss → create → shelf) + ladder events; the rungs themselves are done |
| [GLO-76](https://linear.app/glossed/issue/GLO-76) disabled buttons | DesignSystem: disabled `.glossed` renders identical to enabled — small, its own PR |

**Merged this session (do not re-do):** #110/#112 (item-sheet **fit
persistence** — `ShelfFitStore`, `FitAnswer↔Fit`, model-owned fit with
revert-on-failure; sheet fit is a `Binding`; the `shelf · LIVE` state reads
and writes `item_fits` end to end, verified against the seeded stack: capture,
reopen-shows-saved, `just right` replaces wholesale). #113 (**migration 0014**:
`create_personal_product` gains `p_variant` → `shade_code`, applied to hosted
immediately; pgTAP at 111). #114 (DataKit: `PersonalProductDraft.variant` —
authorized opening). #115/#116 (**the create rung**: create+log service with
the created-but-not-shelved seam and same-clientID retry; the form built to
the frame with brand typeahead FK; three picker states; driven on simulator).
Tickets: GLO-75 opened and closed; GLO-72/73/74/76 opened.

## 2. What exists

| Layer | State |
|---|---|
| Schema | **14 migrations**, all applied to hosted. **111 pgTAP assertions.** Migration slot free. |
| `core/DataKit` | Frozen again. This session's authorized opening: `PersonalProductDraft.variant`. 33 tests. |
| `core/DesignSystem` | Unchanged this session. GLO-76 filed (disabled buttons). 38 tests. |
| `core/Tracking` | Exists; **nothing calls `track()` yet.** 10 tests. |
| `core/Media` | Still does not exist — R2 (§7). |
| `features/Shelf` | Screen + mapping + **persisting fit section**. 54 tests. |
| `features/AddLadder` | **All five rungs built** — search, barcode, near matches, create, confirm. 86 tests. Missing: XCUITest journey, events, matched-product variant pick (GLO-56 → the logging sheet). |
| `supabase/functions` | 5 functions, 49 deno tests, **none deployed** — secrets are §7. |
| The data path | `shelf · LIVE` signs in as maya and now round-trips `item_fits`. Everything else renders fixtures until screens adopt the live path. |

## 3. How this session worked (changes from last time)

Everything in the previous handoff's §3 held (branches, size limits + the
`size-override` label when tests justify it (#115), squash merges, stacked PRs
with retarget-then-restack, migration lock, apply-to-hosted-immediately).
Authorizations re-asked and granted **for this session only**: self-merge on
green, one DataKit opening (the variant field). Re-ask next session.

The loop that worked is unchanged: frame first (as source, via the browser
pane — `docs/DESIGN.md`), model first, view to the frame, picker states for
every state including failures, drive it on a simulator, restack before merge,
build `origin/main` after a stack lands.

## 4. Frozen or dangerous areas

Unchanged: `core/DataKit` (frozen; openings are per-session asks),
`supabase/migrations/` (one open migration PR, on a migration ticket, applied
to hosted right after merge), CI workflows (GLO-71 stays a human fix),
`ingest_jobs` claiming.

## 5. Review: what actually caught defects this session

- **Driving the failed-log picker state** found the category select holding
  its own `@State` copy of the pick and disagreeing with the model — invisible
  in the happy path, fixed by binding the select to the model. The shape
  repeats: *view-local copies of model state are where screens lie.*
- **Driving the form** found disabled `.glossed` buttons render identical to
  enabled (GLO-76). No assertion would catch either.
- **The LIVE round trip** proved fit persistence against real Postgres in
  four taps — including `just right`'s wholesale replace, which the DB
  enforces and the UI now demonstrably honors.
- The **exit-code-through-a-pipe** trap (§0) bit twice before being named.

## 6. Decisions made this session (by Sean, in-session)

| Decision | Answer | Consequence |
|---|---|---|
| Self-merge on green? | Yes, this session | Six PRs merged same-day; re-ask next session |
| Shelf search (GLO-73)? | Build it without a frame, workshop in review | Ticket unblocked |
| Frames for variant pick / lifecycle? | **"I won't be adding frames for it — build from the current design system"** | The frame-*blocked* pattern is over for missing frames. Check the kit first, record the absence, build with primitives in the kit's voice, expect PR iteration. Screens with frames still build to the frame exactly |
| GLO-75 migration + DataKit opening? | Yes, both | 0014 + `draft.variant`; merged and hosted |

## 7. Blocked on a human, not on code (unchanged list)

| Blocked thing | On what | Who |
|---|---|---|
| `storage_presign` deploy, catalog images, cutouts, GLO-74's real bytes | R2 buckets/token/CORS ([GLO-48](https://linear.app/glossed/issue/GLO-48)) | Cloudflare account holder |
| Function deploys (`track_ingest`, `feed_diff`, …) | `INGEST_SECRET`, `ANTHROPIC_API_KEY` secrets | Sean |
| Auth → onboarding → live-by-default | Sign in with Apple ([GLO-50](https://linear.app/glossed/issue/GLO-50)) | Apple Developer account holder |
| [GLO-71](https://linear.app/glossed/issue/GLO-71) CI scope fix | Workflow edit | Any human; agents barred |
| `feed_diff` against a real feed | Rakuten/Impact applications (long lead) | Account holder |

## 8. What past sessions got wrong, so you don't repeat it

Sessions one–three: see §0's traps, which preserve the durable ones (scope-job
skip, stacked-squash double-apply → build main after stacks, secrets squashed
out of history not deleted at HEAD, stale simulator binaries → terminate +
install + launch, fixtures nothing consumes are not known to work, never
background a task that switches branches).

**Session four additions:**

*`--delete-branch` on a stack parent closed the child PR* (§0). *Pipes ate
exit codes twice* (§0). *A view-local copy of model state lied on screen*
(§5). And the positive: **asking Sean four questions in two batches unblocked
three tickets and authorized six merges** — the ask-when-present rule keeps
paying.

## 9. Local setup

```bash
make setup && make dev
supabase test db          # 111 assertions
make functions-test       # 49 deno tests
```

Docker via colima. If the LIVE state fails sign-in: `supabase db reset` first
(§0). Launch with the key:
`SIMCTL_CHILD_SUPABASE_PUBLISHABLE_KEY=$(supabase status | jq -r .PUBLISHABLE_KEY)`
then `simctl launch` — no scheme editing needed.
