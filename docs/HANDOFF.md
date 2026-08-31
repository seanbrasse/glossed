# Session handoff — Aug 30–31 2026 (session 15: the profile was rebuilt twice, an RLS leak shipped and was caught, and merging green PRs turned `main` red)

Where Phase 1 stands, what to do next, and what this session learned. Read
`docs/README.md` first for the design; this file is only about state.

**Session 15 ran as a coordinator plus up to seven concurrent worktree lanes.**
That shape is why several entries below are about *coordination* failures rather
than code: the expensive mistakes were at the seams between lanes, not inside
them.

## Session 15 at a glance (Aug 30–31)

**36 PRs merged** into `main` since the last handoff commit (`8a8f2c1`) — counted,
not estimated. Highlights, in rough order of how much they matter:

| What | Where |
|---|---|
| **An RLS leak shipped and was caught.** `RoutinesRepository.mine()` returned *other people's* routines | #376 shipped it, #387 fixed it, GLO-258 carries the rest |
| The **catalog snapshot became durable** — off-worktree, rotated, auto-refreshing, and proven against a real reset | #370 |
| **Every seeded user could finally pass the age gate** — `profiles` was empty, so all of Phase 1.5 was silently locked | #373 (GLO-182) |
| The **+ drawer** got its cards, its kit glyphs, a fifth door, and its scrim stopped wiping the screen | #377 #384 #386 #396 #400 |
| **FLOW 1 became an actual flow** — the tour was orphaned, the returning path could not terminate, and the payoff cited a shade the user never picked | #382 #383 |
| **The face-off became reachable** for the first time since GLO-17 | #375 #381 |
| **DataKit opened once, and is spent**: routines, collections, looks reads + `publish()` | #376 #387 #391 |
| Migration **0048** — publishing a look is the owner's decision, deliberate and unmoderated pending GLO-26 | #378 |
| The **profile redesign** (GLO-261) — Sean's Instagram/Pinterest direction, mid-merge at handoff | #403 #406 #407 merged; **#408–#411 open** |

---

## 0. Read this first

**Four things, all of which cost real time this session and none of which are
visible in the code.**

### `main` runs no CI, and a limit can be broken by a *merge* rather than a commit

`AppShell.swift` went to **301 lines** — one over SwiftLint's `file_length`
ceiling — because #400 and #394 each passed the gate **against their own base**,
minutes apart. The ceiling is measured **per file, not per diff**. `main` has no
CI run of its own, so nothing caught it; the failure surfaced on an unrelated
profile PR that went red on a file it does not touch. Fixed in #401 by extracting
`ladderFlow` to `AppShellLadder.swift`.

**Two green PRs can merge into a red `main`.** If a PR fails lint on a file it
did not modify, check `main` before debugging the PR.

### RLS SELECT policies are OR'd, so RLS never makes a query "mine"

Ten tables carry an `*_own` + `*_public` pair of **PERMISSIVE** policies. Postgres
ORs them. So an unfiltered `select` returns your rows **plus** every row the
public predicate admits.

`RoutinesRepository.mine()` shipped in #376 doing exactly that. Reproduced:

```
as maya:  select … from routines where deleted_at is null
  → JULI PM RESET        ← not hers
  → morning glass skin
with `and user_id = auth.uid()` → only maya's
```

The tell was in the code the whole time: it called
`_ = try await client.requireUserID()` — **fetched the user id and threw it
away.** Its doc comment claimed the call was "scoped by `routines_own` to
`auth.uid()`", which was false in exactly the way GLO-238's comment was false.

**Any `mine()`-shaped read must pin `user_id` in the query.** Seven of the ten
tables are still unaudited — **GLO-258**. A Swift test cannot see a policy; pgTAP
is the only instrument that can, which is how this survived review.

### Squash-merging a stack silently inflates every PR below it

Merging #406 and #407 rebased the two branches immediately downstream, but
#409–#411 still descended from the **pre-squash** commits. **#409's diff grew from
7 files / 426 lines to 13 / 1956** — replaying history `main` already contained.
Its `size-override` reason silently stopped describing its diff. Nothing warns you.

**After squash-merging any PR in a stack, re-check the sizes of everything below
it** before trusting a label or a review.

### The `lint · format · size · secrets` job fails for at least three different
reasons, and they all look identical

Encountered all three in one session:

| Actual cause | What the check says |
|---|---|
| **PR size gate** (>5 files or >400 lines, no `size-override`) | a lint failure |
| **A genuine SwiftFormat/SwiftLint violation** | a lint failure |
| **A network flake** — `curl` has no `--fail`, so a throttled GitHub response is written into `sf.zip` and `unzip` dies | a lint failure |

**Read the log every time.** Three wrong diagnoses were made this session by
assuming which one it was — including two of the coordinator's own. The `curl`
and the unpinned-on-both-sides SwiftFormat are **GLO-237**.

---

## 1. Where to start

