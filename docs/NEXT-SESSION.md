# Next session — paste this

*Written at the close of session 19 (Sept 2 2026). The reference is
[`docs/HANDOFF.md`](HANDOFF.md); this is only the instruction. If the two
disagree, the handoff is newer.*

---

**Read `docs/HANDOFF.md` §0 before you touch anything.** It is six hazards long
now, and the two new ones both failed *silently* for a day.

**The rule that cost the most last session, as an imperative:** *before you
"fix" the environment, find out what the environment is.* Session 19 quit an app
named Docker that does not exist on this machine (the daemon is **Colima**) and
read the daemon's unchanged answer as a successful restart. `docker context show`
before any daemon surgery. And: **a `db reset` drops the catalog's image index**
— after any reset, `./scripts/catalog_storage.sh reconcile`, until #479 merges
and `make db-reset` does it for you.

## Start here

1. **Get the six PRs reviewed and merged, in this order.** Nothing merged in
   session 19 (Sean was away), so `main` is still `9be4ede` and everything is
   waiting. Merge order matters for one stack:
   - **#479** catalog images survive a reset (standalone)
   - **#476** the category tree, migration **0057** (standalone, `size-override`)
   - **#477** GLO-258's last five tables (standalone; #430 touches the same file)
   - **#478 → #480 → #481** profile reloads in place → shell tells it → tabs keep
     their state. **In that order**, re-checking each diff's size after the one
     above it squashes (the inflation shape, §0).
   **Done looks like:** `main` builds and launches signed-in, product photos
   render on the shelf, switching tabs does not blank a screen, and a collection
   saved from `+` appears on the profile without leaving the tab.
2. **The proof session 19 owed and did not make**, in the simulator: the
   GLO-278 acceptance (save a collection → it is on the profile, no spinner over
   a correct list). GLO-256's recording is done and on the ticket. Next free
   migration number is **0058** — you do not need it.
3. **Ask Sean where his product list is** before doing anything about "the new
   products". What landed is a taxonomy (categories only, PR #476); no product
   row came through, and the raw list is not in the repo.
4. Then the standing chores: `supabase login` (retires the ledger-mismatch bug
   class **and** unblocks promoting the catalog to hosted, which has 0 products);
   the profile follow-ups on GLO-278's comment (resolve tile previews after the
   lists render, with a timeout).

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

`main` at `9be4ede`, unchanged since session 18. **Nine PRs open**: six from
session 19 ([#476](https://github.com/seanbrasse/glossed/pull/476),
[#477](https://github.com/seanbrasse/glossed/pull/477),
[#478](https://github.com/seanbrasse/glossed/pull/478),
[#479](https://github.com/seanbrasse/glossed/pull/479),
[#480](https://github.com/seanbrasse/glossed/pull/480),
[#481](https://github.com/seanbrasse/glossed/pull/481)) and the older three
([#431](https://github.com/seanbrasse/glossed/pull/431),
[#430](https://github.com/seanbrasse/glossed/pull/430),
[#402](https://github.com/seanbrasse/glossed/pull/402)). Tests actually run this
session: `core/DataKit` **134**, `features/Profile` **106**; the other 16
packages were not touched and not run. Local catalog: 3,206 products, 13,877
image objects registered, GETs `200`. Hosted: 22 categories, **0 products, 0
images, 0 buckets, 0 users**, schema through 0056.

**Unverified, and worth knowing:** #479's `db reset` round-trip was not run (a
reset takes the local drive data out from under Sean's phone). #481's retention
was driven once, in the simulator, while the daemon was restarting under it,
and recorded (163 frames, four switches, every one a cross-dissolve of two
laid-out screens — GLO-256 comment).
