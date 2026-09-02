# Next session — paste this

*Written at the close of session 19 (Sept 2 2026). The reference is
[`docs/HANDOFF.md`](HANDOFF.md); this is only the instruction. If the two
disagree, the handoff is newer.*

---

**Read `docs/HANDOFF.md` §0 before you touch anything.** It is six hazards long
now, and the two new ones both failed *silently* for a day.

**The rule that cost the most last session, as an imperative:** *when you
squash-merge a stack, retarget the next PR to `main` BEFORE deleting the merged
branch — GitHub closes a PR whose base vanishes, it does not retarget it.* And:
*before you "fix" the environment, find out what the environment is.* Session 19 quit an app
named Docker that does not exist on this machine (the daemon is **Colima**) and
read the daemon's unchanged answer as a successful restart. `docker context show`
before any daemon surgery. And: **a `db reset` drops the catalog's image index**
— after any reset, `./scripts/catalog_storage.sh reconcile`, until #479 merges
and `make db-reset` does it for you.

## Start here

1. **Fill the new categories from Shopify — step 1, no migration.** Ten of
   0057's top-level groups hold 0 products while ~170 Shopify products in the
   catalog belong in them (the table in `HANDOFF.md` §1). Add the ten groups to
   `TYPE_RULES` in `scripts/shopify_import.ts` (order matters), and reclassify
   the existing rows with the same regexes in SQL — the importer's insert is
   `on conflict do nothing`, so a re-run alone changes nothing. Check
   `rank_positions` for affected items first: moving a product moves its
   ladder. **Done looks like:** `select slug, count(*)` per top-level category
   shows lipcare ≈ 83, tools ≈ 37, exfoliant ≈ 25, body ≈ 20, and the shelf
   still renders every seeded item in a category.
2. **Step 2 needs migration 0058** — `products.leaf_id` plus a
   `product_type → leaf` map (1,277 of 2,202 Shopify types match a leaf label),
   and `search_catalog`'s `attrs` folding in the leaf slug. Ask for the slot.
3. **Drive the two GLO-278 paths not yet driven** — a routine and a look saved
   from `+`, then on the profile without leaving the tab.
4. Then the standing chores: `supabase login`; the profile follow-ups on
   GLO-278's comment (resolve tile previews after the lists render, with a
   timeout).

## Route around these — they are blocked on Sean, not on code

- **The product list itself** — see 3 above.
- **A CLI token or the hosted DB URL** — no migration can be pushed properly and
  no catalog can be promoted without one.
- **Twilio credentials.** Phone OTP is stubbed. GLO-23's Apple half is done.
- **Any NEW Linear issue.** The workspace is at its free issue cap. Updates and
  comments work; creates fail. Session 19 put findings on GLO-223, GLO-256,
  GLO-258, GLO-272, GLO-278.
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

**Zero PRs open.** Ten merged in session 19 (#479 #476 #477 #478 #402 #483
#430 #431 #481 #482), `main` verified after the last one: swiftformat and
swiftlint clean, `xcodebuild build` for the simulator green, `swift test` green
in `core/DataKit`, `features/Profile`, `features/Collections`; the other 15
packages were not run. GLO-278, GLO-267, GLO-264 moved to Done. Local catalog: 3,206 products, 13,877
image objects registered, GETs `200`. Hosted: 22 categories, **0 products, 0
images, 0 buckets, 0 users**, schema through 0056.

**Unverified, and worth knowing:** #479's `db reset` round-trip was not run (a
reset takes the local drive data out from under Sean's phone). The next reset
is the first real test of both the bucket declaration and nadia's seed.