Tracked in **Linear**: workspace [glossed](https://linear.app/glossed), team
**GLO**, project **GLOSSED — Phase 1: The Journal**.

### In flight at handoff — check these before starting anything new

| Thing | State |
|---|---|
| **The GLO-261 profile stack, #408–#411** | Open, all four `MERGEABLE`, lint+scope green, **iOS builds pending**. A background merge chain was rebasing and merging them one at a time; **verify whether it finished** — `gh pr list` is the answer, not this file. Each needs a rebase onto `main` after the one before it merges (see §0 on squash-inflation) |
| **Schema lane — GLO-266, GLO-263, GLO-265** | Holds the **migration slot**. Three sequential migrations: the look-tag reshape, look→routine/collection links, routine cadence. Unknown completion at handoff |
| **Look-tagging UI lane — GLO-266** | Building the tag model + compose interaction against seams. Unknown completion at handoff |
| **#402** — `make test` runs nothing | Open. `project.yml` declares `schemes: Glossed: test: targets: []`, so `xcodebuild test -scheme Glossed` errors outright. **CI never used `make test`** — it runs `xcodebuild build` plus `swift test` per package |

### The profile was redesigned mid-session — do not build to the old frame

Sean rejected the merged profile after driving it and specified an
Instagram/Pinterest shape: identity block, three metrics, four content tabs
(**looks default**), a `+` in the empty state. **`add a look`, `what a stranger
sees` and `where else you are` are deleted.** Full direction and reasoning:
**GLO-261**.

The load-bearing idea, because it is easy to get wrong: Sean's argument is that a
stranger-preview is redundant *because your profile already is what a stranger
sees*. That does **not** follow automatically — Instagram has one account-level
switch and GLOSSED has **four per-surface scopes**, so your own profile must show
private things a stranger cannot. **The scope mark on each tab** is what earns
the right to delete the preview. This deliberately reverses **GLO-190**.

### Next, once the above lands

| Next | Why |
|---|---|
| **The app-layer seam for the profile** | `looksStore`, `collectionsStore`, `routinesStore`, `shelfStore`, `scopesStore`, `onCompose`, `handleStore` are **unwired**. Until one small PR lands, the redesigned profile renders its identity block and **nothing below it**. This is GLO-261's last PR |
| **GLO-260** — the discover eyebrow is merged but dark | `AppSession.swift:96` needs one argument: `catalog: CatalogRepository(client: client)`. `main` carries a correct, tested, **invisible** feature |
| **GLO-258** — seven unaudited tables | The RLS OR leak. Needs pgTAP, therefore the migration slot |
| **GLO-239** — the profile does not refresh after a handle claim | Diagnosed, not fixed: the *shell* presents the claim sheet, so dismissing it never re-runs `OwnProfileView`'s `.task`. **The fix may have landed for free** in the redesign — verify rather than assume |
| **GLO-224** — does Discover own a search field? | Needs Sean. Three costed answers on the ticket. An honest placeholder (`brand, product, shade…`) already shipped; the IA question did not |
| **GLO-227** — discover chips | Blocked on a DataKit opening. Option B (`topChips(productIDs:)`) recommended — no migration, serves every product-card surface |

---

## 2. What exists

Test counts below were **run at handoff**, not recalled:

| Package | Tests | State |
|---|---|---|
| `core/DataKit` | **125** | The frozen core. One opening this session, **spent** (routines, collections, looks) |
| `core/DesignSystem` | **54** | `KitIcons` now carries the drawer's four glyphs + a pencil. GLO-64 is still open elsewhere |
| `features/Profile` | **84** | Mid-rebuild — see §1 |
| `features/Discover` | **35** | The stream. Category eyebrow merged but **dark** (GLO-260) |
| `features/Looks` | **24** | Composer, reorder, media deck. **No app entry point until the drawer's fifth door merged** |
| `features/Collections` | **3** | Package + `CollectionsStore` seam only. **Nothing joins it to `CollectionsRepository`** — see GLO-21 |
| `features/Onboarding` | — | FLOW 1 is now a real flow (#383); **unreachable until the app layer mounts it** (GLO-245) |

**The sentence that is true about all of it:** *a merged feature is not a
reachable one.* This session merged a category eyebrow that renders nothing, an
onboarding flow with no caller, a collections package with no adapter, and a
face-off that was built in GLO-17 and had never once rendered in the app. **Before
building anything new, check whether the thing it depends on is wired** —
`grep -rn "import <Package>" app/` is the two-second version.

**Local stack:** migration head `20260830000048`, `products` = **3,206**,
`variants` = 9,019, `brands` = 497. Catalog snapshot store at `~/.glossed/catalog`
(5 generations). **60 GB free** — see §8 on the night the disk hit zero.

**Canon simulator changed.** The old UDID in previous handoffs is **dead** — the
device set was rebuilt when the disk filled. It is now **iPhone 16 Pro,
`0A658108-11CB-40AD-BC2B-1B140CDFB192`, iOS 26.5**. Launch with the env vars or
you get a config-missing screen:

```bash
SIMCTL_CHILD_SUPABASE_URL="http://127.0.0.1:54321" \
SIMCTL_CHILD_SUPABASE_PUBLISHABLE_KEY="$(supabase status -o json | jq -r .PUBLISHABLE_KEY)" \
xcrun simctl launch <UDID> com.glossed.app
```

**Live fixtures worth keeping:** maya owns `morning glass skin` (am, 2 steps) and
four collections; **juli holds a public routine and a public collection**. That
second one exists so an isolation assertion means something — a profile that
renders correctly against a database where nobody else owns anything proves
nothing, which is exactly how GLO-258's leak survived review.

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

Standing: `supabase test db` runs against the **live local DB** — there is no
shadow database, only `postgres`. So a red can still be drive-drift from
seeded rows someone's drive mutated. Check row timestamps and `is_seeded`
before resetting; **ping the other session before you reset**, and budget the
restore (§9, seven scripts, ~50 min). Current baseline: **567 assertions / 1
known LOCAL failure (`shelf_view` 14; CI is zero)** — the taste lane's count
after 0042's suite landed, and the number §2 carries. The journal lane did not
re-run it.

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
test pass per hour.** Across two sessions it has produced eleven findings, nine
of them merged fixes. Aug 30 alone filed five and closed four, every one
invisible to the suite: a field that deleted itself on the first keystroke, an
instruction to check photographs that were drawings, a source card promising a
capability the app does not have, a "try again" with nothing to press, and the
discovery that **the harness itself could not reach the bug class it was built
for** — no fixture hosted `LadderFlowView`, so no rung-to-rung transition was
drivable at all, which is exactly GLO-96's shape. Every one was invisible to the automated suite, because they are
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
| The sweep is 34 cells in; the named cells are done and what remains is two axes — Dynamic Type everywhere but the shelf, and the ladder's remaining transitions | [GLO-110](https://linear.app/glossed/issue/GLO-110) / [docs/ux-state-sweep.md](docs/ux-state-sweep.md) |
| Import's `screenshot of a haul` promises text extraction that does not exist, and the editor has no visible placeholder while carrying an accessibility one | [GLO-178](https://linear.app/glossed/issue/GLO-178) → [GLO-19](https://linear.app/glossed/issue/GLO-19) |
| The shelf is unusable at accessibility text sizes; three candidate fixes written, none picked | [GLO-172](https://linear.app/glossed/issue/GLO-172) |
| Chips render alphabetically, so likes and dislikes interleave — a feel question for Sean | [GLO-156](https://linear.app/glossed/issue/GLO-156) |
| The Fit ↔ FitAnswer mapping is duplicated in two features with no legal shared home | [GLO-164](https://linear.app/glossed/issue/GLO-164) |
| Applying DDL by direct psql does not stamp `schema_migrations`; two lanes did it independently on Aug 29 and the gap read as an eleven-migration deficit | §0 |
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
| A browse TAB: trending + routines-browse are "what other people do", discover is "what fits you" — a real seam, and the kit's nav is three tabs + plus | parked with Sean (GLO-20 thread) |
| ~~`features/Leaderboard` + the product page's dead `onLeaderboard`~~ — **closed**, #293/#294/#297 | [GLO-20](https://linear.app/glossed/issue/GLO-20) / §1 |
| GLO-21 routines: create done (#341/#342). Left: collections composer, rename/delete (framed in `G.Profile` — open it), and wiring the + drawer's two options | [GLO-21](https://linear.app/glossed/issue/GLO-21) / §1 |
| The four routine slots wear two sets of words — composer `am / pm`, `DataKit.RoutineSlot` `morning / evening`. The kit's drawer says `am / pm`, so DataKit holds the wrong ones, which makes the fix an **opening** question | [GLO-210](https://linear.app/glossed/issue/GLO-210) / [GLO-164](https://linear.app/glossed/issue/GLO-164) |
| GLO-204's remaining half (name + bio editor) is one moderation decision away from buildable | [GLO-204](https://linear.app/glossed/issue/GLO-204) / §7 |
| Hair-type privacy: profile badges must never name a body fact — ruling filed off the tune-card work, db half in [#331](https://github.com/seanbrasse/glossed/pull/331) (another lane's, open at handoff) | [GLO-205](https://linear.app/glossed/issue/GLO-205) |
| The tour has no real-entry trigger — it mounts from the debug door; wiring it to first-launch is part of GLO-23's entry work | [GLO-23](https://linear.app/glossed/issue/GLO-23) |
| The scoped ConfidenceMeter in G.Leaderboard has no defined live data source — deferred, not decorated | GLO-20 / §1 |
| Save/wishlist (+0.5) needs the want_to_try-as-intent ruling before code | tech/07 §2 / §1 |
| Un-dismiss management UI (the row is deletable by construction; no surface offers it yet) | [GLO-181](https://linear.app/glossed/issue/GLO-181) note |

## 7. Blocked on a human, not on code

**Answered this session — left in for one cycle so nobody re-asks:**

| Was blocked | Sean's ruling (Aug 30–31) |
|---|---|
| [GLO-220](https://linear.app/glossed/issue/GLO-220) carousels — whose n | **"Headline only."** The n is a fact about the row, stated once above it; items keep their own evidence. No pinned header, no per-item repeat |
| [GLO-220](https://linear.app/glossed/issue/GLO-220) — can a carousel be editorial | **"Yes, but it must still cite people."** Editorial picks the *question*; the row is filled by query so the n is real. **Slot shape (one slot or several) was never answered** — build proceeded on one-slot and said so |
| GLO-204's `avatar_seed` | **Answered by the frame, not by Sean.** The kit's avatar takes `{name, tone, skinType}` and **no seed exists anywhere in the kit**, so the column is dead. Do not build a picker. The real gap is a *tone* source — [GLO-231](https://linear.app/glossed/issue/GLO-231) |
| A DataKit opening for routines / collections / looks | **Granted, used, and SPENT** — #376, #387, #391. Do not treat it as standing |
| Looks: publish before moderation? | **"Build it, make them publishable, let's deal with moderation after."** Shipped as 0048; unmoderated **by decision**, pending GLO-26, which remains a launch gate under delta 11 |
| Where looks are created | **"add a product, import a list, new collection, routine, post a look"** — a fifth drawer door **and** a profile entry. Overrules the map's *"posting a look is not V1"*, which predates delta 11 |
| Video in looks | **Deferred** — *"maybe we leave video for a v2? Beyond phase 2."* [GLO-234](https://linear.app/glossed/issue/GLO-234) dropped to Low with his sub-rulings recorded (15s cap; audio kept, muted by default, sticky across cards) |
| Settings shape | **Grouped categories the user taps into**, and the **birthday is read-only** — no affordance, not a disabled field. [GLO-257](https://linear.app/glossed/issue/GLO-257) |

**Still blocked, and an agent must not spin on these:**

| Blocked thing | On what | Who |
|---|---|---|
| [GLO-262](https://linear.app/glossed/issue/GLO-262) profile views | **Which of three shapes, or none.** Aggregate-only, identified-and-visible, or identified-owner-only. It is a privacy decision before a schema one — an identified viewer log would be **the first surveillance surface in the app**. Recommendation on the ticket: aggregate-only or not in V1 | Sean |
| [GLO-266](https://linear.app/glossed/issue/GLO-266) tag search scope | His own open question: shelf, whole catalog, or catalog-with-shelf-first. **Recommendation: catalog-wide, shelf ranked first** — GLO-196 makes a look attributed content, never a claim, so an evidence rule should not gate a tag. Built so the scope is one injected query | Sean |
| [GLO-224](https://linear.app/glossed/issue/GLO-224) discover search | Does discover own a search field, or does search stay behind the `+`? Three costed answers on the ticket. The honesty half already shipped (`brand, product, shade…`); **do not ship the frame's `vibe search:` placeholder over name/brand FTS** | Sean |
| [GLO-265](https://linear.app/glossed/issue/GLO-265) cadence | Not the schema — **what cadence is *for*.** Nothing reads `slot` to remind or schedule. If it is a label, keep it a label; a scheduling field nothing schedules grows a notification system nobody asked for | Sean |
| [GLO-227](https://linear.app/glossed/issue/GLO-227) discover chips | A DataKit opening. Option B recommended (`topChips(productIDs:)`) — no migration, serves every product-card surface | Sean |
| [GLO-237](https://linear.app/glossed/issue/GLO-237) CI | `.github/workflows/` is frozen to agents. Two-line fix: `curl --fail --retry` **and** pin SwiftFormat on **both** sides — the Brewfile pins nothing either, so both float independently | Sean |
| [GLO-218](https://linear.app/glossed/issue/GLO-218) | Two rulings: one routine per look or many, and may it credit **someone else's**? If yes the link needs its own `can_view` check **or a private routine leaks through a public look** — [GLO-263](https://linear.app/glossed/issue/GLO-263) carries the trap | Sean |
| Any further DataKit opening | Per-session. The Aug 30–31 opening is **spent** | Sean |
| Any migration slot | Per-migration. Held by the schema lane at handoff for GLO-266/263/265 | Sean |
| [GLO-172](https://linear.app/glossed/issue/GLO-172), [GLO-156](https://linear.app/glossed/issue/GLO-156), [GLO-178](https://linear.app/glossed/issue/GLO-178) | Design calls, unchanged. Render both options and let him pick rather than re-deriving them | Sean |
| GLO-23 Apple + phone auth | Sign in with Apple capability + Twilio secrets are keyboard-minutes; every account screen already runs against the stub | Sean |
| The hosted project | Still needs a DB password, service-role key, or CLI login. **Hosted is at 46 migrations and lacks `0043` (looks) and `0047` (handles)** — probed, not assumed | Sean |
| Landing page → Rakuten / Impact / Beauty API | Unchanged: Vercel project creation 403s on team role; the signups need the channel URL | Sean |
| GLO-85 queue consumer | `ANTHROPIC_API_KEY` **and** Sean's direct word | Sean |
| The browse-tab IA question | Whether trending + routines browse earn a fourth tab. The kit does not answer it, and **its FLOW 2 caption is falsified by delta 11** | Sean |
| Save/wishlist mapping | Whether `want_to_try` IS tech/07's +0.5 save signal | Sean |

## 8. What went wrong, so you don't repeat it

### Session 15 (Aug 30–31) — coordination failures, mostly

The lanes did good work. **Almost everything that went wrong happened at the
seams between them, or in the coordinator.** Recorded as shapes, with the
incident that makes each believable.

**A comment asserting a security guarantee is worse than no comment.** Twice in
one session, verbatim: `LooksRepository` claimed *"no client write can perform
it (RLS: `state` is not client-settable)"* — RLS did no such thing;
`RoutinesRepository.mine()` claimed it was *"scoped by `routines_own` to
`auth.uid()`"* — it was not. Both survived review **because the comment was
read instead of the predicate.** *Shape: when a comment states a guarantee, go
read the thing that supposedly enforces it, or delete the claim.*

**"It passed CI" is not "it is scoped."** A Swift test cannot see an RLS policy.
Ten tables carry OR'd `*_own` + `*_public` policies and a Swift suite will pass
against all of them while leaking. *Shape: privacy properties need pgTAP; a
green package suite is silent about them.*

**An isolation test against an empty database is a ceremony.** A lane nearly
asserted "juli's rows don't appear" against rows that were `only_you` — RLS
alone would have hidden them, so the test would have passed while proving
nothing. It made the fixture genuinely public *first*, then asserted. *Shape:
before trusting a negative assertion, confirm the thing you are excluding would
otherwise be visible.*

**Three wrong diagnoses, all the same shape: a plausible story acted on before
the evidence was opened.** (1) The coordinator's own theory of the "jumpy"
drawer — an opacity fade doubling with a move — was **wrong on mechanism**; an
explicit `.transition()` *replaces* the default, so there was no fade; the scrim
was **translating**. (2) A lane blamed a SwiftFormat version drift for a red
check, posted it as a PR comment, and pushed a commit on it — the log then
showed the binary never downloaded. (3) `tech/03` §2 was cited as calling the
Feed frame "stale"; the word does not appear in that file, which says the
opposite. *Shape: motion gets diagnosed from a recording; CI gets diagnosed from
the log; a citation gets diagnosed by opening the line.*

**Two staleness claims, wrong in opposite directions, in one session.**
`G.Profile` was called current because no superseding delta was found — it is
classed a **stale frame** by `tech/02` §8. `G.Feed` was called stale on a note
that says the reverse. Both came from a summary rather than the cited line, and
each would have cost real work: one shipping false copy, one reinventing a
treatment the kit had already drawn. *Shape: a frame's status is a claim like
any other. Quote the line.*

**The coordinator broke `main` by merging two green PRs.** See §0. *Shape: gates
that measure per-file cannot be satisfied per-diff.*

**A stale ticket blocked a lane for no reason.** GLO-238 was filed saying
"revoke the owner's ability to publish"; Sean ruled the opposite hours later;
the ticket was left Urgent and contradicting the brief. A lane hit both and
correctly stopped. *Shape: when a ruling overturns a ticket, re-scope the ticket
in the same breath — an agent cannot tell a stale Urgent from a live one.*

**Seams fall between lanes and nobody owns them.** Three times: the collections
adapter (repository built, package built, nothing joining them), the discover
eyebrow (merged, dark, one argument missing), the onboarding flow (built,
uncallable). Each surfaced only because a lane mentioned it in passing. *Shape:
when you fence lanes by directory, the wiring between two directories belongs to
nobody by default — assign it explicitly or it will not exist.*

**A local dev key is still a key as far as the scanner is concerned — and the
previous handoff already knew that.** This session's first draft pasted the
literal `sb_publishable_…` value into §2's launch snippet; gitleaks failed the
docs PR. §9 had carried `<from supabase status>` for sessions precisely to avoid
it. *Shape: when you add an example command, copy the placeholder convention
already in the file rather than the value from your shell history.*

**The disk hit zero bytes and took down seven lanes at once.** 55 SwiftPM
`.build` directories across seven worktrees = **26.7 GB**, plus 2.9 GB of
DerivedData. Every tool failed, including the ones needed to diagnose it. It
also unmounted the iOS runtime and destroyed the simulator device set, so the
canon UDID in the previous handoff is dead. *Shape: N parallel worktrees cost
N full build trees; budget for it, and clean up per lane rather than at the end.*
The catalog survived because #370's snapshot store had landed **hours earlier** —
the one time tonight that insurance was bought before it was needed.

**A background script that dies looks exactly like one that is running.** The
coordinator's merge chain failed on line 6 (`declare -A` needs bash 4; macOS
ships 3.2), and was reported to Sean as "running unattended" for twenty minutes.
*Shape: check a background job's output before reporting its status, not just
that you launched it.*

**Squash-merging a stack silently inflates the PRs below it.** See §0.


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
announces itself. **That remedy was wrong, and it failed within the hour.** A
MISSING branch catches a package that was *deleted*; what actually kept
happening was packages being *added* — Privacy, then Discover, then Profile,
three in about an hour, taking the count 8 → 9 → 11 and the totals 438 → 453
→ 469. No hardcoded list can notice a package that did not exist when the list
was written. **The fix is discovery, not enumeration**: §9's loop now globs
`core/*/` and `features/*/` and tests anything with a `Package.swift`. The
general shape — *when a list keeps going stale, stop maintaining the list and
derive it* — is worth more than either count.

*And the stale `.build` scar recurred, now with a nameable trigger.* Four
packages "failed to compile" against main with `cannot find type
'DiscoverHit' in scope` — a type that plainly exists in `DataKit/Discover.swift`.
DataKit's own tests passed at the same moment, which is the tell. `rm -rf
.build` in the four dependents and all 469 tests pass. **The trigger is
specific enough to predict: whenever DataKit gains a type, every dependent
package with a warm cache will report that type as missing.** After any
DataKit change, clean the dependents before believing a single one of them is
broken.

**Session 12 (the taste/discover lane, Aug 29 evening):**

*Fixtures that all satisfy a precondition cannot detect that the precondition
is load-bearing.* 0036 merged green with 14 assertions and wrote ZERO rows
against real data: every fixture had created a `profiles` row, and the writer
inner-joined profiles — a user without one contributed to no aggregate cell
at all. `LEFT JOIN` was the entire fix ([GLO-173](https://linear.app/glossed/issue/GLO-173), 0037,
caught within ten minutes because the writer was run against the live DB
right after merge). **Run every new writer against real data immediately,
and put one fixture on the wrong side of every precondition.**

*Switching the role GUC to anon does not clear the impersonation's JWT
claims.* `auth.uid()` reads the claims, so an "anon" pgTAP block after
`test_as()` is silently still authenticated. Only anon-GRANTED definer
functions expose it — grant-denied paths mask it with a 42501 that passes
for the right answer. Clear both GUCs; `leaderboard.test.sql` has the idiom.

*`timeout` does not exist on macOS.* `timeout 5 docker info` exits 127 —
which reads exactly like "daemon down" — and nearly caused a restart of a
healthy daemon. Related, same night: the daemon is **colima**, not Docker
Desktop; two osascript quits against an app that does not exist did nothing
while looking decisive. `docker context ls` names what is actually
underneath; `colima restart` is the remedy; volumes ride through. **Name the
thing you have observed, not the thing you assume is underneath** — two
sessions cross-confirmed the same split-brain symptom and both inherited the
same wrong noun.

*`gh pr list --author @me` matches every session* — all lanes share one
GitHub identity. "My PRs" must be tracked by branch name or you will adopt,
report on, or merge another lane's work. The taste lane found GLO-171's PR
under "mine" this way.

*A green branch plus a green main can still sum to a red main.* #266 passed
CI, merged, and left `AppShell.swift` at 301 lines — one over the lint cap —
because a sibling PR had grown the file after that CI run; every subsequent
PR failed lint on inherited state. The durable routine (the 1.5 lane's):
**test-merge your head onto the CURRENT tip before merging**, and look for
cross-lane hazards your branch CI could never see (the same routine caught a
`private`-scoping break on #269 that only existed after a peer's merge).

*Before driving the canon simulator, ask who is driving — including sessions
no ping round knows about.* A terminate/install/launch recipe killed a fourth
session's `GLOSSED_SCREENS` sweep mid-drive. And after any drive: restore
what you touched, disclose what you mis-tapped (an own→repurchased flip was
reverted and disclosed; drive fixtures deleted) — authorless drift costs
whoever finds it an hour of diagnosis.

*A stacked branch diffed against a moved main shows phantom deletions.*
After the base PRs squash-merge, `git diff origin/main` on the still-stacked
branch reads as if it deletes the siblings' work. Rebase before trusting any
local diff — the wiring branch briefly read as "removes DataKit code" when
the delta was pure staleness.

**Session 12 (the journal lane, Aug 30):**

*The twenty-two character drive that proved nothing.* In §0 because it is the
stretch's whole lesson; the operational form is short — **give a state the
smallest input that should work, not a realistic one.** Twenty-two characters
into the near-match name field returned three candidates and read as success;
one character exposed that the field deletes itself (GLO-176). The stub answered
any non-empty query identically, so the screen could not tell me what it had
actually received.

*A doc comment can state a contract the code beneath it does not implement.*
`NearMatchRungView`'s eyebrow gate is documented as "a list that failed to load
has no photos to check" — and it tested list *completeness*, never whether a
photo existed, so it told people to check drawings for 430 of 497 brands
(GLO-177). **When a comment states a rule, check that the expression under it
tests that rule.** A comment is a claim like any other.

*I nearly filed a bug against my own fixture.* `add to shelf` in the new
ladder-trip entry looked dead — sheet up, nothing happening. The cause was my
own entry leaving `onClose` at its default no-op, so nothing dismissed the flow.
**Check what you wired before filing against what someone else did.**

*A finding traced is not a finding walked.* GLO-176's reachability was argued
from `react(to:)` and `BarcodeRungModel.noneOfThese()` when filed; GLO-180's
fixture later let me walk it in four taps, and it held. Tracing is enough to
file. It is not enough to be sure.

*The file-length ceiling bit again*, and the answer is the split this repo has
already made four times (`AnchorSheetEntry`, `ShelfLifecycleEntry`,
`NearMatchFixtures`, `ScreenData`) — never a suppression.

*And two lanes refreshed THIS FILE within the hour.* I wrote a full update, then
found the taste lane had already landed one that fixed several of the same rows
— including a real pgTAP number (567) where mine would have written "not
re-measured". Re-applying my edits onto their version, rather than rebasing over
it, is the only reason that number survived. **Before editing a shared document,
diff it against the commit you started from** — and where the other lane's
version is better, take theirs.

### The onboarding lane, Aug 30 daytime (GLO-20 UI, GLO-18, tune, kit nav)

*§0's invented-name scar recurred INSIDE A TEST FIXTURE, same session it was
re-read.* The payoff test's wire JSON used `exact_shade_count`; the decoder's
CodingKeys say `n_exact_shade`. A fixture with a wrong key decodes to nil and
the test passes by testing nothing. Caught only by reading the CodingKeys
before writing the fixture — which is the same rule as §0's: **grep the name
out of the file, never type it from memory. Fixture keys are queries too.**

*The CI formatter is NEWER than the local one, and they disagree.* CI's
SwiftFormat enforces `wrapIfExpressionBodies`; the local `make format`
re-breaks that exact wrapping — so formatting a pushed branch locally UNDID a
CI fix and failed the next run. And SwiftFormat's multiline `if let x, cond {`
output violates SwiftLint's `opening_brace`. The escapes: fold format output
into the pushed commit (never a follow-up commit that local format will
fight), and refactor the fought-over expression into a computed property so
neither tool has an opinion. **When two formatters disagree, restructure the
code out of the disputed shape rather than arbitrating.**

*`swift test` builds macOS, and a `View`'s statics are MainActor there.*
Calling one from a nonisolated test traps at runtime (signal 5) — not a
compile error. Mark pure statics `nonisolated` (`TuneCard.line`,
`LeaderboardModel.n(of:)` both carry this). Same family: iOS-only modifiers
(`.keyboardType`, `.datePickerStyle(.wheel)`) need `#if os(iOS)` or the test
build breaks before any test runs.

*`AppShell.swift` sits at exactly 300/300 lines — it CANNOT grow.* Every new
shell wire goes in a new file as an `extension AppShell`, and anything needing
stored state gets its own host view (`TuneCardHost` owns its `@State`; the
shell cannot). Do not shave a comment to buy a line twice; the repo has split
four times for this and splitting is the answer.

*`ProfileDraft.brandAffinities` is `nil ≠ []` and the difference is a user's
data.* `nil` omits the key and the upsert leaves the column untouched; `[]`
wipes it — a deliberate answer. A caller that "defaults to empty" erases
brands. This was asked live by another lane and is worth restating here:
**never default an optional-collection draft field.**

*A live fixture read as vandalized, and `updated_at` said nobody touched it.*
Maya's fenty row looked flipped own→finished mid-drive; before reverting I
checked timestamps and found two pre-existing duplicate rows — nothing
flipped, and a "restore" would have been the actual data damage.
**Check-before-dismiss has a mirror: check before you REPAIR.** The evidence
bar for fixing data is the same as for filing against it.

*Two shell habits that silently no-op:* `docker exec psql <<heredoc` without
`-i` runs nothing and exits 0 — the heredoc needs stdin attached; and zsh
treats `===` as a glob (`echo ===CHECKS===` died AGAIN this session, twice
across sessions now) — quote any separator with repeated `=`.

*A magic offset let two views disagree about the same point.* The tour's
pulsing ring and its arrow each computed the target x independently
(`x − 27` vs `offset(x: 17)`); Sean saw the misalignment before I did. One
shared 54pt column now positions both. **Two views pointing at one thing get
one geometry, not two arithmetics.**

*Merging a peer's docs branch to avoid a file collision dragged their whole
epic's CODE into my docs PR.* Squash-merge means their branch's commits never
share SHAs with main, so `git merge` re-applies all of it. The fix:
`git checkout <branch> -- docs/HANDOFF.md` — **take the file, never the
branch.**

**Session 13 (the privacy/profile lane, Aug 30):**

*A merge is not an apply, and nothing in the repo can tell you.* The hosted
project sat **four migrations behind main** — 0043–0046, including two of
Sean's own rulings — and nobody noticed, because every one of them was merged,
green, and closed. The repo looks identical whether hosted is current or a week
stale. **After any migration merges, run `list_migrations` against the project;
that call is the only source of truth.** Applied 0044–0046 and verified the
result by querying hosted, not by trusting the tool's success.

*Copy derived from what RENDERED is not copy about what IS.* GLO-205 made
body-fact badges viewer-relative — they show only to a viewer whose own value
matches. The stranger preview then told users **"no badges — you haven't
published any"** while one was switched on, because it computed that sentence
from the empty rendered set. Before the ruling those two were the *same fact*,
so the derivation had been correct. The sharp part: the screen that lied is the
one built specifically so a user could **check** the privacy model rather than
trust the copy, so the fix protecting the data put the lie back on the
verification surface. **When a render becomes conditional on the viewer, every
sentence derived from that render must be re-derived from state.** Mine, within
the hour, caught only by driving (GLO-212, #346).

*I merged a red PR because my watcher checked completion, not conclusions.*
`gh pr checks` had finished, so the script said go; the db suite was FAILURE
and three assertions were red on main until I noticed. Then the repaired script
did it again one layer down: **right after a force-push the old checks are gone
and the new ones have not registered**, so "nothing incomplete" is briefly TRUE
and an eager poll reads an empty set as green. Both are the same bug —
**confirming the absence of failure instead of the presence of success.** The
watcher now sleeps before its first poll and requires the iOS job to have
reached a verdict.

*Frame conformance is worth auditing and the gaps were NOT systemic — record
the clean passes.* Sean said the privacy screen "didn't look the same"; the
source route in `docs/DESIGN.md` then found three real gaps — privacy's missing
master control, the cold-start shelf as one sentence where the frame specifies
a whole stage-0 screen (GLO-211), and settings, which reads as missing because
**it is a STATE of `G.Profile`, not one of the kit's 21 screens**. Then two
clean passes: the AddLadder rungs and the product page both match, each
carrying its one divergence *in the code*. A clean pass recorded as clean is a
finding — it is what stops the next session budgeting a week-long sweep.

*Five times now the shape has been "the layers exist, the screen never reached
for them"* — avatar, bio, display name, cold-start picks, the confidence meter.
`DesignSystem.Avatar` had shipped with the kit port and nothing drew it.
**Before concluding something needs building, grep for the component and the
repository method.**

### Session 14 (the profile lane)

*A feature can be merged, green, driven — and dead.* `submitPublicText` wrote
**directly to `public_texts`**, which has a SELECT policy and no insert policy,
so RLS refused every write. Linked socials had shipped that way and told users
*"that didn't save. try again"* about something that could never save. I had
also written a migration fixing `set_public_text()` — **a function the app
never called** — and told Sean "a bio renders the moment it's written", which
was false. What found it was executing the app's exact INSERT in psql and
watching it get refused. **A table with only a SELECT policy refuses all client
writes; check the policy set before believing a write path exists** (GLO-216,
[#356](https://github.com/seanbrasse/glossed/pull/356)). A pgTAP `throws_ok`
now asserts the refusal, so nobody "fixes" it by adding an insert policy.

*I closed a ticket on a partial and only caught it by checking the half I had
not built.* GLO-204 covers three fields; I shipped two and marked it Done.
Checking the avatar half found a bug **I had created**: `OwnProfileView` drew
the avatar initial from the handle while the other two profile screens use
`displayName ?? handle`, so once a display name became settable you were the
only person seeing a different initial than everyone else. **Before closing a
ticket, re-read its scope and check every part you did not personally build.**

*Two fixes were reverted this session for being partial, and both would have
read as complete.* (1) GLO-221: I proposed idempotent pgTAP fixtures in the
ticket, built all 28 across 16 files, ran it — 334 → 389 assertions, **7 files
still aborting**, because `public_profile.test.sql` calls the real
`claim_handle` against a user who already claimed through the app, and an
`on conflict` there would be flatly wrong. The fixtures were never the bug: the
suite is written to own its users from a clean slate and the clean slate is
what is missing. Re-pointed at "reset around the suite", which
GLO-223's snapshot made affordable within the hour and which shipped as
`make db-test-clean`. (2) The bio editor's capitalisation: a
typed `soft glam` stores as `Soft glam`, and I nearly overrode it before
reading that `GlossedTextArea` **documents having no `typing` option on
purpose** — prose keeps the system default. **A partial repair that reads as a
complete one is worse than none**, and the second case is the better lesson:
the primitive had already decided, in a comment, and my instinct was to
re-decide it locally.

*Grep found nothing means the query was wrong until proven otherwise.* Three
misses in one night across two lanes, one root: searching for a **spelling**
instead of a **behaviour** — literal `U+FE0E` where the source writes
`\u{FE0E}`; comment lines counted as occurrences; `autocapitalization` where
the code says `.plainTyping()`. All fail **silently and in the safe-looking
direction**: you get zero, which reads as "clean". The corollary is the sharp
one — **the better a codebase is, the more it wraps raw APIs, so grepping for
the raw API under-reports precisely where people were careful.** Its sibling:
check a ticket's *status* before reporting on it. A peer reported GLO-172's
accepted, shipped trade-off as a live finding; that costs Sean's attention
rather than an agent's, which is the expensive kind.

*State the evidence grade, every time.* Three claims this session rest on
different footing: the bio was **driven end to end** on the canon device *and*
verified in psql from both ends; GLO-206's frame items were **read against the
file** plus its tests and said so on the ticket; the avatar fix was **unit-
tested by reverting the fix and watching the test fail** before trusting it.
Saying which is which is what lets the next person know what to re-check.

*Two devices means two OSes, and a wrong path can be blocked by an accident.*
The canon is **iPhone 16 Pro / iOS 18.0** — a UI finding on another OS may not
reproduce, and 18.0 → 26.5 is eight majors of text metrics. I reached for an
iPhone 17 and it refused to attach for an unrelated **permissions** reason. Had
device access been granted, nothing would have objected and I would have had a
screenshot that looked like evidence. **The next lane will hit that prompt,
grant it, and sail straight through.**

### Session 14 (the AddLadder / Shelf / Import lane)

*Three tickets this session described harm that did not exist* — GLO-61's
`failed_searches` write, GLO-53's deleted-item race, and GLO-172's "open"
clipping question (the ticket was **Done**, and the clipping is the accepted
residue of a fix chosen after the obvious one was tried and reverted). All
three were settled by probing. **A ticket is a hypothesis written by someone
with less information than you now have — including when you wrote it.**
Reporting a closed, deliberate trade-off as a live finding is the expensive
version: it costs *Sean's* attention re-deciding something, with his own
earlier reasoning invisible.

*"Unblocked" is not the same as "worth doing".* GLO-202 was picked up because
it was code-only and needed no ruling while every Medium and High item wanted a
slot or an answer — availability standing in for priority. It cost a night and
ended in a PR Sean closed unmerged.

*The `plainTyping()` miss is the general case of the grep lesson.* A search for
`autocapitalization` returned nothing on a file carrying three `.plainTyping()`
calls, and absence-of-match was read as absence-of-care. **The code had done
something better than the string being searched for.**

*And a design-system tension worth watching:* `GlossedTextArea` justifies
having no `typing` option on the grounds that all its uses are prose — and
[#355](https://github.com/seanbrasse/glossed/pull/355) then found a text area
that wanted `.plain`. That assumption is one counterexample down; it survives
only because the import box is a bare `TextEditor`, not a `GlossedTextArea`.
**If a second one appears, the option belongs on the type, not a third
feature-local helper.**

## 9. Local setup

```bash
make setup && make dev
# the full sweep (§5) — run ALL of these, not just the package you touched:
# Packages are DISCOVERED, never listed (§8): three appeared in one hour and a
# hardcoded list cannot notice a package that did not exist when it was written.
for p in $(ls -d core/*/ features/*/ | sed 's:/$::'); do
  [ -f "$p/Package.swift" ] || continue
  echo "== $p"; (cd $p && swift test)   # 514 total at 63739aa — RE-MEASURE
done
make functions-test       # 82 deno tests
supabase test db          # 567 assertions / 1 known LOCAL failure (shelf_view 14)
# schema_migrations agreed at 42/42 when last checked (§0) — but nothing
# enforces it. To ask whether a migration landed, grep its object name out of
# the file and look for THAT, never a name you remembered:
grep -oE "create (or replace )?function [a-z_.]+" supabase/migrations/<file>.sql
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

**You should not need those seven scripts twice.** The catalog snapshot store
(GLO-223) lives at **`~/.glossed/catalog`** — deliberately OUTSIDE the repo,
because the first version kept its one copy at `supabase/.catalog-snapshot.sql`
and that copy was found sitting in one worktree of six, invisible to every
other lane and one `git clean` from gone. Override with `GLOSSED_CATALOG_HOME`.

```bash
make catalog-generations   # what the store holds, newest first, with row counts
make catalog-snapshot      # take one now
make catalog-restore       # put the newest one back
```

- **It refreshes itself.** Any script that grows the catalog leaves a fresh
  snapshot behind — the hook is in `scripts/db.ts`, which all eight import
  scripts must import to reach the database, so a script written later is
  covered without being wired up. It does not fire for a remote
  `GLOSSED_DB_URL`, when the row count did not move, or on a Ctrl-C — so
  `make catalog-snapshot` is still the explicit door.
- **Several generations are kept** (`GLOSSED_CATALOG_KEEP`, default 5), so a
  bad snapshot can never be the only snapshot. A save under
  `GLOSSED_CATALOG_MIN_PCT` (default 90%) of the last one is **refused** until
  you pass `--allow-shrink`; the old script only refused at zero rows, which
  meant 22,668 → 400 was silent.
- Each snapshot carries a `.meta` manifest (per-table counts, timestamp, git
  sha) and **restore verifies against it** — per-table counts plus an orphan
  check — and dies rather than half-succeeding.
- The dump is `--rows-per-insert --on-conflict-do-nothing`, not COPY, because
  the restore lands in a database `supabase db reset` has already seeded and
  `seed.sql` re-inserts brands/products/variants under **fixed uuids the
  snapshot also contains**. Plain COPY hits a duplicate key and the
  single-transaction restore rolls the whole catalog back. Restore is therefore
  idempotent — running it twice is a no-op, proven.
- `pg_dump --disable-triggers` **does not work here** and the old comment
  claiming it would was wrong: this container's `postgres` has `usesuper = f`,
  so it dies with `permission denied: … is a system trigger`. The restore uses
  `set session_replication_role = replica`, which Supabase does permit.

**Proven against a real `supabase db reset`**, not a rolled-back transaction:
22,668 rows before, 22,668 after (products 3,206 · variants 9,019 ·
brands 497). The fresh-machine path — no in-repo snapshot, store only — was
exercised in the same run.

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
