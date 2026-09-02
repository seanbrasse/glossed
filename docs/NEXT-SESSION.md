# Next session — paste this

*Written at the close of session 19 (Sept 2 2026). The reference is
[`docs/HANDOFF.md`](HANDOFF.md); this is only the instruction. If the two
disagree, the handoff is newer.*

---

**Read `docs/HANDOFF.md` §0 before you touch anything.** It is six hazards long
now, and the two new ones both failed *silently* for a day.

**The rule that cost the most last session, as an imperative:** *when you
squash-merge a stack, retarget the next PR to `main` BEFORE deleting the merged
branch — GitHub closes a PR whose base vanishes, it does not retarget it.*

Three more, each of which cost real time in session 19:

- *`wc -l` a file before you add to it* — the 300-line ceiling has now bitten
  three sessions, this time on `KitIcons.swift`, and CI is the only thing that
  says so.
- *Find out what the environment is before you "fix" it* — the daemon here is
  **Colima**, not Docker Desktop; `docker context show` before any surgery.
- *A `db reset` drops the catalog's image index* — `make db-reset` now runs
  `scripts/catalog_storage.sh reconcile` for you (#479); after a bare
  `supabase db reset`, run it by hand.

## Start here

0. **The stylist is rules first, model last — and works without a key.**
   Sean, Sept 2: *"as little AI as possible — searching, filtering, looking at
   data and making comparisons."* Three PRs open on top of the stack: **#496**
   (`plan.ts` — routine / missing / try next / compare / about from the shelf
   and the cohort RPCs, zero model calls; `model.ts` only for a free-form
   question when a key exists; base #491), **#497** (the routine card wears the
   detail's shape, a save offers *open it* and trips the profile reload; base
   #494), **#498** (`08-stylist.md` §4; base `main`). **Retarget #496 and #497
   to `main` BEFORE their base branches are deleted.** Driven live as maya with
   no key: morning routine → save → open it → edit → on the profile. **The key
   exists now** — Sean created `glossed-stylist-local` in the console (a
   *personal*, identity-linked key; expires Oct 2 2026); it lives ONLY in
   `supabase/functions/.env` as `ANTHROPIC_API_KEY` plus
   `ANTHROPIC_WORKSPACE_ID`, which a personal key needs on every request
   (`400 anthropic-workspace-id is required` without it — #496 sends it).
   The free-form path was driven: 200 in 8s, a routine card of maya's items.
   Hosted still has no secret. **Later that day:** the fallback runs
   **Sonnet 5** (bake-off in 08 §3; `STYLIST_MODEL` overrides), and #496
   grew `lexicon.ts` — how people phrase beauty asks, learned offline,
   matched at zero tokens — with a 60-row corpus in `lexicon_test.ts`, a
   `look` intent, and the plans offered to Sonnet as tools. **The pattern:**
   a real phrasing that lands on `open` but had a shape is a lexicon row,
   then a corpus row. Never a runtime model. Next builds: STY-7 (refusal copy is Sean's),
   ingredient clashes once an INCI table exists, use cases 11 and 12 as planner
   intents.

1. **Step 1 of the Shopify fill is done (#488).** The rules and the backfill
   are in; `make db-reset` restores the catalog from the snapshot, which was
   taken AFTER the backfill, so nothing to re-run locally. Hosted has no
   catalog yet.
2. **Step 2 needs migration 0058** — `products.leaf_id` plus a
   `product_type → leaf` map (1,277 of 2,202 Shopify types match a leaf label),
   and `search_catalog`'s `attrs` folding in the leaf slug. Ask for the slot.
3. **Drive the two GLO-278 paths not yet driven** — a routine and a look saved
   from `+`, then on the profile without leaving the tab.
4. Then the standing chores: `supabase login`; the profile follow-ups on
   GLO-278's comment (resolve tile previews after the lists render, with a
   timeout).

## Route around these — they are blocked on Sean, not on code

- **Hosted secrets** — `ANTHROPIC_API_KEY` + `ANTHROPIC_WORKSPACE_ID` exist locally only; setting them on the hosted project is Sean's.
- **The stylist's rulings** — minors (v1 adults only), refusal copy, the
  budget migration, `/design-login` for the kit frame. 08 §5 names each.
- **The product list itself** — Sean's Sept 1 listing reached the repo only as 0057's category rows; ask where it is before building on "the new products".
- **A CLI token or the hosted DB URL** — no migration can be pushed properly and
  no catalog can be promoted without one.
- **Twilio credentials.** Phone OTP is stubbed. GLO-23's Apple half is done.
- **Any NEW Linear issue.** The workspace is at its free issue cap. Updates and
  comments work; creates fail. Session 19 put findings on GLO-223, GLO-224 (the
  Stylist's whole ticket thread), GLO-256, GLO-258, GLO-272, GLO-278.
- **A DataKit opening** for the one-line pin in `RankingRepository.positions()`
  (latent, no caller) and for GLO-227's chips.

## Process

- Branches `feat/GLO-<n>-desc` (also `fix/`, `chore/`, `docs/`, `test/`). PR body
  follows the template, **including the visual plan** — a paragraph is not one.
- ≤5 files / ≤400 lines, else `size-override` + a written reason. **Tests count
  as files** — #478 went red on exactly this.
- **Never merge; Sean merges.** A merge grant is per-session and per-batch.
- **Never push to `main`.** `core/DataKit` and `supabase/migrations/` are frozen
  absent an explicit, in-session opening from Sean.
- The Bash cwd persists between commands: `(cd pkg && swift test)`, never a bare
  `cd`.

## Tooling that fails silently — the whole reason §0 exists

- **A `db reset` empties `storage.buckets` / `storage.objects`** while the files
  stay on the volume. Photos become placeholders with no error. `./scripts/catalog_storage.sh count` says whether you are in that state.
- **A wedged edge runtime hangs the `you` tab ~2 min**, then it renders without
  previews. Probe `storage_presign` with `{}` — a healthy runtime answers 400 in
  under 100 ms. If it hangs: `docker ps -a --filter name=edge`; a container stuck
  in `Created` means the daemon is wedged → `LIMA_HOME=$HOME/.colima/_lima limactl stop --force colima && colima start`
  (`colima restart` and `colima stop -f` both hang on it).
- **Photos die quietly without `supabase functions serve`.** Restart it after
  every `supabase start`.
- **A red package is a stale `.build` cache until proven otherwise.**
- **Never ask whether a migration landed by matching a version number.** Grep an
  object name out of the file and probe for that.
- `main` runs no CI, so two green PRs can merge into a red `main`.

## State at handoff, verified not recalled

**Fifteen merged in session 19** (#479 #476 #477 #478 #402 #483 #430 #431 #481
#482 #485 #486 #487 #488 #490) and **four open at handoff, merging under the
grant as CI goes green**: #491 #492 #493 (the stylist's function, glyph and
package) and #494 (the tab — stacked on the other two; rebase it onto `main`
after they squash, then merge). `main` was verified after #488: swiftformat and
swiftlint clean, `xcodebuild build` for the simulator green, `swift test` green
in `core/DataKit`, `features/Profile`, `features/Collections`; the other 15
packages were not run. GLO-278, GLO-267, GLO-264 moved to Done. Local catalog: 3,206 products, 13,877
image objects registered, GETs `200`. Hosted: 22 categories, **0 products, 0
images, 0 buckets, 0 users**, schema through 0056.

**Unverified, and worth knowing:** #479's `db reset` round-trip was not run (a
reset takes the local drive data out from under Sean's phone). The next reset
is the first real test of both the bucket declaration and nadia's seed.
