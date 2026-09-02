# Session handoff — Sept 2 2026 (session 19: the product photos came back, the tabs stopped remounting, and the stylist shipped behind a flag)

Where Phase 1 stands, what to do next, and what the last three sessions learned.
Read `docs/README.md` first for the design; this file is only about state.

**Starting a session?** [`docs/NEXT-SESSION.md`](NEXT-SESSION.md) is the short,
pasteable version — what to start on, what is blocked on a human, and the rule
that cost the most last time. This file is the reference it points at.

## Session 19 at a glance (Sept 1 → 2)

**15 PRs merged and 4 open at handoff.** Merged: #479, #476, #477, #478, #402,
#483, #430, #431, #481, #482, #485, #486, #487, #488, #490 — counted, in that
order; open and merging as CI goes green: #491, #492, #493, #494 (the Stylist —
#494 is stacked on #492 + #493 and must be rebased onto `main` after they
squash). All each watched to green under Sean's *"review and merge on
your own"* grant given Sept 1 evening). **Zero PRs open at handoff.** `main` is
at the close-of-session docs commit; the three PRs that predated this session
(#402, #430, #431) were reviewed, two of them fixed for a schema they predated,
and merged with the rest.

| What | Where |
|---|---|
| **Why the product photos vanished (Aug 31 ~11:39 UTC): a `db reset` drops the `storage` schema.** 3,206 products and 7,625 `variant_images` came back from the snapshot; **1.9 GB of cutouts were still on the storage volume**; but `storage.buckets` and `storage.objects` were empty, so Storage said *"Bucket not found"* for files it was standing on. `ProductImage` swallows a failed load into its floor by design, so nothing errored. Local repaired (13,877 rows registered, GETs `200 image/png`), and the bucket is now declared in `config.toml` with a reconcile script `make db-reset` runs | **#479**, GLO-223, §0 |
| **The tab "glitches" were one bug: the shell's `switch` on `tab` is not a tab container.** Every switch unmounted the old screen and mounted the new one from nothing. A `TabView` with its bar hidden per tab; recorded — 163 frames, four switches, every one a cross-dissolve of two laid-out screens (frame numbers on the ticket) | **#481**, GLO-256 |
| **The profile reloads when a composer or editor closes** (GLO-278 — five covers, zero `onDismiss`), in place, pulls to refresh, clears a stale toast, and its loading column is full width. Driven: a collection saved from `+` was on the tab the moment the composer closed | **#478, #483**, GLO-278 → Done |
| **The category tree landed**: renumbered `0055 → 0057`, both commits, one squash. Next free slot **0058** | **#476**, GLO-272 |
| **GLO-258's ten tables are all in the suite** — 8 → 18 asserts across #477 and #430. One latent finding left: `RankingRepository.positions()` is unpinned and has no caller | **#477, #430** |
| **The seed has a public stranger** (nadia) so isolation asserts assert something — #431, rebased and fixed: it inserted two `privacy_scopes` columns 0053 dropped, and two suites counted whole tables | **#431**, GLO-267 → Done |
| `make test` runs the 18 package suites instead of nothing | **#402**, GLO-264 → Done |
| **Sean's "updated products list" came through as a TAXONOMY, not products** — 0057 inserts categories only; the raw list is nowhere in the repo. Sean asked whether the new categories can be filled from Shopify: yes, in two steps — see §1 | GLO-272 comment, §1, §7 |
| **A wedged edge runtime hangs the `you` tab for ~2 minutes**; Docker here is **Colima**; the daemon wedged on one container and only `limactl stop --force` under Colima's `LIMA_HOME` got it back | §0, §8 |
| **GitHub CLOSES a stacked PR when its base branch is deleted** — it does not retarget. #480 died that way when #478 merged with `--delete-branch`; reopened as #483 | §8 |
| **The Stylist shipped behind a flag** — Sean's Sept 1 ask, built the same night as `tech/03` §7 pulled forward: `docs/tech/08-stylist.md` (spec, 14 use cases, the rules), edge function `stylist` (prefetch under the caller's JWT, `claude-opus-5` tool loop, eight tools, artifact ids validated, 11 tests), `features/Stylist` (thread, routine/product/look/collection cards, chips, composer, 10 tests), the glyph + `stylist_query` event, and the fourth tab behind `StylistFlag` (DEBUG on). Driven with the demo stylist — **no `ANTHROPIC_API_KEY` exists on any stack**, so the live path answers 503 until Sean adds one | #490 #491 #492 #493 #494, GLO-224 thread, §7 |
| **After the drive, Sean's four notes, all landed the same night:** the look tile is the photo (#485), fit a photo to the frame before upload — pinch, drag, crop (#486), the tab capsule centred and the dots gone (#487), and step 1 of the Shopify fill (#488) | GLO-272, GLO-266 |

## Session 18 at a glance (Sept 1)

