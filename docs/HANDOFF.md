# Session handoff — Aug 28 2026 (third session)

Where Phase 1 stands, what to do next, and the decisions a new session would
otherwise have to rediscover. Read `docs/README.md` first for the design; this
file is only about state.

## 0. Two silent failures to know before anything else

**CI's scope job can skip every real check and stay green
([GLO-71](https://linear.app/glossed/issue/GLO-71)).** The scope step fetches
the PR's base with `--depth=1`, which shallows the ref; if the base has
advanced *at all* since the branch was cut, `git diff BASE...HEAD` dies with
`no merge base`, the failure is indistinguishable from "no changes", and the
macOS build, db suite, and deno suite are all skipped — five green checks, no
build ran. Seen live on #91. Until a human fixes the workflow (agents may not):
**a skipped `build · test (iOS)` on a Swift PR is unproven, not green** —
rebase onto the base's exact tip and re-push before trusting checks.

**Stacked squash-merges can double-apply a hunk without a conflict.** #84 and
#85 both descended from the same pre-#84 merge-base; the squash of #85
re-applied `ShelfRow` into a main that already had it. `main` did not compile
and nothing said so, because CI deliberately does not re-run on push to main.
Fixed in #89. The guard: after merging a stack, `swift build` against
`origin/main` — or restack each child on the parent's squash before merging it.

The design-frame access route in §0 of the previous handoff still works and is
unchanged — see [`docs/DESIGN.md`](DESIGN.md) for opening `screens.jsx` as
source. If you cannot open the frame, stop and say so.

## 1. Where to start

Tracked in **Linear**: workspace [glossed](https://linear.app/glossed), team
**GLO**, project **GLOSSED — Phase 1: The Journal**.

| Next | Why |
|---|---|
| [GLO-14](https://linear.app/glossed/issue/GLO-14) PR 2 — dedupe adjudication | **The open lane.** PR 1 (#92, #93) landed: `feed_diff` plans every row and applies GTIN updates/delistings, but `queue_candidate` and `insert_product` deliberately write nothing until the adjudicator defines what a `merge_candidates` row means. Claude API work ⇒ `read-the-damn-docs` first, spend caps per the ticket |
| [GLO-16](https://linear.app/glossed/issue/GLO-16) logging sheet | **Unblocked by two decisions this session** (§6): the sheet owns the shade/size pick (GLO-56 decided), preselecting a single variant but always confirming; fit capture is multi-axis via `captureFit(itemID:fits:)` once #90/#91 merge |
| [GLO-47](https://linear.app/glossed/issue/GLO-47) fit block persistence | The write path exists end-to-end after #88/#90/#91: multi-select `FitControl` → `captureFit` → `capture_fit()` RPC. The page still persists nothing |
| Wiring screens to live data | The whole chain exists (`user_shelf_items` → `ShelfRepository.shelf()` → `ShelfItem(row:)`) but **no screen calls it**, because nothing can sign in — a debug-only password sign-in against the local seed would unblock driving real data ([GLO-23](https://linear.app/glossed/issue/GLO-23) is the real auth, still gated on GLO-50) |
| [GLO-58](https://linear.app/glossed/issue/GLO-58) GTIN-14 migration | Small, independent, migration slot free after #88. `feed_diff` already compares at 14 digits; the scan path still does not |
| [GLO-70](https://linear.app/glossed/issue/GLO-70) "rated it" copy · [GLO-51](https://linear.app/glossed/issue/GLO-51) plural labels | One-liners, but each needs the frame read first |

**Merged this session (do not re-do):** #82 `user_shelf_items` view ·
#83 `create_personal_product` + widened `search_catalog` · #84 `ShelfRow` +
`shelf()` · #85 brands/RPC/`CatalogHit` widening · #86 packaging table →
DesignSystem · #87 `ShelfItem(row:)` mapping · #88 multi-axis `item_fits` +
`capture_fit()` · #89 the main-compile fix · #92 `feed_diff` planner.
Open at handoff time: #90 (captureFit set), #91 (multi-select FitControl),
#93 (`feed_diff` handler) — all green-or-pending, merge on green.

## 2. What exists

| Layer | State |
|---|---|
| Schema | **9 migrations**, all applied to the hosted project (manually via Supabase MCP after each merge). **85 pgTAP assertions.** Migration slot free. |
| `core/DataKit` | Still frozen by default. **Opened this session with explicit authorization** for GLO-66/60/63/67; that authorization was session-scoped and does not carry forward. 29 tests (30 after #90). |
| `core/DesignSystem` | + `ProductMock.Kind.usual(forCategory:)` (one packaging table for all features), multi-select `FitControl` in #91. 33 tests (38 after #91). |
| `core/Media`, `core/Tracking` | **Still do not exist.** Media needs R2 (§7); Tracking is GLO-21 PR 1 and still needed by everything. |
| `features/Shelf` | Screen + **the wire mapping** (`ShelfItem(row:)`, `ShelfSection.grouped(from:)`). 45 tests. |
| `features/*` others | Unchanged from last session (AddLadder 78, Ranking 29, ProductPage 11, Import 12). |
| `supabase/functions` | `storage_presign` (not deployed, §7) + **`feed_diff`** (planner merged, handler in #93). 29 deno tests. Not deployed — needs `INGEST_SECRET` and a pg_cron schedule (a later PR). |
| The data path | `user_items → user_shelf_items → ShelfRow → ShelfItem` exists end to end and is tested at every joint. **No screen reads it yet** — the app has no way to sign in, so every screen still renders from the debug picker's fixtures. That is the honest sentence about this codebase: the seam is closed in code and open at runtime. |

## 3. How this session worked (changes from last time)

Everything in the previous handoff's §3 held (branches, ≤5 files/400 lines,
squash merges, stacked PRs with retarget-before-merge, migration lock,
self-merge on green **authorized for this session specifically**). New:

- **Human decisions can be asked for in-session.** Three questions
  (DataKit opening, GLO-56, GLO-67) were put to Sean directly and answered in
  minutes. Flag-and-route-around is for when nobody is at the keyboard.
- **Restack children onto the parent's squash before merging them** — see §0's
  second failure. Retargeting the base is necessary but not sufficient.
- **After any retarget or force-push, confirm the iOS check *ran*** — see §0's
  first failure.
- The migration slot was used three times serially (#82 → #83 → #88), each
  applied to hosted immediately after merge.

### The loop that worked (unchanged, plus one step)

1–7 as in the previous handoff (open the frame; read it against schema and
core *before* writing; model first; view to the frame's numbers; drive it on a
simulator; add picker states; name the frame in the PR). Plus:

8. After merging anything stacked, build `origin/main` locally before starting
   the next thing.

## 4. Frozen or dangerous areas

- `core/DataKit` — frozen again now the authorized opening is done. The
  reasoning is unchanged: it is the one path every query takes, and a missing
  session check there is a data leak, not a bug.
- `supabase/migrations/` — one open migration PR project-wide; apply to hosted
  right after merge or the environments drift.
- CI workflows, lint configs — agents may not modify them, **including to fix
  GLO-71**; it is written up for a human.
- `ingest_jobs` claiming: the state-filtered UPDATE in `feed_diff` is the
  concurrency lock. Do not "improve" it into a select-then-update.

## 5. Review: what actually caught defects this session

The recap is still manual (`gh workflow run visual-recap -f pr=<n>`) and was
not used this session; you are the review. What worked:

- **Testing against the platform decoder, not a hand-configured one**, found
  that `UserItem.startedOn` could never decode — Postgres `date` columns throw
  in supabase-swift's timestamp-only decoder, and the old test passed because
  it used its own `JSONDecoder`. Fixed in #84 (`PostgresDay`). The shape:
  *a test that configures its own environment proves the test, not the code.*
- **Building `origin/main` after a stack merge** found the double-applied
  `ShelfRow` (§0).
- **Driving the screen** verified all four multi-axis fit rules (both axes
  lit, axis-swap, `just right` exclusive, honest meter) and found GLO-70's
  "rated it" copy — a defect no assertion would catch, again.
- **`swift-testing` traps**: a `static` on a SwiftUI `View` is main-actor by
  conformance; the first test calling `FitControl.picked` killed the whole
  test process with signal 5, every test "started", none reported. If a suite
  dies with all tests started and none passed, run `--no-parallel` and look at
  the first unfinished test. `nonisolated` is the fix for pure helpers
  (the `ShelfModel.ordered` precedent).

## 6. Decisions made this session (by Sean, in-session)

| Decision | Answer | Consequence |
|---|---|---|
| Open frozen DataKit? | Yes — once, bundled | #84/#85/#90 exist; core is frozen again |
| [GLO-56](https://linear.app/glossed/issue/GLO-56) shade/size pick owner | **The logging sheet** (GLO-16) | Ladder gets no pick rung; search/near-match/import all hand a `productID` to the sheet; barcode skips it; single-variant products preselect but still confirm |
| [GLO-67](https://linear.app/glossed/issue/GLO-67) fit axes | **The kit wins — multi-axis** | #88 (schema) merged, #90/#91 (DataKit, control) open; `user_shade_anchor` now carries one bound per axis |

## 7. Blocked on a human, not on code (unchanged)

| Blocked thing | On what | Who |
|---|---|---|
| `storage_presign` deploy, catalog images, cutouts | R2 buckets/token/CORS ([GLO-48](https://linear.app/glossed/issue/GLO-48)) | Cloudflare account holder |
| Auth → onboarding → any live-data screen | Sign in with Apple on the App ID ([GLO-50](https://linear.app/glossed/issue/GLO-50)) | Apple Developer account holder |
| [GLO-71](https://linear.app/glossed/issue/GLO-71) CI scope fix | Workflow edit | Any human; agents are barred |
| `feed_diff` against a real feed | Rakuten/Impact publisher approval (long lead — **start the applications**) | Account holder |

## 8. What past sessions got wrong, so you don't repeat it

**Sessions one and two** — see the entries preserved below; the shapes still
recur.

*Session one:* acted on assumptions without checking or declaring them — built
to primitives when the frames were reachable (→ GLO-62); `git push -q` hid a
failed push; planned three times against a core that could not supply the data
(→ GLO-60). *Session two:* fixed a bug that was not there (eyeball-measured a
pixel drift); used one number in two places, twice.

**Session three (this one):**

*A stacked squash double-applied a hunk and broke main silently.* The two PRs
shared a pre-stack merge-base. CI's no-rerun-on-main policy made it invisible;
the next branch build found it. **Rule: a child PR is restacked on its
parent's squash before it merges, and `origin/main` gets built after any stack
lands.**

*Five green checks, no build.* The scope job's shallow fetch turned "the base
moved" into "no changes" (§0, GLO-71). **Rule: a skipped check is not a passed
check — read which jobs ran, not the color.**

*A green test was testing its own decoder.* `startedOn` had never once decoded
off the wire, and the unit test could not see it because it built its own
`JSONDecoder`. **Rule: decode-shape tests use the SDK's decoder, verbatim.**

*The kit's copy and the repo's vocabulary disagree on one screen* ("rated it"
vs reports, GLO-70) — found only by looking. The screen-driving rule keeps
earning its place.

What went right and is worth copying: asking the human the three questions
instead of routing around all of them — GLO-56 and GLO-67 had been "flag and
wait" for two sessions and each took one message to settle.

## 9. Local setup (unchanged)

```bash
make setup && make dev
supabase test db          # 85 assertions
make functions-test       # 29 deno tests
```

Docker via colima. The corrupted-layer gotcha from last session stands:
`docker system prune -a -f --volumes`, not another pull.
