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
| [GLO-47](https://linear.app/glossed/issue/GLO-47) fit block persistence — **and wiring the sheet's fit section** | Both write paths exist whole (`captureFit(fits:)` → `capture_fit()`; `fits(itemID:)` reads back). The product page persists nothing; the item sheet's new fit section (#108) fires `onFitChanged` into a default no-op. Wire either against the LIVE picker state |
| [GLO-15](https://linear.app/glossed/issue/GLO-15) create rung | Buildable at last: `brands(matching:)` supplies the FK, `createPersonalProduct` returns a loggable `CreatedProduct`, `scannedGTIN` rides the draft |
| Event wiring | `core/Tracking` + `events` + `track_ingest` all exist and **nothing calls `track()` yet** — each feature wires its own events while its surface is fresh (the whole point of moving GLO-21 PR 1 forward) |
| [GLO-14](https://linear.app/glossed/issue/GLO-14) leftovers | All four PRs landed. What remains: the pg_cron schedule for nightly `feed_diff` (needs the deployed function, §7) and the Rakuten/Impact applications (human) |
| [GLO-63](https://linear.app/glossed/issue/GLO-63) item 3 | The near-match RPC with a *reason* — the valuable one. Migration slot free |
| [GLO-16](https://linear.app/glossed/issue/GLO-16) logging sheet | **Frame-blocked, not effort-blocked** — do not start it. The kit has no variant-pick UI anywhere (checked Aug 28 evening; every frame shows a product with its variant already resolved). Sean has to add the frame. The sheet's *anchor fit section* is already built (#107/#108) |
| [GLO-51](https://linear.app/glossed/issue/GLO-51) plural labels | Small, needs the frame open |

**Merged this session (do not re-do):** #82–#108, zero open at handoff time — the shelf chain (view,
`ShelfRow`, packaging table, mapping), the ladder server (`create_personal_product`,
widened `search_catalog`), multi-axis fit (#88/#90/#91), GTIN-14 both halves
(#95/#96), `core/Tracking` + `events` schema + `track_ingest` (#97/#98/#99),
the whole GLO-14 dedupe chain (#92/#93/#100/#101/#102) + `inci_enrich` (#105)
+ the weekly fill list (#104), the main-compile fix (#89), **the first live
read** (#103: debug sign-in + a `shelf · LIVE` picker state rendering the
seeded database end to end), and the item sheet's anchor fit section
(#107/#108: `is_anchor` on the row, `fits(itemID:)`, the section built to the
frame and driven, the picker close's third home). Tickets closed: GLO-66,
GLO-67, GLO-58, GLO-70. `origin/main` was rebuilt locally after the final
merge and compiles.

## 2. What exists

| Layer | State |
|---|---|
| Schema | **13 migrations**, all applied to hosted (manually via Supabase MCP after each merge). **108 pgTAP assertions.** Migration slot free. |
| `core/DataKit` | Frozen again. Session's authorized openings delivered: `ShelfRow`+`shelf()`, brands/RPC/`CatalogHit`, `captureFit(fits:)`+`fits(itemID:)`, `gtin14` matching, `signIn(email:password:)`, `is_anchor` on the row. 32 tests. |
| `core/DesignSystem` | + packaging table, multi-select `FitControl`. 38 tests. |
| `core/Tracking` | **Exists** (#97): the tech/06 registry as a compiler-checked enum + the drop-on-failure queue. 10 tests. **Nothing calls `track()` yet.** |
| `core/Media` | Still does not exist — R2 (§7). |
| `features/Shelf` | Screen + wire mapping + the sheet's anchor fit section. 46 tests. |
| `supabase/functions` | `storage_presign`, `feed_diff` (plans + writes), `track_ingest`, `dedupe_adjudicate` (claude-opus-5, ≤10 calls/run), `inci_enrich` (OBF, 12/run). **49 deno tests. None deployed** — secrets are §7. |
| The data path | **Live, drivable, and driven**: the `shelf · LIVE` picker state signs in as maya and renders Postgres through the whole chain. Everything else still renders fixtures until screens adopt the same path. |

The auth seed is now signable-in (#103): GoTrue rejects NULL token/timestamp
columns with "Database error querying schema", and email users need
`auth.identities` rows — both fixed in `seed.sql`, with maya given a starting
shelf on variants the pgTAP suites don't touch.

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

**Evening additions, same session:**

*The seeded users could never sign in, and nothing knew.* GoTrue scans
`auth.users` token/timestamp columns into non-nullable Go types; the seed's
NULLs failed every password grant with "Database error querying schema" —
which reads like a broken stack. Found the minute the first live sign-in was
attempted (#103), which is the deepest version of "run the thing": the seed
had been "working" since day one because nothing had ever exercised its
login path. **Rule: a fixture nothing consumes is not known to work.**

*A commit landed on the wrong branch* (Tracking onto the GLO-58 branch)
because a background CI-wait had checked out a different branch mid-flight.
**Rule: never background a task that switches branches while foreground work
continues in the same tree** — background only read-only waits. It happened a
second time the same evening (the picker fix edited on #103's branch): the
rule is real.

*Gitleaks scans the PR's whole commit range, not the tip.* #103 removed a
hardcoded key in a follow-up commit and still failed — the first commit
carried it. **Rule: a secret must be squashed out of the branch history, not
just deleted at HEAD.** (And do not teach the scanner the key is harmless —
a guard that has to know that stops being a guard.)

*A rebuilt .app does not reach a running simulator by itself.* Twenty minutes
were spent driving a stale binary that still showed the fixed bug. **Rule:
after rebuilding, `simctl terminate` + `install` + `launch`, and when a fix
refuses to appear, md5 the installed binary against the built one before
doubting the fix.**

*The frame check prevented a GLO-62 repeat.* GLO-16's logging sheet was next
by every plan, and reading the kit first showed **no variant-pick frame
exists anywhere** — the pick the GLO-56 decision assigned to that sheet has
never been designed. Stopped and flagged instead of inventing UI from
primitives. **Rule: "open the frame first" applies to whether the frame
exists at all.**

## 9. Local setup (unchanged)

```bash
make setup && make dev
supabase test db          # 85 assertions
make functions-test       # 29 deno tests
```

Docker via colima. The corrupted-layer gotcha from last session stands:
`docker system prune -a -f --volumes`, not another pull.