**6 PRs merged** (#468, #429, #470, #432, #471, #472 — counted, each watched to
green under Sean's per-batch merge grants). **One PR is open and green: #473.**

| What | Where |
|---|---|
| **The app runs on Sean's actual iPhone**, tethered, signed with his team — not the simulator. Bundle ID is now `com.glossed.beauty`; `com.glossed.app` is owned by a different Apple developer account and was never available | #468, GLO-50, §0 |
| **Sign in with Apple works end to end** — App ID capability, Supabase provider, and the Swift: `AppleNonce`, `AppleSignInController`, and a DataKit opening for `signInWithIdToken`. Nothing advances until the server returns | #471, GLO-23 |
| **Migration 0055: an account cannot be under 13.** COPPA was a client-side promise — `AccountModel.createAccount` in Swift, on the happy path. A direct PostgREST insert with `birth_year_month = '2020-01'` was accepted without complaint | #470, GLO-23 |
| **Migration 0056: a calendar bomb, defused.** A freshly-built database has partitions for this month and next, never last — so `refresh_event_rollups(current_date - 1)` has nowhere to write on the 1st. Reachable 1 day in 30, and CI had never run on a first-of-month since the table was created | #470, §8 |
| **GLO-274 was a live bug, not pending work** — `PrivacyRepository.scopes()` still selected two columns 0053 dropped, so every visit to `you` raised a toast that then *stayed*. Diagnosed from a screen recording plus the Postgres log, not by reading code | #472 |
| **Hosted is caught up — 13 migrations applied, and verified.** It was **divergent, not behind**: it held 0040–0042 and 0046 but not 0043 | §0, §8 |
| **Onboarding mounts in the real shell**, and nobody gets through without a name and a handle | #429, #432, GLO-245 |
| **Linear's 6 epics became milestones** inside the Phase 1 project (52 issues reassigned), and all 7 ingest tickets were verified against `origin/main` and closed | — |
| The tagged-product list **collapses**, and a link **says its name first** (`morning glass skin - routine`) | **#473, open** |

## Session 17 at a glance (Aug 31 → Sept 1)

**26 PRs merged** (#441–#466 — counted, all watched to green and squash-merged
under Sean's standing merge-on-green grant for the session). One branch is
**committed, green locally, and has NO PR** — see §1 first.

| What | Where |
|---|---|
| **Per-item privacy replaced per-surface** for looks + routines: migration 0053, `can_view_item`, archive = scope-not-state, the per-surface arms fail closed | #441–#443, GLO-272 |
| **The R2 photo economy went from nonexistent to live end-to-end**: read path (batched signed GETs), pfp write+read namespaces, and — this session — an actual Cloudflare bucket + creds. First real photos ever rendered | #444, #452, #454, §0 |
| **The uniform edit pattern** (click in → edit → disabled-until-dirty save → confirm → delete-with-warning) shipped for looks, collections, routines; cards became doors | #447–#453 |
| **Batch 2**: collection descriptions, one-routine-one-collection per look (unique indexes), photo swap keeps the slot (row/position/tags survive, only `r2_key` moves), want-to-try default collection (virtual — renders `shelf(status: want_to_try)`), split link pickers (routine by label, collection as its card), open-then-swap photo viewers with camera | #457–#463 |
| **The reach ladder**: draft · only you · friends · public as ONE dial over the two columns; schema untouched (GLO-26's gate and `posted_at` stay on the draft→public transition) | #464 |
| **Spot cards render beside their dot** — translucent ink, milk text | #465 |
| **The `.task(id:)` self-cancel bug**: both photo viewers cleared `picked` first and cancelled their own upload; found the moment R2 went live, because before that the presign 500 masked it | #466, §8 |
| **The category tree for Sean's comprehensive product listing** — 10 new rankable groups, 4 relabels, 202 leaf types under `parent_id` — is committed and green locally but the PR was never opened (a background-script race, §8) | §1, branch `feat/GLO-272-category-tree` |


**Session 16 was one lane, and it spent the night on crossings rather than
features.** Nothing below was built from scratch except the collections
composer; the rest was already merged, already tested, and reachable from
nowhere. That is the session's one finding, and §0 now leads with it.

## Session 16 at a glance (Aug 31)

| What | Where |
|---|---|
| **An unsigned build was making three built tabs claim to be unbuilt.** `CODE_SIGNING_ALLOWED=NO` → no Keychain → the session cannot be read back → every read `notAuthenticated`. Sean saw it and asked whether the dev sign-in was worth keeping | §0, #427 |
| **A second RLS leak, live on `main`.** `ShelfRepository.shelf()` and `.items()` returned other people's rows; the shipped shelf tab was leaking. Reproduced against a genuinely public owner, fixed, and given the pgTAP suite that can see it | #422, GLO-258 |
| **The GLO-261 profile is finished and reachable** — identity block, three metrics, four tabs, a scope mark per tab, the `+`, and the handle claim that closes GLO-239 | #409–#411, #424 |
| **The face-off renders in the app for the first time since GLO-17.** Every `rank it` in the build was wired to `dismiss` or to `{}` | #423, GLO-240 |
| The **discover category eyebrow** stopped being invisible — one argument | #425, GLO-260 |
| The **collections composer**, and both doors that open it | #426, GLO-21 |
| `make run`, so the launch that costs an evening is one command | #427 |
| **This file carried three false claims**, each corrected in place rather than argued with: the face-off "became reachable", juli "holds a public routine and a public collection", `core/Media` "has never existed" | §0, §2, §6 |

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
| ~~The face-off became reachable~~ — **this line was FALSE; corrected Aug 31.** #375 and #381 landed entirely inside `features/Ranking`, `app/` never imported it, and `rank it` was wired to `dismiss`. Reachable as of #423 | #375 #381 → #423 |
| **DataKit opened once, and is spent**: routines, collections, looks reads + `publish()` | #376 #387 #391 |
| Migration **0048** — publishing a look is the owner's decision, deliberate and unmoderated pending GLO-26 | #378 |
| The **profile redesign** (GLO-261) — Sean's Instagram/Pinterest direction, mid-merge at handoff | #403 #406 #407 merged; **#408–#411 open** |

---

## 0. Read this first

### The catalog images live in the `storage` schema, and a `db reset` drops it

The GLO-223 snapshot keeps eight public tables. It does not keep
`storage.buckets` or `storage.objects`, and the `catalog` bucket was only ever
created imperatively by `scripts/catalog_images.ts`. So after any reset the
**files** (1.9 GB, `/mnt/stub/stub/catalog/<variant>/cut512.png/<version>` inside
`supabase_storage_glossed`) survive and the **rows that index them** are gone.
Storage answers `NoSuchBucket`; `ProductImage` renders its drawn floor; nothing
errors. Every product photo was a placeholder from Aug 31 ~11:39 UTC until Sept 1
and nobody noticed for a day — Sean asked *"why aren't we showing the actual
product photos anymore."*

**#479** (open) declares the bucket in `supabase/config.toml` — the CLI seeds
declared buckets on `start` **and** `db reset` (read in `supabase/cli`'s
`reset-local-database.ts`; prune of undeclared buckets defaults to *no*) — and
adds `scripts/catalog_storage.sh reconcile`, which inventories the volume and
registers every file as an object row with the `version` the file backend keys
on. `make db-reset` runs it after the snapshot restore. **Until #479 merges**, run
it by hand after any reset:

```bash
./scripts/catalog_storage.sh count      # bucket rows / object rows / files on volume / images without a file
./scripts/catalog_storage.sh reconcile  # idempotent; proves one GET at the end
```

Not verified: a full `make db-reset` round-trip with #479 — a reset takes the
local drive data out from under Sean's phone, and the standing rule is to ask.

### A hung `storage_presign` hangs the whole `you` tab — and Docker here is Colima

`ProfileTabsModel.load()` is serial and the looks read awaits the tile-preview
presign. When the local edge runtime wedged on Sept 1 (`serving the request…`
logged, never answered — even `{}` as a body hung, so the worker never booted),
the profile sat on a spinner until URLSession gave up (~2 min), then rendered
without previews. Probe before blaming the profile:

```bash
curl -s -m 10 -X POST http://127.0.0.1:54321/functions/v1/storage_presign \
  -H "Authorization: Bearer $ANON" -H "apikey: $ANON" -H "Content-Type: application/json" -d '{}'
# healthy: a 400 in <100ms. Anything else: the runtime is wedged.
```

Then: **the Docker daemon is Colima** (`docker context show`), not Docker
Desktop — there is no app to quit. On the wedge, `docker rm -f` / `docker start` /
`docker inspect` on the edge container hung indefinitely while `docker ps` and
`docker exec` still worked; `colima ssh` hung; `colima restart` **and**
`colima stop -f` hung too (both wait on the daemon's graceful stop). What
actually stopped it:

```bash
LIMA_HOME=$HOME/.colima/_lima limactl stop --force colima   # colima's own Lima home, not ~/.lima
colima start
```

Supabase's containers are `unless-stopped` and the DB volume persists, so the
stack comes back on its own; then `docker rm -f supabase_edge_runtime_glossed`
if one is left in `Created`, and `supabase functions serve` again. A follow-up worth making: resolve preview URLs
*after* the lists render, with a timeout, so a dead presign costs previews and
not the tab.

### Photos silently die when `supabase functions serve` is not running

Every photo surface (pfp, look uploads, carousels, tile previews, swaps)
rides `storage_presign`, which the local stack does NOT serve by default —
`supabase start` lists `edge_runtime` under "Stopped services", and cycling
the stack kills a running serve. The failure is quiet: the app renders its
honest placeholders ("photo not available yet") and nothing errors. Before
any photo work: `supabase functions serve` in its own terminal, and restart
it after every `supabase start`. Credentials live ONLY in
`supabase/functions/.env` (gitignored, present in the main checkout AND this
worktree; bucket `glossed-dev`, account in the file). Never print or commit
them. Rotation note: the token is account-wide R2 admin (`glossed-local-dev`
under Sean's profile API tokens) because Cloudflare's R2 dashboard writes
were down mid-setup — rotate to bucket-scoped when their dashboard recovers.

### TWO migrations claim slot 0055, and one of them is mine

**Resolved in session 19:** renamed to `0057` on the branch, PR #476 open and green.
Next free number is **0058**. Left for one cycle; the shape below still holds.

`main` now carries `20260901000055_an_account_cannot_be_under_13.sql` (#470,
this session). The un-opened branch `feat/GLO-272-category-tree` carries
`20260901000055_the_category_tree_grows_to_fit_the_shelf.sql`. **Same version
prefix, different files.** Supabase keys the ledger on that prefix, so the two
cannot coexist on one branch.

This is a session-18 mistake, stated plainly: the previous handoff's §0 warned
that this exact branch held migration 0055, and I took the slot anyway without
looking. The migration lock is not just "one open PR" — it is one open
*number*, and an un-opened branch still holds its number.

**Fix before opening that PR** (rename on the branch, not on `main` — `main`'s
0055 is merged and must not move):

```bash
git checkout feat/GLO-272-category-tree && git rebase origin/main
git mv supabase/migrations/20260901000055_the_category_tree_grows_to_fit_the_shelf.sql \
       supabase/migrations/20260901000057_the_category_tree_grows_to_fit_the_shelf.sql
```

Then open the PR as the previous handoff describes: **both commits, one squash**
(DataKit guard + the 202-leaf tree), size-override, because shipping the data
without the guard floods five category pickers. Also state the taxonomy decision
it encodes — products rank at the TOP level, the 202 leaves are vocabulary.

### Hosted is caught up, and the ledger will lie to you about it

Hosted (`nsnniahnfmagoejwrgvc`) now matches the repo's **56 migrations**. Verify
the arithmetic before trusting it, because the ledger shows **59 rows**:

- `badges_never_name_the_value` and `bios_auto_approve` each appear **twice** —
  re-applied this session, safe only because both are `create or replace`.
- Repo file 0046 landed as **two** hosted rows (`reference_data_tree_and_domain_chips`,
  `reference_data_category_chips`).

59 − 2 − 1 = 56. ✅

**Hosted was divergent, not behind** — it held 0040–0042 and 0046 but not 0043,
so "N migrations behind" was never the right description and any catch-up plan
built on that number would have been wrong.

**The ledger versions are MCP-generated timestamps that do not map to repo
filenames.** Repo `20260831000053_an_item_carries_its_own_visibility.sql` is
hosted `20260901213611`. So: **never ask whether a migration landed by matching a
version.** Grep an object name out of the file and probe for THAT:

```bash
psql "$DB" -c "select count(*) from pg_proc where proname = 'can_view_item'"
```

**This is the condition that hid GLO-274** — hosted still had the dropped
columns, so the stale read succeeded there and failed only against a database
that was actually current. `supabase login` + `supabase db push` would end the
whole class of problem; no CLI token exists, and Sean chose to continue via MCP
for this round. **Getting that token is the highest-value chore on the list.**

**The rest of §0 is standing hazard, accumulated across sessions 15–18. None of
it is visible in the code, and each entry cost real time at least once.**

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

### A build flag that is correct for CI produces an app that cannot sign in

`.github/workflows/ci.yml` builds with `CODE_SIGNING_ALLOWED=NO`. That is right
there — CI never launches anything. Copy that line into a build you intend to
**run** and you get an **unsigned** app, which has no Keychain access.
supabase-swift persists the session to the Keychain, so `signIn` succeeds and
the very next `auth.session` throws.

What that looks like on the phone: every live read returns `notAuthenticated`,
`AppSession.reloadShelf()` swallows it on its `try?`, `shelfModel` and
`discoverModel` stay nil — and discover, shelf and profile, **all three built
and merged**, render `not built yet · GLO-20` / `· GLO-21`. Sean read the app
as broken and asked whether the dev sign-in was worth having. It was; the
placeholder was lying.

Diagnosed with `codesign -d --entitlements -`, which printed nothing at all for
the installed binary. **Use `make run`** — it exists now for exactly this, and
it also supplies the two env vars. *Shape: a flag that is correct in one context
is not therefore correct in another, and "it built" is not "it runs".*

### Building to a real phone: what `make run` does NOT cover

`make run` targets the simulator. A tethered device needs four things that took
a session to find, all now in `project.yml`:

- **`DEVELOPMENT_TEAM: QHGRFFYNUJ`** and `CODE_SIGN_STYLE: Automatic`. Device
  builds had previously worked only via the XC Wildcard profile.
- **Bundle ID `com.glossed.beauty`.** `com.glossed.app` is registered to a
  *different* Apple developer account and cannot be claimed. Sean picked this as
  an interim — *"I'm not settled on the glossed name for now"* — so treat the
  identifier as provisional, not as a naming decision.
- **An explicit `info:` block instead of `GENERATE_INFOPLIST_FILE`.**
  `NSAppTransportSecurity` is a *dictionary*, and `INFOPLIST_KEY_*` can only
  carry scalars. Switching also means `CFBundleShortVersionString` and
  `CFBundleVersion` must be pinned to `$(MARKETING_VERSION)` /
  `$(CURRENT_PROJECT_VERSION)` — XcodeGen otherwise defaults the version to 1.0
  and silently drops yours.
- **A bundle rung in `AppSession.boot()`'s config lookup.** A phone launches with
  no environment at all, and `SUPABASE_PUBLISHABLE_KEY` has no fallback, so the
  keys are baked in at build time via `GlossedSupabaseURL` /
  `GlossedSupabasePublishableKey`. The values are passed on the `xcodebuild`
  command line and are **not** committed.

For LAN access to a local stack: `NSAllowsLocalNetworking` covers `.local` and
unqualified hostnames but **not raw IPv4** — a raw IP needs an
`NSExceptionDomains` entry — and iOS 14+ terminates the app outright without
`NSLocalNetworkUsageDescription`.

### Sign in with Apple needs far less configuration than the guides suggest

The **native** flow (`signInWithIdToken`) needs only the **bundle ID as the
Client ID** in Supabase. No Services ID, no `.p8`, no client secret. Two traps:

- Supabase's provider form rejects a save with *"Secret key should be a JWT"*
  even when the Apple flow does not use one — the rule is **"must be a JWT *if
  present*"**, and a leftover secret from another provider fails it. Clear it.
- Apple must receive `sha256(rawNonce)`; Supabase must receive the **raw** one.
  Sending the same value to both fails in a way that reads like a config problem.

### A package can be linked into the app target and imported by nothing

`grep -rn "import <Package>" app/` is the two-second check §2 already
recommends, and it found **five** surfaces merged and dark in one session:

| surface | what was missing |
|---|---|
| the profile's four tabs, scope marks and `+` | seven `OwnProfileView` parameters, all defaulted `nil` |
| the discover category eyebrow (#388) | one argument — `catalog:` on `DiscoverStore.repository` |
| the face-off (GLO-17, #375, #381) | `app/` never imported `Ranking`; `rank it` was wired to `dismiss` |
| the shelf sheet's `rank it` | `ShelfView` never passed `onRank`, so the sheet took its defaulted `{}` |
| the collections composer | `features/Collections` imported by nothing; no live adapter at all |

**The face-off one matters most, because this file said the opposite.** The
previous handoff's at-a-glance table recorded *"The face-off became reachable
for the first time since GLO-17 — #375 #381"*. It was not reachable at all:
both PRs landed entirely inside `features/Ranking` and neither touched `app/`.
Tapped on device before changing anything — nothing happened. *Shape: a
handoff's claims are claims. The one instrument that settles "is this
reachable" is the app, not the ticket and not this file.*

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
| **The Stylist** — five PRs (#490–#494), the spec merged first; the rest merging as CI goes green under the standing grant. #494 (the tab) was stacked on #492 and #493 and must be rebased onto `main` after they squash — the inflation shape | GLO-224 thread |
| **The stylist has a key locally (Sept 2, session 20) — and, as of #496, does not need one for the shaped asks.** `glossed-stylist-local`, a *personal* console key, in `supabase/functions/.env` only, with `ANTHROPIC_WORKSPACE_ID` beside it — a personal key is refused without `anthropic-workspace-id` on the request, so #496 sends it. Expires Oct 2 2026. No hosted secret. With #496, `plan.ts` answers a routine, the gaps, try-next, compare and about from data with zero model calls; only a free-form question reaches `model.ts`, and without a key it gets the honest menu instead of a 503. `STYLIST_DEMO=1` still drives the canned stylist | Sean (key) |
| **Rules first, model last (Sept 2, session 20).** Sean: *"as little AI as possible."* #496 (function: `plan.ts`, `data.ts`, `model.ts`, 12 planner tests; base #491), #497 (the routine card's shape, *open it* through the shell's `.routine` door, `onRoutineSaved` → the GLO-278 profile trip; base #494), #498 (`08-stylist.md` §4; base `main`). Driven live as maya, no key: morning routine → save → open it → edit → profile lists it; a pm routine saved from the tab reached the already-mounted profile. **Retarget #496/#497 to `main` before their bases are deleted.** The local seed has an empty `agg_rank_scores` and no shade anchor, so *missing* says "no receipts yet" and *try next* carries only the exploration slot — honest, and the cohort receipts light up with face-off data | #496 #497 #498, GLO-224 thread |
| **Filling the new categories from Shopify** (Sean's ask, Sept 1) | **Step 1 done — #488** (rules in `TYPE_RULES`, backfill in `scripts/reclassify_new_groups.sql`, 168 products moved on local, 0 ladders touched). Step 2 (leaves) still needs slot **0058** |
| **Sean's product list** | Still not in the repo — ask where it is before building on "the new products" |
| Local drive data | The `session 19 drive` collection was soft-deleted after the GLO-278 drive; nadia is now seeded on every reset |

### Filling the new categories from Shopify — step 1 landed Sept 1 (#488), step 2 open

The importer's `TYPE_RULES` (`scripts/shopify_import.ts`) map a storefront's
`product_type` to a **top-level** category and know nothing about the ten
groups 0057 added, so every one of them holds **0 products** while the catalog
already contains products that belong there:

| new group | Shopify products that belong (by `product_type`) | where they sit today |
|---|---|---|
| lipcare | 83 (`lip balm`, `lip treatment`, `lip mask`, `lip scrub`) | `lip` |
| tools | 37 (`cheek brush`, `foundation brush`, `eyeshadow brush`…) | blush 18, foundation 8, brow, concealer… |
| exfoliant | 25 (`exfoliator`, `lip scrub`, `masks & peels`) | treatment 14, mask 9 |
| body | 20 (`body moisturizer`, `body serum`, `body fragrance mist`) | moisturizer 9, fragrance 6 |
| primer · lashes · device | 3 · 3 · 2 | mascara, serum, lip |
| setting · scalp · haircolor | 0 in the current storefronts | — |

**Step 1 — done (#488).** `TYPE_RULES` carries the ten groups first, in a
stated order (primer before lip, device before tools, lip care before body
before exfoliant), and `scripts/reclassify_new_groups.sql` is the same ten
patterns as Postgres regexes — the backfill, because the importer's insert is
`on conflict do nothing` and a re-run never moves a filed row. Run once on
local: 168 moved (lipcare 87, tools 37, body 20, exfoliant 13, setting 5,
primer 3, lashes 2, device 1); a second run moves nothing. **The TS rules and
the SQL CASE are kept in step by hand** — no test proves it. Hosted still has
0 products, so nothing to run there until the catalog is promoted.

**Step 2, one migration (0058):** a `products.leaf_id` (nullable, must point at
a row with `parent_id set`) and a `product_type → leaf slug` map. Measured:
**1,277 of 2,202** Shopify products' `product_type` string-matches a leaf label
(`lip gloss`, `lip liner`, `brow gel`, `sheet mask`…); the rest are top-level
words (`fragrance`, `mascara`, `blush`) with no finer Shopify type — those are
correct at the top and stay leafless. Then extend `search_catalog`'s `attrs` to
include the leaf slug so `snail mucin` finds the serum typed as one.

**What Shopify cannot fill:** setting, scalp, haircolor — none of the 22
listed storefronts sells them. Those need new storefronts in `STORES`, and each
one is a `curl`-200 check plus a brand-name entry.

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
| ~~The app-layer seam for the profile~~ | **Done — #424.** All seven filled; four tabs, their scope marks and the `+` render, driven as maya against a genuinely-public juli |
| ~~**GLO-260** — the discover eyebrow~~ | **Done — #425.** One argument. The eyebrow (`FRAGRANCE`) renders; the same screenshot on `main` an hour earlier had none |
| ~~**GLO-258** — five unaudited tables left~~ — **in the suite, #477 (session 19)**; what remains is one unpinned, uncalled read, `RankingRepository.positions()` | The RLS OR leak. **The shelf's two are closed (#422)** — `ShelfRepository.shelf()` and `.items()` both leaked, reproduced against a public owner, and the shipped shelf tab was leaking too. `supabase/tests/database/owner_scoped_reads.test.sql` is the instrument and needs no migration slot; extend it rather than writing a second file |
| ~~**GLO-239** — the profile does not refresh after a handle claim~~ | **Done — #424.** The profile presents the claim sheet itself now, so dismissal is a signal it has. **Not drivable on maya** (she has a handle); reasoned from the code, and whoever gets a handle-less account should confirm it |
| ~~**GLO-245** — onboarding mounts only from the debug picker~~ | **Done — #429, #432.** FLOW 1 mounts in the real shell and the name+handle step ships. What unblocked it was GLO-23's Apple half: the new-account path now gets a real session, so `finish` has one to write a profile with. The **phone** path still dead-ends pending Twilio |
| **GLO-224** — does Discover own a search field? | Needs Sean. Three costed answers on the ticket. An honest placeholder (`brand, product, shade…`) already shipped; the IA question did not |
| **GLO-227** — discover chips | Blocked on a DataKit opening. Option B (`topChips(productIDs:)`) recommended — no migration, serves every product-card surface |

---

## 2. What exists

**Session 19 ran seven suites, not eighteen.** Run this session, on `main` or
on the branch that landed: `core/DataKit` 134, `features/Profile` 106,
`features/Collections` 17, `core/Tracking` 16, `features/Looks` 91,
`features/Stylist` 10, and the `stylist` function's 11 `deno test`s. Every other
count below is **carried from session 18's full sweep** (914 across 18 packages)
and was not re-run — treat those as approximate. A red package is a stale
`.build` cache until proven otherwise (§8).

| Package | Tests | State |
|---|---|---|
| `core/DataKit` | **134** | The frozen core. **Four openings spent**: routines/collections/looks (Aug 30), the shelf's scoping fix (#422), `signInWithApple(idToken:nonce:)` (#471), and the GLO-274 privacy read (#472). The last derives its select list from `CodingKeys` so a dropped column cannot silently break it again |
| `core/DesignSystem` | **54** (s18) | `KitIcons` carries the drawer's five glyphs + a pencil; `StylistIcon` in its own file (the ceiling); `FloatingNav.Glyph.stylist` |
| `core/Media` | **8** | **It exists** — `PhotoPreparer`, `PresignedUploader`. GLO-148 says it never has; that is stale |
| `core/Tracking` | **16** | The event queue; `stylist_query` carries tool names and a bool, never the words |
| `features/AddLadder` | **120** | The biggest suite in the repo |
| `features/Browse` | **14** | |
| `features/Collections` | **17** | Composer + store. **Wired to the drawer and the profile `+` as of #426** |
| `features/Discover` | **35** | The stream. Category eyebrow live as of #425 |
| `features/Import` | **12** | Screen + model; **no live `ImportParsing` conformance exists** — GLO-19 |
| `features/Leaderboard` | **16** | |
| `features/Looks` | **91** | Composer, reorder, media deck; reachable from the drawer's fifth door |
| `features/Onboarding` | **69** | FLOW 1 **mounts in the real shell** as of #429; name+handle ships (#432); **Sign in with Apple is real** (#471) — `AppleNonce`, `AppleSignInController`, and one seam covering sheet + server call so the model stays testable. Phone OTP still stubbed |
| `features/Privacy` | **18** | |
| `features/ProductPage` | **22** | |
| `features/Profile` | **106** | The redesign, complete and wired (#403–#411, #424); reloads in place on a `reloadKey` (#478); the look tile is the photo (#485) |
| `features/Ranking` | **41** | The face-off. **Reachable as of #423** — it was not before, whatever the last handoff said |
| `features/Routines` | **15** | Composer only; the profile's routines tab reads through `ProfileRoutinesStore` |
| `features/Shelf` | **138** (s18) | |
| `features/Stylist` | **10** | **New (#493).** Wire types for the `stylist` function, a store of closures with `.live` and `.demo`, the thread model, and the routine / product / look / collection cards. Reachable via the fourth tab **only behind `StylistFlag`** (#494, DEBUG on) |

**A red package here is a stale cache until proven otherwise.** `features/Shelf`
reported `error: fatalError — cannot find type 'LogDraft' in scope` during this
sweep. `LogDraft` had moved to `ShelfModels.swift` in #422 and Shelf's `.build`
still held the pre-split DataKit module. `rm -rf .build` and it is 138 green.
§8 already carried this shape; it cost ten minutes anyway.

**Two sentences are true about all of it.** *A merged feature is not a
reachable one* — and, since session 19, *a reachable feature may be behind a
flag*: the stylist tab exists on every DEBUG build and on no release build
until Sean flips `StylistFlag`, and its live path is a `503` on every stack
until an `ANTHROPIC_API_KEY` exists. What was driven was the demo stylist.

*A merged feature is not a reachable one.* This session merged a category eyebrow that renders nothing, an
onboarding flow with no caller, a collections package with no adapter, and a
face-off that was built in GLO-17 and had never once rendered in the app. **Before
building anything new, check whether the thing it depends on is wired** —
`grep -rn "import <Package>" app/` is the two-second version.

**Local stack (Sept 2):** repo migration head **0057** (the category tree);
`products` = **3,206** (168 re-filed into the ten new groups by #488), 13,877
catalog image rows registered against the storage volume (#479). Catalog
snapshot store at `~/.glossed/catalog`, newest generation taken after the
backfill. The local ledger does not match the repo's filenames (§0) — probe
objects, not versions.

**Canon simulator changed.** The old UDID in previous handoffs is **dead** — the
device set was rebuilt when the disk filled. It is now **iPhone 16 Pro,
`0A658108-11CB-40AD-BC2B-1B140CDFB192`, iOS 26.5**. Launch with the env vars or
you get a config-missing screen:

```bash
SIMCTL_CHILD_SUPABASE_URL="http://127.0.0.1:54321" \
SIMCTL_CHILD_SUPABASE_PUBLISHABLE_KEY="$(supabase status -o json | jq -r .PUBLISHABLE_KEY)" \
xcrun simctl launch <UDID> com.glossed.beauty
```

**Live fixtures — and the correction that matters.** maya owns `morning glass
skin v2` (am, 2 steps), four collections, five shelf items and the handle
`maya_k`. The previous handoff said **juli holds a public routine and a public
collection**; she does not, and `seed.sql` never gave her one. Probed Aug 31:
`privacy_scopes` holds **zero rows for anyone**, juli's collection is
`only_you` (it is named `JULI PRIVATE KIT`), and she owns **no** shelf items
and no looks.

So every cross-user isolation assertion in this repo currently runs against an
empty set — the "ceremony" failure §8 names, as the default state. Verifying
GLO-261's tabs meant making juli genuinely public by hand first, asserting,
then reverting. **[GLO-267](https://linear.app/glossed/issue/GLO-267) puts the
fixture in `seed.sql`** so it survives a reset and runs in CI. Until it lands:
build the public fixture, confirm the thing you are excluding is genuinely
reachable, assert, revert.

## 3. How this session worked

Unchanged: branches `feat/GLO-<n>-desc` (also `fix/`, `docs/`, `test/`), ≤5
files/400 lines (`size-override` + reason when the shape demands it), squash
merges, **one migration NUMBER at a time — including numbers held by branches
with no PR yet** (session 18 broke this; §0), drive-then-psql on everything, two lanes
coordinating by direct message with file-level ownership announced before
touching.

**Session 19's loop, under Sean's "review and merge on your own" grant (given
Sept 1 evening — per-session, not standing):**

1. one PR per concern, ≤5 files or `size-override` with the reason written
   (tests count as files — #478 went red on exactly this);
2. a background chain per PR: poll `gh pr checks` until nothing is
   in-progress, refuse on any `FAILURE`, `gh pr merge --squash --delete-branch`;
3. **for a stack, retarget the next PR to `main` BEFORE deleting the merged
   branch** — GitHub closes a PR whose base vanishes (#480 → reopened as #483);
   then rebase the next one so its diff is its own again;
4. for a PR older than the last migration, re-run CI before trusting the
   check — #430 and #431 were green against a base 0053 had since changed;
5. after the last merge, lint and build `main` itself, because `main` runs no CI.

**Session 17's loop, which produced six merged fixes in one stretch:**

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
restore (§9, seven scripts, ~50 min).

**The local baseline is no longer "567 / 1". Re-run Aug 31: `Files=40,
Tests=533, Result: FAIL`, with SIX files red.** CI is still zero, so this is
local rot, and it is worth knowing before you spend an hour on it:

| file | why |
|---|---|
| `handles`, `public_profile`, `suggested_people`, `browse_routines` | all four die on `duplicate key … handles_pkey`. **maya has a handle in the local DB and the suites assume she does not.** It is drive-created (`handles.created_at` = Aug 30 21:11 EDT), not seeded — `seed.sql` writes no `handles` row |
| `looks` (3, 13) | not investigated |
| `shelf_view` (14) | the previously known one |

So four of the six are one cause, and that cause is **drive-drift, diagnosable
in one query**: `select * from handles`. A `make db-reset` clears it and now
snapshots the catalog first, so the ~50 min restore is no longer the price it
was. *The general point: check the timestamp before you believe the red.* The
number this file used to carry was a different lane's, taken before that drive
happened, and it went stale silently.

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

**A stand-in that announces itself is a legitimate drive of the UI, not of the
feature.** The stylist was driven with `STYLIST_DEMO=1` — every canned line
begins "demo ·" — which proves the tab, the cards, the save, the doors and the
chips, and nothing about the model's answers. Say which half a drive proved.

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
| **Stylist:** product rows are not doors — opening a product page needs a `CatalogHit` the block does not carry (STY-12); the row's image area draws nothing without a catalog key (the mock silhouette does not render at 56pt) | GLO-224 thread, `08-stylist.md` §5 |
| **Stylist:** streaming needs a third method on `GlossedClient` (frozen core); v1 is turn-at-a-time with a `thinking…` line | STY-11 |
| **Stylist:** no transcript table by decision (08 §3) — the thread dies with the tab; persisting it is a `domain.md` §6 retention decision | 08 §3 |
| **Stylist:** the TS tool schemas in `tools.ts` and the Swift wire types in `StylistWire.swift` are kept in step by hand; no test crosses the boundary | STY-4 |
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
| ~~`core/Media` has never existed~~ — **stale, corrected Aug 31.** It exists, with `PhotoPreparer.swift`, `PresignedUploader.swift` and 8 passing tests. Re-scope or close | [GLO-148](https://linear.app/glossed/issue/GLO-148) |
| Hosted Supabase: schema is **current through 0056** (session 18), but still essentially empty — measured Sept 1: **22 categories, 0 products, 0 profiles, 0 auth users**. The 202-leaf tree is not there (it rides the un-opened branch, §0) | [GLO-158](https://linear.app/glossed/issue/GLO-158) |
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
| **Session 17:** GLO-279 — the profile's rename-in-place machinery is dead code (edit-profile button removed; edit screens own renames). Pure deletion | [GLO-279](https://linear.app/glossed/issue/GLO-279) |
| **Session 17:** the collection COMPOSER takes no description (create-then-edit); Sean may want it at creation | GLO-272 comments |
| **Session 17:** profile grid can hold a stale tile after an edit under the cover until its next load (same as post-composer saves) | GLO-272 comments, #448 body |
| **Session 17:** pfp reads are OWN-ONLY by construction; rendering anyone else's face owes the minors ruling (said in-code at the read branch) | #454 |
| **Session 17:** R2 orphan reaping (re-shoots, deleted looks, pfp swaps all orphan old objects) is a standing server-side job nobody owns | 0053/0054 comments |
| ~~**Session 17:** the "something went wrong." toast on the profile is local-only … local edge-runtime/feed flakiness~~ — **FALSE, disproved session 18.** It was [GLO-274](https://linear.app/glossed/issue/GLO-274): `PrivacyRepository.scopes()` selecting two columns 0053 had dropped. Fixed in [#472](https://github.com/seanbrasse/glossed/pull/472). **Worth the shape, not just the fact — a real schema/code disagreement was written off as "local flakiness" for a full session because it only reproduced against a database that was actually current** | #446 → #472 |
| **Session 17:** want-to-try leaf slugs vs the shelf's `want_to_try` status: the default collection renders STATUS; the new `body`/`device` etc. leaves are catalog vocabulary. Unrelated systems that share words — do not merge them | the category-tree migration (**was** "0055"; that number is the age floor now — §0), `WantToTryStore` |

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

**Unblocked in session 17 — left in for one cycle:**

| Was blocked | What happened (Sept 1) |
|---|---|
| R2 / any photo feature | **DONE.** Bucket `glossed-dev` + creds exist; pipeline verified in-app both directions. The Cloudflare R2 *dashboard* was mid-incident — bucket was created over REST with a profile API token when the R2 pages hung |
| The migration slot | Free at handoff — 0053/0054 merged; 0055 waits in the un-opened PR (§1) |
| DataKit openings | GLO-272's grant was used across the whole session (edit writes, swap, description, category guard). Treat as **spent**; per-session rule stands |

**Still blocked, and an agent must not spin on these:**

| Blocked thing | On what | Who |
|---|---|---|
| **`ANTHROPIC_API_KEY`** for the stylist | In `supabase/functions/.env` locally (the file holds only the R2 keys) and as a hosted function secret. Without it the stylist is a 503 and the tab says so | Sean |
| **Minors and the stylist** | No ruling; v1 answers adults only (`isAdult` in `tools.ts`, `403 not_yet`). 13–17 see *"the stylist is for adults for now"* | Sean |
| **The stylist's refusal copy** (medical classifier, STY-7), **its budget table** (STY-8, a migration slot), **the kit frame** (STY-10, `/design-login`) | Each named in 08 §5 | Sean |
| **Where is the product list?** | Sean's "comprehensive product listing" (Sept 1) reached the repo only as 0057's category rows. No file in `docs/`, `scripts/`, `supabase/seed*`, no `.csv`/`.json`. If it named branded products, they are not in the catalog and nothing can make them searchable until the list itself is in hand | Sean |
| **Promoting the catalog to hosted** | Hosted has 0 products / 0 images / 0 buckets. `scripts/db.ts` targets local unless `GLOSSED_DB_URL` is set; the image step needs a Mac. Needs `supabase login` or the hosted DB URL — same blocker as the migration ledger | Sean |
| A DataKit opening for `RankingRepository.positions()` | One line, latent, no caller. Wait for a caller or a grant | Sean |
| Any **new** Linear issue | Workspace at the free issue cap. **Updates to existing issues work** (verified session 18); only creates fail. Upgrade or archive | Sean |
| R2 token rotation | Cloudflare's R2 dashboard writes recovering (active incident Sept 1); then mint a bucket-scoped token and swap `.env` | Sean / Cloudflare |
| Leaf-level ranking question | The 0055 tree ranks at the top level BY DESIGN. If Sean ever wants "rank your lipsticks" as its own ladder, that is a product decision + a re-point of `products.category_id` consumers — ask, don't drift into it | Sean |
| [GLO-262](https://linear.app/glossed/issue/GLO-262) profile views | **Which of three shapes, or none.** Aggregate-only, identified-and-visible, or identified-owner-only. It is a privacy decision before a schema one — an identified viewer log would be **the first surveillance surface in the app**. Recommendation on the ticket: aggregate-only or not in V1 | Sean |
| [GLO-266](https://linear.app/glossed/issue/GLO-266) tag search scope | His own open question: shelf, whole catalog, or catalog-with-shelf-first. **Recommendation: catalog-wide, shelf ranked first** — GLO-196 makes a look attributed content, never a claim, so an evidence rule should not gate a tag. Built so the scope is one injected query | Sean |
| [GLO-224](https://linear.app/glossed/issue/GLO-224) discover search | Does discover own a search field, or does search stay behind the `+`? Three costed answers on the ticket. The honesty half already shipped (`brand, product, shade…`); **do not ship the frame's `vibe search:` placeholder over name/brand FTS** | Sean |
| [GLO-265](https://linear.app/glossed/issue/GLO-265) cadence | Not the schema — **what cadence is *for*.** Nothing reads `slot` to remind or schedule. If it is a label, keep it a label; a scheduling field nothing schedules grows a notification system nobody asked for | Sean |
| [GLO-227](https://linear.app/glossed/issue/GLO-227) discover chips | A DataKit opening. Option B recommended (`topChips(productIDs:)`) — no migration, serves every product-card surface | Sean |
| [GLO-237](https://linear.app/glossed/issue/GLO-237) CI | `.github/workflows/` is frozen to agents. Two-line fix: `curl --fail --retry` **and** pin SwiftFormat on **both** sides — the Brewfile pins nothing either, so both float independently | Sean |
| [GLO-218](https://linear.app/glossed/issue/GLO-218) | Two rulings: one routine per look or many, and may it credit **someone else's**? If yes the link needs its own `can_view` check **or a private routine leaks through a public look** — [GLO-263](https://linear.app/glossed/issue/GLO-263) carries the trap | Sean |
| [GLO-267](https://linear.app/glossed/issue/GLO-267) seed fixture | **Ready to build, needs a go-ahead only because it moves shared state.** `seed.sql` has no cross-user public fixture, so every isolation assertion in the repo runs against an empty set. Changing seed data reaches every lane's drive at once, and nine PRs were open when it was filed | Sean |
| [GLO-245](https://linear.app/glossed/issue/GLO-245) onboarding | **Partly unblocked.** FLOW 1 now mounts in the real shell (#429) and the name+handle step ships (#432), because Sign in with Apple gives the new-account path a real session. The **phone** path still dead-ends at the account step pending Twilio | Sean |
| Any further DataKit opening | Per-session. Aug 30–31's is spent; Aug 31's second opening (the shelf's scoping fix, #422) is **also spent** | Sean |
| Any migration slot | **0057 is held by #476.** Next free is 0058 — and a branch with no PR still holds its number (§0) | Sean |
| [GLO-172](https://linear.app/glossed/issue/GLO-172), [GLO-156](https://linear.app/glossed/issue/GLO-156), [GLO-178](https://linear.app/glossed/issue/GLO-178) | Design calls, unchanged. Render both options and let him pick rather than re-deriving them | Sean |
| GLO-23 — **phone OTP half only** | Sign in with Apple is **DONE** (#471): App ID capability, Supabase provider, and the Swift all shipped and were driven on Sean's phone. What remains is Twilio, which Sean deferred outright ("we deal with twilio later"). `sendCode`/`verifyCode` stay no-ops until then | Sean |
| The hosted project | Still needs a DB password, service-role key, or CLI login. **Hosted is at 46 migrations and lacks `0043` (looks) and `0047` (handles)** — probed, not assumed | Sean |
| Landing page → Rakuten / Impact / Beauty API | Unchanged: Vercel project creation 403s on team role; the signups need the channel URL | Sean |
| GLO-85 queue consumer | `ANTHROPIC_API_KEY` **and** Sean's direct word | Sean |
| The browse-tab IA question | Whether trending + routines browse earn a fourth tab. The kit does not answer it, and **its FLOW 2 caption is falsified by delta 11** | Sean |
| Save/wishlist mapping | Whether `want_to_try` IS tech/07's +0.5 save signal | Sean |

## 8. What went wrong, so you don't repeat it

### Session 19 (Sept 1 → 2) — append-only, newest first

**I "restarted Docker Desktop" without checking what Docker was.** `osascript
quit app "Docker"` → *Unable to find application named 'Docker'* → `docker info`
answered immediately because nothing had restarted. The provider was Colima the
whole time (`docker context show`, ten characters). *Shape: look before you
assert — the fix for "the daemon is wedged" depends on which daemon, and the
check costs less than the wrong restart.* Recorded in memory as well as here.

**I opened a 6-file PR without the label and CI told me.** #478 is four source
files plus their two test files; the size gate is ≤5, no exceptions for tests.
Added the label and the reason after the red run. *Shape: count the files
`git diff --stat origin/main` prints before `gh pr create`, not after.*

**I killed a `supabase functions serve` that Sean had started.** It was wedged
(even `{}` hung) and the restart was the right call, but it was his process in
his terminal, from this worktree. Said here so he is not surprised by a dead
tab. The replacement runs from this session's `nohup`, so it dies with the
machine, not with the terminal.

**A `cd features/Profile && swift test` in one command moved the shell's cwd for
every command after it.** The next lint, commit and `gh pr create` all ran from
inside the package and failed in ways that looked like real errors (`No lintable
files`, `pathspec did not match`). *Shape: the Bash cwd persists across calls;
subshell it — `(cd pkg && swift test)` — or use absolute paths.*

**A `\copy … from stdin` fed through `$(cat file)` inside a heredoc silently lost
columns.** The first storage repair failed with `missing data for column` on a
line that was not in the file. `docker cp` the TSV in and `\copy` from a path.

**Duplicates on the storage volume.** 13,882 files, 13,877 objects: a re-upload
leaves the old version file behind and both claim one object name. The reconcile
keeps the newest by mtime — an `ON CONFLICT DO UPDATE` over all of them dies with
*cannot affect row a second time*.

**The stylist's glyph pushed `KitIcons.swift` to 338 lines and CI caught it,
not me.** The 300-line ceiling is per file; adding 50 lines to a 288-line file
is over it, and `swiftlint` on the package said so only after the PR was open.
Moved the icon to its own file. *Shape: `wc -l` the file you are adding to
before you add to it — the ceiling has bitten three sessions now.*

**The stylist was driven with a canned store, and every screenshot says so.**
No `ANTHROPIC_API_KEY` exists anywhere, so the live path could not be driven.
Rather than claim it, `STYLIST_DEMO=1` swaps in a stylist whose every line
starts "demo ·" — the tab, the cards, the save, the doors and the chips are
proven; the model's answers are not. *Shape: when the real thing cannot be
driven, drive a stand-in that announces itself in every frame, and say which
half is proven.*

**GitHub closes a stacked PR when its base branch is deleted — it does not
retarget it.** `gh pr merge 478 --delete-branch` closed #480 (base: #478's
branch) on the spot, and `gh pr edit --base main` then refused because the PR
was closed. The merge script had `set -e` and no check on the merge's result, so
it went on to rebase #481 into a conflict and force-push mid-rebase. Reopened
the commit as #483. *Shape: when squash-merging a stack, retarget the next PR to
`main` BEFORE deleting the merged branch — or do not delete it — and check
`gh pr view --json state` after every merge before acting on the next.*

**Two pre-session PRs were green and would have broken `db reset`.** #430 and
#431 last ran CI on Aug 31 at 11:46; 0053 dropped `privacy_scopes.routines` /
`.looks` at 18:37 the same day, and both inserted those columns. A green check
is a claim about the base it ran against. *Shape: for any PR older than the
last migration, re-run CI before trusting the check.* #431 also counted public
looks table-wide in `look_links.test.sql`, which the stranger it seeds then
broke — the exact "ceremony vs absolute count" shape its own comment names.

**What was NOT done, stated so it is not assumed:** a `make db-reset` round-trip
with #479; the GLO-278 acceptance for a routine and a look (collections was
driven: saved from `+`, on the tab immediately, no spinner); the full 18-package
test run (DataKit, Profile and Collections were run on `main` after the merges;
the rest were not touched).

### Session 18 (Sept 1) — append-only, newest first

**I wrote this handoff from memory instead of invoking the skill that exists for
it, and the skill caught two gaps.** `session-handoff` was installed the whole
time. Writing the document first and running the skill afterwards surfaced (a) no
next-agent *prompt* — the skill is explicit that the reference and the
instruction are different documents — and (b) no drift pass over the sections the
session did not touch, which is where the §6 toast correction came from.

The shape, because it is not about this one skill: **an available procedure you
approximate from memory will pass its own review.** The document looked complete
because I was grading it against my own plan. Check for a skill or checklist
before producing the artifact, not after.

**I took a migration slot the previous handoff had warned me about.** Its §0 said
in as many words that `feat/GLO-272-category-tree` held migration 0055. I read
that section, then numbered the age floor 0055 anyway. The lock is one open
*number*, not one open PR, and an un-opened branch still holds its number. §0
carries the fix.

**Three separate squash-merge traps, all in one stack, all costing real time:**

1. `gh pr merge --delete-branch` on #432 **closed #469**, because GitHub closes
   any PR whose base branch is deleted — and a *closed* PR's base cannot be
   changed, so it could not simply be retargeted. #469 had to be reopened as
   **#471** off `main`.
2. Compensating with `--delete-branch=false` on #429 then left #432 pointing at
   a stale base and showing **CONFLICTING** — a conflict with no conflicting
   lines. Retargeting to `main` cleared it.
3. Plain `git rebase` on the child **replayed the parent's pre-squash commit**,
   re-adding code that was already on `main`. The stacked-rebase incantation is
   `git rebase --onto <new-base> <old-parent-tip>`, and nothing warns you.

**I stated a docs conclusion as settled and it was wrong.** I said the native
Apple flow needs no client secret — true — and then the Supabase dashboard
refused to save with *"Secret key should be a JWT."* The actual rule is **"must
be a JWT *if present*"**: a stray secret left over from the Google provider was
failing validation on a field the Apple flow does not use. Clearing it saved.
The claim was right about Apple and wrong about the form.

**A screen recording came out 0 bytes twice.** `TaskStop` hard-kills, so
`simctl recordVideo` never writes the moov atom and the file is unplayable —
stop it with `pkill -INT -f "simctl io"` instead. After the first kill,
CoreSimulator held a stale host record lock; only rebooting the device cleared
it.

**Two bugs in my own migration, both caught by the test rather than by review.**
I asserted 2026-09-01 was "ambiguous" for a `2013-08` birthday when it is the
first *certainly-13* day, and I wrote a comment claiming `birth_year_month` was
nullable when it is `NOT NULL`. Also drafted a dead-code
`ensure_events_partitions_window()` helper and cut it — the cron already covers
long-running databases; only fresh installs need 0056.

**`Codable` ignores unknown keys, so no decode test could have caught GLO-274.**
The struct kept decoding fine; the *select list* was what named dropped columns,
and only the database objected. `PrivacyScopes` now derives its select list from
its `CodingKeys` (`CaseIterable`) so the two cannot drift again.

**The profile's scope mark read `public` over a draft.** Found by driving the
fixed build, not by reading it: `looks_public_read` tests `state = 'public'`, so
unpublished looks must be excluded from the ceiling. Two existing tests failed my
first attempt at `mark(for:)` — they assert a privacy signal must *wait* rather
than guess. I restored the guard rather than weakening the tests.

**Top-level `private` in Swift is file-scoped**, so promoting test helpers to
internal collided with `ProfileCardCopyTests`' same-named declarations.
Fixtures stay localized per the package's existing convention.

**The stale-`.build` trap recurred, at seven times the scale — §2's existing
warning was not enough.** Session 17 hit it in one package (`features/Shelf`) and
wrote "a red package here is a stale cache until proven otherwise." That sentence
was there, and it still cost time, because the failure does not look like a cache
problem: **it breaks the packages DOWNSTREAM of the one you changed, and blames
the wrong file.** After the DataKit edits, `swift test` failed in
**7 of 18 packages** — AddLadder, Browse, Discover, Import, Leaderboard,
ProductPage, Ranking — with type-inference errors reported *inside
`core/DataKit/Sources/DataKit/RoutinesRepository.swift`*, a file none of them
touch and which compiles fine on its own (DataKit's own 133 tests passed in the
same run). It ends in a bare `error: fatalError` naming nothing.

All seven passed after `rm -rf <package>/.build` — 120, 14, 35, 12, 16, 22, 41,
no code change. The tell is the shape: **the failing package is not the package
named in the error.** Before
debugging any cross-package compiler error after a DataKit change, clear the
caches — and note that a per-package sweep is exactly how this surfaces, which is
another reason §5 says to run all of them rather than the one you touched.

### Session 17 (Aug 31 → Sept 1) — append-only, newest first

**A background script and a foreground branch switch raced, and the loser was
invisible.** The habit all session was one backgrounded compound: build → lint
→ commit → push → `gh pr create` → poll-and-merge. It worked 20+ times — until
a foreground `git checkout -B` ran while the background script was still in
its 36-second build. The script's later `git commit` landed on the NEW branch,
its push shipped an empty branch, and both `gh pr create` attempts failed with
"No commits between main and …" — leaving the category tree merged-looking
locally and nonexistent remotely. **The shape: git state is process-global; a
backgrounded script that touches the index or HEAD owns the worktree until it
exits. Background ONLY the poll-and-merge; do commit/push/create in the
foreground and read `gh pr list --head <branch>` for a number before moving
on.** Also the poller's `gh pr view $N` with an empty `$N` silently falls back
to the *current branch* — quote-and-check `$N` first.

**`.task(id: picked)` cancels itself if you clear `picked` first.** Both new
photo viewers cleared the picker selection as step one of the upload handler —
which changes the task id, which cancels the running task, which kills every
in-flight URLSession call with -999, which surfaced as "that photo didn't
save" over a pipeline that was fine. The composer's original picker cleared at
the END; the new code didn't copy that, and nothing caught it because uploads
could not succeed locally anyway (no R2) until the very hour the bug mattered.
**Anything running under `.task(id:)` must not mutate its own id until done —
and an error path that can't be exercised locally is untested, not passing.**

**`CODE_SIGNING_ALLOWED=NO` cost a third drive.** Session 16 wrote the rule,
session 17 broke it anyway by copying the CI invocation for a "quick check"
and then driving that build: unsigned → no Keychain → every read
`notAuthenticated` → the app reads as broken. `make run` exists precisely so
nobody types the flag. Build-only compile checks are fine; never LAUNCH that
artifact.

**form_input "ok" on a React radio is not a selection.** Cloudflare's R2 token
form: `form_input` on the Admin-Read-&-Write radio returned ok, the UI kept
Object-Read-only selected, and the submit nearly minted a useless token. **On
JS-framework forms, click the element and re-screenshot to confirm state;
form_input is only trustworthy for text fields.**

**When a vendor dashboard hangs, check their status page before debugging
yourself.** Three R2 dashboard writes hung silently (bucket ×2, token ×1) with
no error UI. cloudflarestatus.com showed an active R2 incident. The unblock
was routing around the broken plane: profile-level API token (different
backend) → REST bucket create → S3 creds derived as token-id +
SHA-256(token). An hour of UI retries would have found nothing.

**A merged PR left `main` one line over the file ceiling — again.** The chrome
PR merged with `OwnProfileView.swift` at 301 lines (session 16's exact
merge-race shape; the limit is per-file and `main` runs no lint of its own).
It surfaced as a red herring on the NEXT branch's local lint, and was fixed by
extracting `ProfileClaimSheet.swift` inside an unrelated PR, honestly labeled.
**After merging anything that grew a file near 300, `wc -l` it on main.**

**Restoring dev data changed the local test baseline.** Re-inserting handle
`maya` (needed so drives are not stuck on "no handle yet") made
`suggested_people.test.sql` collide on `handles_pkey` locally. Known class
(shelf_view #14 is the same). **The local pgTAP baseline is now TWO known
failures; CI is the arbiter. Write down every dev-data write you make, because
it becomes someone's mystery red test.**

**A scripted block cut can silently take the wrong span.** A python extraction
for a 300-line split matched a doc comment INSIDE the block, produced a file
starting with `}`, and the reflex `git checkout --` recovery ALSO reverted two
unrelated staged-in-working-tree edits in the same files, which then had to be
re-applied from memory. **Cut blocks by exact anchor lines you have just read,
and never checkout-revert a file holding unstaged work you still want.**

**swiftformat and swiftlint disagree about multiline declaration braces.** A
class declaring two protocols across lines gets its brace re-wrapped by one
tool and flagged by the other, forever. Restructure instead: one-line
declaration plus per-protocol `extension`s. Re-running the formatters in
alternation converges on nothing.

### Session 16 (Aug 31) — the crossings, and three false claims in this file

**A green PR that GitHub calls `CLEAN` can still produce a `main` that does not
compile, and nothing in CI is looking.** #425 was green — lint, scope, iOS
build — and GitHub reported `MERGEABLE` / `CLEAN`. Merging it would have landed
an `AppShellPrivacy.swift` with **`func compose` defined twice**.

The cause is the stacked-squash double-apply already in this file's scar list.
#425's branch still descended from #424's **pre-squash** commit, so it carried
its own copy of #424's changes; `main` carried the squashed copy; the three-way
merge applied both. **CI never tested that result** — it tested the branch. The
size gate reads the same stale merge base, so it reports the inflated file count
as though that were the change.

Caught only because `git diff origin/main origin/<branch>` looked alarming — it
appeared to delete #423 and #427 wholesale, which is a two-way diff against a
branch that predates them and a false alarm in itself — and that was worrying
enough to justify a local `git merge --no-commit --no-ff` and a look. The
duplicate was in the result.

*Shape: after ANY squash-merge in a stack, rebase everything below it before
merging. Not because a label says to —* `git merge --no-commit --no-ff` *into a
scratch branch is the only thing that shows you what you are about to ship.
Fifteen seconds, and it is the only gate that would have caught this.*

**Five merged features were reachable from nowhere, and the cause was always
the same.** A repository in `core` and a screen in `features` belong to two
lanes; the file in `app/` that joins them belongs to neither. Session 15 already
named this ("seams fall between lanes and nobody owns them") and it kept
happening, because naming a shape does not assign an owner. The five: the
profile's seven `nil` stores; the discover eyebrow's one missing argument;
`RankItView`, built in #381 and constructed by no one; `ShelfItemSheet`'s
`rank it`, taking a defaulted `{}`; and `features/Collections`, which had a
store, a tint, a summary type and no adapter to `CollectionsRepository`.

*Shape: `grep -rn "import <Package>" app/` costs two seconds and settles it.
Run it on anything you are told is done.* The collections PR (#426) ships the
seam and the crossing together, with a `size-override` whose written reason is
exactly this — splitting them would have made a sixth.

**A control wired to `dismiss` looks deliberate in a way `{}` does not.**
`ProductPageView`'s `rank it` was `onRank: dismiss` at all three call sites. It
reads as a decision. It is a dead end, and it survived review at three separate
sites because each one looked intentional. *Shape: when a callback's argument is
another callback the screen already has, ask what it was supposed to do.*

**This handoff carried three claims that were false, and each cost time.**
"The face-off became reachable" (it was not — #375/#381 never touched `app/`);
"juli holds a public routine and a public collection" (she holds neither, and
`seed.sql` never gave her one, so every isolation assertion in the repo runs
against an empty set — GLO-267); "`core/Media` has never existed" (it exists,
with 8 passing tests). Session 15's own §8 says *"a frame's status is a claim
like any other. Quote the line."* **That applies to this file.** *Shape: when
this document tells you something is done, the app is the instrument, not the
sentence.*

**A build flag correct in one context is wrong in another.** See §0. The tell
was that `codesign -d --entitlements -` printed nothing at all; the symptom was
three tabs claiming to be unbuilt. Thirty minutes went into reading auth code
before anyone looked at the binary. *Shape: when every read fails and the writes
never happened, suspect the process, not the queries.*

**The stale-`.build` shape recurred, and the sweep is where it bites.**
`features/Shelf` reported `error: fatalError — cannot find type 'LogDraft'`
during the full-package sweep, ten minutes after #422 moved `LogDraft` to a new
file. `main` was green; the package's `.build` held the pre-split DataKit
module. §8 already carried this. *Shape: in a package sweep, a red that names a
type you just moved is a cache. `rm -rf .build` before you debug it.*

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
`com.glossed.beauty` — launching `co.glossed.app` from memory got
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
supabase test db          # local: 533 tests, 6 files red — see §4, mostly drive-drift. CI is zero
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
`com.glossed.beauty` (read `project.yml`, don't recall it). **Screenshot pixels
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
