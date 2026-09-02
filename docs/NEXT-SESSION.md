# Next session — paste this

*Written at the close of session 22 (Sept 2 2026, evening). The reference is
[`docs/HANDOFF.md`](HANDOFF.md); this is only the instruction. If the two
disagree, the handoff is newer.*

---

**Read `docs/HANDOFF.md` §0 and "Session 22 at a glance" before you touch
anything.** Zero PRs are open. Twenty-one merged tonight; `main` is `4ef961e`
and Sean's phone runs it.

**The rule that cost the most this session, as an imperative:** *after
`git rebase --onto`, read the commits that survived and the diff of any file
the merged-away base also touched — a history that adds a thing and later
removes it replays as a removal once the addition is upstream.* #499's rebase
silently dropped the `Stylist` package from `project.yml`; lint and size
passed; the phone build's stale-binary guard was the only thing that said no.
And: *wait for the iOS job, not just lint, on any PR that touches
`project.yml` or a `Package.swift`.*

## Start here

1. **Ask Sean what his phone showed** for #508 (Apple through "create an
   account" as an existing account → discover, nothing re-asked) and #509
   (the handle step carrying on with `@seantest`), and whether one product
   logged as him. Only his phone can drive those. **A merge grant is
   per-session — do not assume tonight's carries.**
2. **If he sends more onboarding notes,** the shape that worked: one note =
   one branch off `main`, `GLO-108` in the name, the note quoted in the PR,
   driven on the simulator with `SIMCTL_CHILD_GLOSSED_ONBOARDING=1` before
   pushing. Ticket bodies go on GLO-108 as a comment (Linear refuses creates).
3. **Then the standing chores:** Shopify fill step 2 (slot 0058), `supabase
   login`, the stylist's lexicon growth from real misses, STY-8 then SAV-2 when
   the slot frees, and the thirteen packages not re-run tonight (`make test`).
4. Housekeeping: `phone/sep-2-onboarding` in the main checkout is superseded
   by `main` and can be deleted.

## Route around these — blocked on Sean, not on code

- **Any merge** without a fresh grant.
- **Any new Linear issue.** Comment on GLO-108 (onboarding), GLO-224 (stylist,
  saves) or GLO-23 (the phone's account).
- **A real Apple ID** for #508/#509 — only Sean's phone can drive them.
- **Hosted secrets, the catalog promotion, TestFlight** — all his.
- **The migration slot** — STY-8 then SAV-2 are queued behind it.
- **The payoff's picks** — whether to draw from the leaderboard later is his.

## Process

- Branches `feat/GLO-<n>-desc` (`fix/`, `chore/`, `docs/`). PR body follows the
  template including the visual plan. ≤5 files / ≤400 lines or `size-override`
  with a reason; tests count as files.
- Never push to `main`; `core/DataKit` and `supabase/migrations/` are frozen
  absent an in-session opening.
- **Squashing a stack:** snapshot every branch tip first; `git checkout --detach
  origin/<branch> && git rebase --onto origin/main <old-base-tip>`, push with
  `--force-with-lease`, retarget, read the surviving commits, merge, repeat.
  §3 has the loop.
- **Edit scripts anchor on raw text.** zsh: `$pipestatus`, `printf '%s'` for
  JSON; `(cd pkg && swift test)`; `for pair in "a b"` does not word-split —
  use `${pair%% *}` / `${pair##* }`. Never `source` a `sed` range of a script.
- The simulator drive: `make run`, then relaunch with
  `SIMCTL_CHILD_GLOSSED_ONBOARDING=1` to see FLOW 1; the phone: the
  `phone-build.sh` shape (build, mtime check, entitlement check, `strings` on
  `Glossed.debug.dylib`, `devicectl install`, launch) is in §0 and §3.

## Tooling that fails silently

- **A stale `.swiftmodule` in DerivedData satisfies an import for a package the
  project no longer links.** The failure arrives at link time as undefined
  symbols, not at compile time as a missing module.
- `swift test` has two summary shapes (`Executed N tests` / `Test run with N
  tests in M suites passed`); a filter for one reads the other as zero.
- Everything session 21 listed: a `.task` on a zero-size view, a `View`'s
  static helper in a task group, a package asset catalog on an incremental
  build, the void builds, the keychain across uninstall, `db reset` emptying
  storage buckets, the wedged edge runtime.

## State at handoff, verified not recalled

**Zero open, twenty-one merged** (#491–#511). `main` `4ef961e`: swiftlint and
swiftformat clean; simulator build green, fresh dylib; Onboarding 78, Profile
106, DesignSystem 54, Stylist 11, Tracking 16; the stylist function's 97 deno
tests; FLOW 1 driven from `main` on the simulator (hook → quiz → tone →
payoff bay with images → *create your account*). The other thirteen packages
were not re-run. Sean's phone: the 18:00 build of the #511 tree, entitlement
and dev-sign-in-off proven, launched. Local stack up, `supabase functions
serve` running (pid from the `glo-145-fitsection-gate` worktree, with the
stylist key in its `.env`). Hosted: unchanged — 0 products, 0 users, no
functions, no secrets.

**Not driven:** #508 and #509 with a real Apple ID (Sean), #504's
after-recording, the stylist tab on `main` (built and linked; not opened
tonight).
