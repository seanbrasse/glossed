# Session handoff — Aug 28 2026

Where Phase 1 stands, what to do next, and the decisions a new session would
otherwise have to rediscover. Read `docs/README.md` first for the design; this
file is only about state.

## 0. Read this before you build a screen

**Open the frame first.** [`docs/DESIGN.md`](DESIGN.md) has the design kit's URL
and — more importantly — how to read `screens.jsx` **as source**, which gives
you exact copy, sizes and tokens instead of a screenshot to squint at.

The route in `DESIGN.md` (read the code viewer's `<textarea>`) **no longer
works**: the viewer moved into a cross-origin frame that the browser pane's
`javascript_tool` cannot reach. What works, and what GLO-62 was built from, is
the project's own API, called from the pane with the session's cookies:

```js
// with any page of the design project open in the browser pane
const r = await fetch('/design/anthropic.omelette.api.v1alpha.OmeletteService/GetFile', {
  method: 'POST', credentials: 'include',
  headers: {'content-type': 'application/json'},
  body: JSON.stringify({projectId: '38230b94-09d2-4776-9d21-be0722ba54f2',
                        path: 'ui_kits/glossed-app/screens.jsx'})});
const {content} = await r.json();                       // base64
const src = new TextDecoder().decode(Uint8Array.from(atob(content), c => c.charCodeAt(0)));
```

`ListFiles` takes `{projectId, path}` and lists a directory. `screen-map.html`
comes back the same way, captions included — which is the part the frames alone
do not carry. Both are exact, both are ~100KB, and slicing by symbol
(`src.indexOf('G.Shelf = function')`) is how to read one screen at a time.

This is not a nicety. An earlier session could not reach the kit, built the
whole submission ladder from the primitives instead, and produced screens that
use every token correctly and look nothing like the design. That is
[GLO-62](https://linear.app/glossed/issue/GLO-62), and it is a rework, not a
polish pass. **If you cannot open the frame, stop and say so.**

Every UI ticket now names its `G.<Screen>` symbol and quotes the frame's
structure. The PRD sections that constrain each screen are quoted there too,
because the PRD is not in this repo (§9).

## 1. Where to start

Everything is tracked in **Linear**, not GitHub Issues:
workspace [glossed](https://linear.app/glossed), team **GLO**, project
**GLOSSED — Phase 1: The Journal**. Every ticket carries its design frame, its
PRD references, and what is blocking it.

Next tickets, in dependency order:

| Ticket | Why it is next |
|---|---|
| [GLO-16](https://linear.app/glossed/issue/GLO-16) shelf + cutouts | **Start here.** The biggest genuinely-free work. Unblocked by GLO-48's presign ([#37](https://github.com/seanbrasse/glossed/pull/37)). The ticket carries the bay view's exact geometry, and `ProductMock` (#56) is the primitive its bays are made of |
| [GLO-65](https://linear.app/glossed/issue/GLO-65) a way to run a screen | Small, and it pays for itself on the next UI ticket. The app root is still `PlaceholderView`, so every look at a screen costs a throwaway edit — see §5 |
| [GLO-63](https://linear.app/glossed/issue/GLO-63) three facts the catalog withholds | The ladder's rows are shipped with an empty sub-slot because of it. Server-side; wants a migration slot |
| [GLO-62](https://linear.app/glossed/issue/GLO-62) ladder rework | **Done for what exists.** Rungs 0–2 rebuilt to the frames: [#56](https://github.com/seanbrasse/glossed/pull/56) `ProductMock`, [#57](https://github.com/seanbrasse/glossed/pull/57) the rows, [#58](https://github.com/seanbrasse/glossed/pull/58) rung 0, [#61](https://github.com/seanbrasse/glossed/pull/61) rung 1, [#60](https://github.com/seanbrasse/glossed/pull/60) rung 2. Rungs 3–4 were never built, and belong to GLO-15 when GLO-60 unblocks it |
| [GLO-60](https://linear.app/glossed/issue/GLO-60) DataKit: 3 gaps | **Blocks GLO-15 from closing.** Needs a human, or explicit authorization — see §4 |
| [GLO-56](https://linear.app/glossed/issue/GLO-56) who owns the shade/size pick | A decision, not code. Also blocks GLO-15; read it before starting GLO-16 |
| [GLO-15](https://linear.app/glossed/issue/GLO-15) submission ladder | Search, barcode and near-match rungs merged. Create rung is not buildable (GLO-60) |
| [GLO-47](https://linear.app/glossed/issue/GLO-47) product page · [GLO-19](https://linear.app/glossed/issue/GLO-19) import | Parallel-safe — different feature directories, untouched |
| [GLO-14](https://linear.app/glossed/issue/GLO-14) catalog ingest | Server-only lane, parallel with all iOS work |
| [GLO-48](https://linear.app/glossed/issue/GLO-48) catalog images + R2 | Presign done. The rest **needs a human with the Cloudflare account** — see §9 |

**Blocked on a human, not on code:**
[GLO-50](https://linear.app/glossed/issue/GLO-50) App Store Connect — the Sign in
with Apple capability on the App ID gates [GLO-23](https://linear.app/glossed/issue/GLO-23)
(auth flows), which gates [GLO-18](https://linear.app/glossed/issue/GLO-18)
(onboarding). Everything else routes around it.

## 2. What exists

**53 PRs merged, all CI-green.** `main` is the only long-lived branch.

| Layer | State |
|---|---|
| Schema | 6 migrations, all applied to the hosted project. 49 pgTAP assertions. |
| `core/DataKit` | **FROZEN** — see §4. Config, client, typed errors, 4 repositories. 23 tests. |
| `core/DesignSystem` | Tokens, 3 bundled fonts, 28 primitives. 26 tests. `ProductMock` is what the frames draw; `TypographicTile` is the floor below it. No icon primitive yet ([GLO-64](https://linear.app/glossed/issue/GLO-64)). |
| `features/Ranking` | Complete: engine, rules, session, view. 29 tests. |
| `features/AddLadder` | Ladder, search rung, barcode rung, near-match rung — **all three built to the kit frames**. 78 tests. Create rung blocked (GLO-60); the rows' sub-slot is empty for want of data (GLO-63). |
| `supabase/functions` | `storage_presign` — scoped R2 PUT URLs. 14 Deno tests, run by the `functions · deno` CI job. **Not deployed** (§9). |
| Other features | Not started — the bulk of what remains. |

**Hosted Supabase**: project `glossed`, us-east-1. The project ref lives in the
Supabase dashboard and in `.env`, deliberately not written down here — RLS is
what actually protects the data, but a public repo is no place to hand someone
a target. Migrations are applied **manually via the Supabase MCP after each
merge**; [GLO-46](https://linear.app/glossed/issue/GLO-46) replaces that with a
CI `db push`. Never apply `seed.sql` to it — the seed creates fake auth users
and is local/staging only.

## 3. How this session worked (worth repeating)

- Branches `feat/GLO-<n>-desc`, conventional commits, squash merge.
- **PRs ≤5 files / 400 lines.** When one grew past that by acting on review
  findings, it used `size-override` **with a written reason as a PR comment** —
  the label is for that, not for convenience.
- Migrations are a global lock: one open migration PR at a time, and the merged
  SQL is applied to the hosted project before moving on.
- CI changes ship as their own small PR rather than riding along with feature
  work, so a gate is never quietly weakened inside an unrelated diff.
- **The user authorized self-merge on green CI for that session only.** The
  handbook default is a human read on every PR. Without explicit
  authorization, do not self-merge.

## 4. DataKit is frozen

`core/DataKit` is the one path every query takes. Do not modify it. If a feature
needs data it does not expose, that is a ticket against DataKit reviewed on its
own — not an edit made in passing. The reasoning is in `core/CLAUDE.md`; the
short version is that a missing session check there stops being a bug and
becomes a data leak.

Business rules do not belong in it either. Ranking order, wear-in gating and
unlock thresholds live in the features that own them.

**Three changes are queued against it**, bundled into
[GLO-60](https://linear.app/glossed/issue/GLO-60) so the core is opened once
rather than three times. One of them is not a nicety:
`PersonalProductDraft` requires a `brandID`, and nothing on `CatalogRepository`
returns brands — `search_catalog` gives `brand_name` as a string with no id. So
the create rung's "brand typeahead FK, no free-text brands" **cannot be built at
all**, and GLO-15 cannot close until that lands.

## 5. The automated recap earns its keep — read it

**It is manual now, not automatic** (Aug 28). Each run is a full Sonnet agent at
30 turns billed to a *personal* Anthropic key, and a busy agent session opens a
dozen PRs — plus a close/reopen for every recap that came back a stub. That
outran what the review was worth paying for on every PR. Ask for one where it
matters:

```bash
gh workflow run visual-recap -f pr=123
```

It still posts the same thing: mermaid diagram, file map by layer, schema
deltas, risk-ordered review notes.

It has now caught four real bugs, and they are all one family: **a name
claiming more certainty than the code can supply.** Two sub-shapes, worth
telling apart because the fixes differ.

*A guess reported as a statement.* A placement the system guessed recorded as
one the user stated — first for comparison-cap exhaustion, then, in the very fix
for the first, for skips, because a skip collapses the search range exactly as a
resolved comparison does. The fix adds a flag that admits the uncertainty.

*An attempt reported as an achievement.* `SearchRung` returned
`recordedMiss: true` after calling `recordFailedSearch` — which is `try?` inside
frozen DataKit and swallows its own transport errors, so the layer above cannot
know whether the miss was recorded. And `SearchRungModel` re-derived "is this a
miss" from the raw query while the rung decides from the *tidied* one, so `" a "`
would have claimed a miss for a search that never ran. The fix here *removes* a
claim rather than adding a flag — rename to what is actually known, or delete
the second implementation of the rule. Prefer this shape where it is available.

Treat its findings as review, not decoration: act on them before merging. If
acting on them pushes the PR past 400 lines, that is what `size-override` with a
written reason is for — trimming the reasoning the review asked for to hit a
number defeats the point of both.

Two mechanical facts:
- It **refuses to run on any PR that modifies workflow files** (a sound guard:
  otherwise a PR could rewrite the workflow to exfiltrate the key). Workflow
  changes cannot test themselves; the next feature PR is the check.
- **A green `recap` run does not prove a recap was posted.** Seen twice
  ([#43](https://github.com/seanbrasse/glossed/pull/43),
  [#45](https://github.com/seanbrasse/glossed/pull/45)): the agent spent its
  turns working out how to pipe a body into `gh pr comment`, left a stub, and
  exited green. The prompt now tells it to write the body to a file and forbids
  test comments ([GLO-59](https://linear.app/glossed/issue/GLO-59)), but look for
  the comment rather than the check mark.

**Since it no longer runs automatically, the PR body's Visual plan section is
the only shape-of-the-change artifact on most PRs.** Hold it to that bar.

### With the recap manual, you are the review

Turning it off ([#51](https://github.com/seanbrasse/glossed/pull/51)) removed the
only automated review these PRs had. It caught five real bugs in one session, so
the loss is real. Two things partly cover it:

- **The PR body's Visual plan section is now the only shape-of-the-change
  artifact on most PRs.** Write it like someone will rely on it, because they
  will.
- **Run the thing on a simulator.** Every UI bug this session that mattered was
  found by looking at the screen, not by a test: a doubled heading, iOS
  autocapitalising a brand name into a miss, a rung that never searched on
  appear, and copy instructing a phone that cannot scan to scan.

  It held on the next session too. GLO-62's rework was looked at four times and
  the two defects that came out of it were both invisible to tests: an escape
  row nobody could pick out of a list, and a near-match list whose products all
  drew as the same pink dropper — on the screen whose eyebrow says *check the
  photo, not the name*.

  **The cost is that there is nowhere to look.** `app/Glossed` is still
  `PlaceholderView`, so each of those four looks meant hand-writing an entry
  point and a fake repository into `GlossedApp.swift`, then remembering to
  revert it. A review step that costs an uncommitted edit is a review step that
  gets skipped silently. [GLO-65](https://linear.app/glossed/issue/GLO-65) is a
  `#if DEBUG` screen picker, and it is smaller than the ticket it unblocks.

## 6. CI economics

The repo is **public**, so Actions minutes are free and this is now about speed
and noise rather than spend. The shape is still worth knowing: measured over 98
runs, the macOS iOS build was **87% of billed minutes**, because macOS bills at
**10×** and each run costs ~21 minutes.

Already in place: a concurrency group cancels superseded runs; a cheap Ubuntu
`scope` job gates the macOS build on Swift changes and the database suite on
`supabase/` changes; CI no longer re-runs on push to `main` (a squash-merge has
identical content to the PR just tested). Skipped jobs cost nothing.

If the repo ever goes private again, the macOS build is the only thing that
matters, and batching pushes is the single biggest lever.

## 7. Open threads

| Item | Where |
|---|---|
| Mid-session shelf changes desync a ranking session | [GLO-53](https://linear.app/glossed/issue/GLO-53) — decide with the screen that calls `apply` |
| Hair-type reference photos are placeholders | [GLO-52](https://linear.app/glossed/issue/GLO-52) — must be real, reviewed by people with those hair types |
| Category tree + chip vocabulary exist only in dev seeds | [GLO-51](https://linear.app/glossed/issue/GLO-51) — production needs them as a migration |
| No branch protection on `main` | Now that the repo is public, protection is free — worth enabling |
| Numbers chosen, not validated | `docs/BACKLOG.md` — payoff n≥8, min-n 5, shrinkage k≈10 |
| Nobody owns the shade/size pick | [GLO-56](https://linear.app/glossed/issue/GLO-56) — a search hit is a *product*, a shelf item is a *variant*. AddLadder or GLO-16's logging sheet? Blocks GLO-15 |
| Two-char search floor duplicated | [GLO-55](https://linear.app/glossed/issue/GLO-55) — frozen DataKit and AddLadder each hard-code it. Drift one way silently poisons the queue GLO-14 reads |
| Autocorrect fix lives at a call site | [GLO-57](https://linear.app/glossed/issue/GLO-57) — belongs in `GlossedInput`, next to `GlossedKeyboard`. Every future search field forgets it otherwise |
| Orphaned cutouts accumulate | [GLO-54](https://linear.app/glossed/issue/GLO-54) — re-shoots write new keys by design; nothing collects the old ones |

## 8. Local setup

```bash
make setup         # tools, xcodegen, supabase start, db reset + seed
make dev           # regenerate + open Xcode
supabase test db   # 49 pgTAP assertions
```

Docker runs via **colima** (`colima start --cpu 2 --memory 4`). One gotcha seen
this session: a Docker image whose layer was corrupted by a full disk keeps
being reused after a re-pull — `docker system prune -a -f --volumes` is the fix,
not another `docker pull`.

## 9. Blocked on a human, not on code

Both need credentials no agent has. Everything else routes around them.

**R2 provisioning ([GLO-48](https://linear.app/glossed/issue/GLO-48)).** Buckets
`glossed-prod` / `glossed-dev`, an API token, CORS, and a spend alert. Until
they exist, `storage_presign` is merged but deliberately **not deployed** — a
deployed function without secrets is just an endpoint that 500s. The env var
names are already in `.env.example` and are read only inside the Edge Function,
never in the app bundle. Deploy with `supabase functions deploy storage_presign`
once the secrets are set.

**App Store Connect ([GLO-50](https://linear.app/glossed/issue/GLO-50)).** The
Sign in with Apple capability on the App ID gates
[GLO-23](https://linear.app/glossed/issue/GLO-23) (auth), which gates
[GLO-18](https://linear.app/glossed/issue/GLO-18) (onboarding).

## 10. Two agents at once works, with one rule

Two sessions ran concurrently on Aug 28 without collision. What made it work:
**claim tickets explicitly before starting, by message, and say what you are
holding on disk but have not pushed.** Use `ListAgents` to find peers and
`SendMessage` to claim. The near-miss was both sessions eyeing GLO-15 at the
same minute; one message settled it.

Worth repeating: a session that is winding down should say so and name what it
is leaving free, and one agent should not merge another's PR when that PR
touches a file class its own instructions put off-limits — merging is not
modifying, but the conservative read costs nothing.

One git habit that cost the earlier session real work twice: `git push -q` hides
a failed push, and a docs commit whose content never reached the remote merged
as an empty pointer. **Check `git show --stat HEAD` before pushing**, and check
the PR's file list after.

## 11. What is actually blocked, and on whom

Worth reading before picking anything up — three of the remaining GLO-15 pieces
are blocked on something other than effort.

| Blocked thing | On what | Who can unblock |
|---|---|---|
| `storage_presign` deploy · catalog images | R2 buckets, token, CORS, spend alert ([GLO-48](https://linear.app/glossed/issue/GLO-48)) | the Cloudflare account holder |
| GLO-15 create rung | **two** gaps in the frozen core ([GLO-60](https://linear.app/glossed/issue/GLO-60)) — see below | a human, or an agent explicitly authorized to open frozen DataKit |
| GLO-15 near-match rung's *point* | catalog images — "check the photo, not the name" is a weak instruction when the photo is a tile | same R2 chore |
| Auth, onboarding | Sign in with Apple on the App ID ([GLO-50](https://linear.app/glossed/issue/GLO-50)) | the Apple Developer account holder |

The create rung's blocker is worth knowing precisely, because it is not
obvious from the outside and it is not a missing convenience.
`createPersonalProduct` inserts a row in `products`. `ShelfRepository.log` needs
a `variantID`, and `user_items.variant_id` is `not null`. **Nothing creates the
variant** — no DataKit call, no trigger; `variants.kind` merely defaults to
`'default'` for a row nobody inserts. So the last rung of the ladder would
produce a product that cannot be logged, which is the one thing the ladder
exists to do — and it would fail *quietly*: the create succeeds, the
personal-scope badge appears, and the shelf write fails a step later on a
product that now exists and is invisible. The fix is probably a
security-definer RPC inserting both atomically, which makes it a migration
ticket as well as a DataKit one.

The near-match rung is **buildable now** and degrades honestly:
`TypographicTile` is the floor of ADR 0004's fallback chain and landed in
[#48](https://github.com/seanbrasse/glossed/pull/48) precisely so it is not the
thing holding that rung up when someone gets to it.

Also open, and higher priority than its label suggests:
[GLO-59](https://linear.app/glossed/issue/GLO-59) — the recap agent has twice
posted a test stub instead of a recap while the check went green. The recap is
the review step this project leans on, so a silent miss means a PR merges with
no review while the check mark says otherwise. Fixing it means editing a
workflow, which agents may not do.

## 12. What this session got wrong, so you don't repeat it

Three failures, all the same shape — **acting on an assumption instead of
checking**, and not saying out loud that it was an assumption.

**The design.** The kit was linked on the Linear project from the day it was
created. The 403 from `WebFetch` was taken as "unreachable" and the whole
submission ladder was built from the primitives. It opens fine in the browser
pane; `screens.jsx` reads as source. One question would have caught it.
→ [GLO-62](https://linear.app/glossed/issue/GLO-62), and §0 above.

**The handoff.** The previous session's PR added the pointer to
`docs/HANDOFF.md` without the file — a `git push -q` had failed silently and the
merge went through empty. **Check `git show --stat HEAD` before pushing, and the
PR's file list after.**

**The blockers.** GLO-15's create rung was planned three times before anyone
checked whether `CatalogRepository` could supply a `brandID` (it cannot) or
whether a created product could reach the shelf (it cannot — nothing creates the
variant, and `user_items.variant_id` is `not null`). Both were findable in a
two-minute read of the frozen core. → [GLO-60](https://linear.app/glossed/issue/GLO-60).

The counterweight worth keeping: the automated recap caught five real bugs, all
one family — *a name claiming more certainty than the code can supply*. When it
flagged something, checking it rather than agreeing with it was what found the
actual defect twice (a test that could not fail the way it claimed; a
determinism test that passed for the implementation it existed to prevent).
