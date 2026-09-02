# Next session — paste this

*Written at the close of session 20 (Sept 2 2026, daytime). The reference is
[`docs/HANDOFF.md`](HANDOFF.md); this is only the instruction. If the two
disagree, the handoff is newer.*

---

**Read `docs/HANDOFF.md` §0 before you touch anything.** Session 20 added four
hazards, and three of them failed *silently*: a phone build that signs without
the capability it needs, a keychain that survives an uninstall, and a pipeline
whose exit code was the `grep`'s.

**The rule that cost the most this session, as an imperative:** *after a device
build, check the binary's mtime and its entitlements before you install it —
`ls -la <app>/Glossed` and `codesign -d --entitlements :- <app>`.* Two
"successful" builds were signing failures and I installed the stale binary on
Sean's phone twice. And, again: *when you squash-merge a stack, retarget the
next PR to `main` BEFORE deleting the merged branch.*

## Start here

0. **Did Sean's phone make its account?** The entitled build (dev sign-in off,
   light-only, Sign in with Apple) has been on his iPhone since Sept 2 14:23,
   parked at FLOW 1. Check `auth.users` on the local stack for an `apple`
   provider row. If none: the stack must be up with `supabase functions serve`
   running and the Mac awake on the same Wi-Fi (`http://Seans-MacBook-Pro.local:54321`);
   `docker logs supabase_auth_glossed` says why a tap failed. **Done looks
   like:** an `apple` user, a `profiles` row with a handle, and the tabs on his
   phone with an empty shelf.
1. **Five PRs are open and none merged** — #495 (handoff), #496 (the stylist:
   rules first, lexicon, Sonnet 5, plan tools; base #491), #497 (the routine
   card and its door; base #494), #498 (spec §3–4; base `main`), #499 (the
   phone's own account, the entitlement, light-only, Release boot; base
   `main`). Sean merges. **Retarget #496 to `main` before #491's branch is
   deleted, and #497 before #494's.** After a squash, re-check every PR below it
   for inflation.
2. **The stylist's next builds**, in order: the lexicon grows from real misses
   (the function logs `intent` per turn — anything landing on `open` that had a
   shape is a `lexicon.ts` row, then a `lexicon_test.ts` row); STY-7's refusal
   copy is Sean's; ingredient clashes wait for an INCI table; use cases 11 and
   12 are planner intents when their data exists.
3. **TestFlight for friends** is the ask behind "can friends test it" — the code
   half is done (#499's Release boot); the rest is hosted: promote the catalog,
   deploy the functions with their secrets, an App Store Connect record. All
   Sean's, see below.
4. Then the standing chores from session 19: Shopify fill step 2 (needs slot
   0058), `supabase login`, the GLO-278 tile-preview follow-up.

## Route around these — they are blocked on Sean, not on code

- **Hosted secrets** — `ANTHROPIC_API_KEY` + `ANTHROPIC_WORKSPACE_ID` exist
  locally only (`supabase/functions/.env`; the key is personal and expires
  **Oct 2 2026**). Hosted has neither, nor the function.
- **Promoting the catalog to hosted** — needs the hosted DB URL or a CLI login.
  Without it hosted has 0 products and TestFlight is pointless.
- **The stylist's rulings** — minors (v1 adults only), refusal copy, the
  budget migration, `/design-login` for the kit frame. 08 §5 names each.
- **The product list itself** — Sean's Sept 1 listing reached the repo only as
  0057's category rows; ask where it is before building on "the new products".
- **Twilio credentials.** Phone OTP is stubbed. Apple sign-in is real.
- **Any NEW Linear issue.** The workspace is at its free issue cap. Updates and
  comments work; creates fail. Session 20's findings are on GLO-224 (the
  stylist thread) and GLO-23 (the phone's account).
- **A DataKit opening** for the one-line pin in `RankingRepository.positions()`
  (latent, no caller) and for GLO-227's chips.

## Process

- Branches `feat/GLO-<n>-desc` (also `fix/`, `chore/`, `docs/`, `test/`). PR body
  follows the template, **including the visual plan** — a paragraph is not one.
- ≤5 files / ≤400 lines, else `size-override` + a written reason. **Tests count
  as files.**
- **Never merge; Sean merges.** A merge grant is per-session and per-batch;
  none was given in session 20.
- **Never push to `main`.** `core/DataKit` and `supabase/migrations/` are frozen
  absent an explicit, in-session opening from Sean.
- The Bash cwd persists between commands: `(cd pkg && swift test)`, never a bare
  `cd`. And the shell is **zsh**: `$pipestatus` (lowercase), and `echo` mangles
  `\n` in JSON — `printf '%s'`.
- A PR cut from `main` gets `main`'s `project.yml` plus its own diff; the
  integration branch's carries the stylist stack's packages and CI cannot
  generate it.

## Tooling that fails silently — the whole reason §0 exists

- **A device build signs without the capability it needs** and exits 0; the
  Apple sheet fails at tap time. Check the built app's entitlements.
- **iOS keeps keychain items across an uninstall** — a "fresh" install can boot
  as maya. The app now signs the seeded dev user out when dev sign-in is off.
- **A `db reset` empties `storage.buckets` / `storage.objects`** while the files
  stay on the volume. `make db-reset` reconciles; a bare `supabase db reset`
  needs `./scripts/catalog_storage.sh reconcile` by hand.
- **A wedged edge runtime hangs the `you` tab ~2 min.** Probe `storage_presign`
  with `{}` — a healthy runtime answers 400 in under 100 ms. Docker is Colima:
  `LIMA_HOME=$HOME/.colima/_lima limactl stop --force colima && colima start`.
- **Photos die quietly without `supabase functions serve`.** Restart it after
  every `supabase start`; the first stylist request after a restart 502s once.
- **Never ask whether a migration landed by matching a version number.** Grep an
  object name out of the file and probe for that.
- `main` runs no CI, so two green PRs can merge into a red `main`.

## State at handoff, verified not recalled

**Zero merged, five open** (#495 #496 #497 #498 #499); every check green except
the iOS job on #499, queued behind a slow macOS runner when this was written.
Tests run at handoff: the stylist function **97** `deno test`s (12 planner, 24
tools, 61 corpus), `features/Stylist` **11**; no other package was run this
session. Local catalog: 3,206 products, 13,877 image objects, GETs `200`; the
stack was stopped and started once (to enable the Apple provider) and the
catalog survived it. Local `auth.users`: the 3 seeded rows, **no Apple account
yet**. Hosted: unchanged from session 19 — 22 categories, 0 products, 0 users,
schema through 0056, no functions, no secrets.

**Driven on the phone (Sean's iPhone 17 Pro Max, over the LAN):** the dev-user
build in light mode, and then the entitled build to FLOW 1. **Not driven:** the
Apple tap itself, onboarding as a new user, and the Release build on a device
(compiled for the simulator only).
