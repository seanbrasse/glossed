# Next session — paste this

*Written at the close of session 22 (Sept 2 2026, evening). The reference is
[`docs/HANDOFF.md`](HANDOFF.md); this is only the instruction. If the two
disagree, the handoff is newer.*

---

**Read `docs/HANDOFF.md` §0 and the four "Session 22" blocks before you
touch anything.** Zero PRs are open. Thirty-five merged tonight; Sean's phone
runs `main` at #527, and `functions serve` runs from the
`glossed-phase-1-1fbaa3` worktree at `main`.

**The rule that cost the most this session, as an imperative:** *after
`git rebase --onto`, read the commits that survived and the diff of any file
the merged-away base also touched — a history that adds a thing and later
removes it replays as a removal once the addition is upstream.* #499's rebase
silently dropped the `Stylist` package from `project.yml`; lint and size
passed; the phone build's stale-binary guard was the only thing that said no.
And: *wait for the iOS job, not just lint, on any PR that touches
`project.yml` or a `Package.swift`.*

## Start here

1. **Ask Sean what his phone showed for #508** (Apple through "create an
   account" as an existing account → discover, nothing re-asked). #509 is
   confirmed by his screenshot (`@seantest` on his profile) and he has two
   items logged. Then the new sheets on his phone: the shade sheet's
   `swipe up for more`, the item sheet without `full page`. **A merge grant is
   per-session — do not assume tonight's carries.**
2. **If he sends more onboarding notes,** the shape that worked: one note =
   one branch off `main`, `GLO-108` in the name, the note quoted in the PR,
   driven on the simulator with `SIMCTL_CHILD_GLOSSED_ONBOARDING=1` before
   pushing. Ticket bodies go on GLO-108 as a comment (Linear refuses creates).
3. **Two fixtures worth adding** to the debug catalog: an empty shelf and an
   empty profile (tonight they were driven as juli on a throwaway branch —
   see the second "Session 22" block).
4. **Then the standing chores:** Shopify fill step 2 (slot 0058), `supabase
   login`, the stylist's lexicon growth from real misses, STY-8 then SAV-2 when
   the slot frees, and the thirteen packages not re-run tonight (`make test`).
5. Housekeeping: `phone/sep-2-onboarding` in the main checkout is superseded
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
- **`deno fmt --line-width=100`, always** — the bare default is 80 and does
  not undo itself. **End a chain on the command whose status matters**, not
  on `grep`.
- **Edit scripts anchor on raw text, with `^`-anchored regexes** — an
  indented line is a substring of its deeper twin — **and the chain ends on
  the script's exit code.** zsh: `$pipestatus`, `printf '%s'` for
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

**Zero open, thirty-five merged** (#491–#527). `main` at #527: swiftlint and
swiftformat clean; simulator build green, fresh dylib; Onboarding 78, Profile
108, DesignSystem 54, Stylist 11, Tracking 16, Shelf 144, AddLadder 125,
ProductPage 22; the stylist function's 97 deno
tests; FLOW 1 driven from `main` on the simulator (hook → quiz → tone →
payoff bay with images → *create your account*). The other thirteen packages
were not re-run. Sean's phone: the build of `main` at #527, entitlement
and dev-sign-in-off proven, launched. Local stack up, `supabase functions
serve` running (pid from the `glo-145-fitsection-gate` worktree, with the
stylist key in its `.env`). Hosted: unchanged — 0 products, 0 users, no
functions, no secrets.

**Not driven:** #508 with a real Apple ID (Sean), #504's after-recording,
the stylist tab on `main` (built and linked; not opened tonight), the new
sheets on a phone.
