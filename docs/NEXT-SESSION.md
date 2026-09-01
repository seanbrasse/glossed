# Next session — paste this

*Written at the close of session 18 (Sept 1 2026). The reference is
[`docs/HANDOFF.md`](HANDOFF.md); this is only the instruction. If the two
disagree, the handoff is newer.*

---

**Read `docs/HANDOFF.md` §0 before you touch anything.** It is four hazards long
and every one of them cost a session at least once.

**The rule that cost the most last session, as an imperative:** *a migration slot
is a NUMBER, and a branch with no PR still holds its number.* Session 18 read the
warning that `feat/GLO-272-category-tree` held `0055`, then numbered a new
migration `0055` anyway. Before you create any migration file, run:

```bash
git ls-remote --heads origin | awk '{print $2}' | while read -r b; do
  git ls-tree -r --name-only "$b" -- supabase/migrations/ 2>/dev/null
done | sort -u | tail -5
```

Next free number is **0057**.

## Start here

1. **Renumber and ship the category tree.** `feat/GLO-272-category-tree` is
   pushed, green locally, and has no PR. Its migration collides with `main`'s
   `0055` — rename it to `0057` first (§0 has the commands), then open **one** PR
   with **both** commits and a `size-override`. The DataKit guard and the
   202-leaf data must land in the same squash; the data without the guard floods
   five category pickers. **Done looks like:** merged, and `categories()` still
   returning only top-level rows when driven.
2. **Get a Supabase CLI token** (`supabase login`). Every migration in session 18
   went through MCP, which stamps ledger versions that do not match repo
   filenames — the exact condition that hid GLO-274 for a session. This is a
   chore, not a feature, and it retires a whole class of bug.
3. **GLO-258** — five unaudited tables remain on the RLS OR-leak.
   `supabase/tests/database/owner_scoped_reads.test.sql` is the instrument;
   extend it rather than writing a second file. Needs no migration slot.

## Route around these — they are blocked on Sean, not on code

- **Twilio credentials.** Phone OTP is stubbed (`AccountStore.sendCode` /
  `verifyCode`). Sean deferred it explicitly. GLO-23 stays open on that half —
  its Apple half is done and shipped.
- **Any NEW Linear issue.** The workspace is at its free issue cap. *Updating*
  existing issues works; creating fails. Put new findings as comments on
  [GLO-272](https://linear.app/glossed/issue/GLO-272).
- **GLO-224** (does Discover own a search field?) — three costed answers are on
  the ticket, waiting on a product call.

## Process

- Branches `feat/GLO-<n>-desc` (also `fix/`, `chore/`, `docs/`, `test/`). PR body
  follows the template, **including the visual plan** — a paragraph is not one.
- ≤5 files / ≤400 lines, else `size-override` + a written reason.
- **Never merge; Sean merges.** A merge grant is per-session and per-batch — do
  not infer one from a previous session's.
- **Never push to `main`.** `core/DataKit` and `supabase/migrations/` are frozen
  absent an explicit, in-session opening from Sean.

## Tooling that fails silently — the whole reason §0 exists

- **Photos die quietly without `supabase functions serve`.** No error; the app
  renders honest placeholders. Restart it after every `supabase start`.
- **A red package is a stale `.build` cache until proven otherwise.** It breaks
  packages *downstream* of the one you changed and blames a file they do not
  touch. Session 18 lost 7 of 18 packages to this; all passed untouched after
  `rm -rf .build`.
- **Never ask whether a migration landed by matching a version number.** Grep an
  object name out of the file and probe for that.
- `main` runs no CI, so two green PRs can merge into a red `main`. If a PR fails
  lint on a file it did not modify, check `main` first.

## State at handoff, verified not recalled

**914 tests passing across all 18 packages.** `main` is at `e980569`. Three PRs
open, none from session 18: [#431](https://github.com/seanbrasse/glossed/pull/431),
[#430](https://github.com/seanbrasse/glossed/pull/430),
[#402](https://github.com/seanbrasse/glossed/pull/402). Hosted Supabase is
current through migration 0056 and essentially empty — 22 categories, 0 products,
0 profiles, 0 auth users.

**Unverified, and worth knowing:** nothing in session 18 was driven against
hosted with a real signed-in user, because hosted has no users. Sign in with
Apple was driven on Sean's phone against the **local** stack only.
