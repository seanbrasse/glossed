# Next session — paste this

*Written at the close of session 21 (Sept 2 2026, evening). The reference is
[`docs/HANDOFF.md`](HANDOFF.md); this is only the instruction. If the two
disagree, the handoff is newer.*

---

**Read `docs/HANDOFF.md` §0 and "Session 21 at a glance" before you touch
anything.** Twenty PRs are open, none merged, and they stack six deep.

**The rule that cost the most this session, as an imperative:** *before you
drive a build, prove it is the build you think it is — chain edit and build
with `&&`, grep the whole log for ` error: `, compare the binary's mtime to the
build's start, and `strings Glossed.app/Glossed.debug.dylib` for a string you
just added.* Three "successful" simulator builds were void and I debugged a
stale binary for twenty minutes. And: *a phone build is the union of every open
stack* — the first one of the day dropped the stylist and Sean noticed.

## Start here

1. **Nothing merges until Sean grants it.** When he does, the order is in the
   handoff: #500 → #502 → #503 → #506 → #508 → #509 as one stack, retargeting
   each to `main` before its base is deleted; #505 on #500; #501, #504, #507,
   #510 straight in; then the stylist stack and #499. Squash-merging a stack
   inflates every PR below it — re-check file lists after each merge.
2. **Sean's phone has everything** (`phone/sep-2-onboarding`, local, not a PR).
   What he has not yet been able to try: signing in with Apple through "create
   an account" as an existing account (#508 — should land on discover with
   nothing re-asked) and the handle step carrying on with `@seantest` (#509).
   **Done looks like:** he reports both, and one product logged as him.
3. **If he sends more onboarding notes,** the shape that worked: one note = one
   branch off the right base, `GLO-108` in the name, the note quoted in the PR,
   driven on the simulator with `GLOSSED_ONBOARDING=1` before pushing. Ticket
   bodies go on GLO-108 as a comment (Linear refuses creates).
4. **Then the standing chores:** Shopify fill step 2 (slot 0058), `supabase
   login`, the stylist's lexicon growth from real misses, and the saves spec's
   SAV-2 when the slot frees.

## Route around these — blocked on Sean, not on code

- **Any merge.** No grant in session 21.
- **Any new Linear issue.** Three refusals today. Comment on GLO-108 (onboarding),
  GLO-224 (stylist, saves) or GLO-23 (the phone's account).
- **A real Apple ID** for #508/#509 — only Sean's phone can drive them.
- **Hosted secrets, the catalog promotion, TestFlight** — unchanged from
  session 20; all his.
- **The migration slot** — STY-8 then SAV-2 are queued behind it.
- **The payoff's picks** — curated by me; whether to draw from the leaderboard
  later, or change the twelve, is his.

## Process

- Branches `feat/GLO-<n>-desc` (`fix/`, `chore/`, `docs/`). PR body follows the
  template including the visual plan. ≤5 files / ≤400 lines or `size-override`
  with a reason; tests count as files.
- Never merge; never push to `main`; `core/DataKit` and `supabase/migrations/`
  are frozen absent an in-session opening.
- **Edit scripts anchor on raw text.** Three of today's scripted edits asserted
  on text read with `grep -v "///"` and silently missed. Read the raw file.
- zsh: `$pipestatus`, `printf '%s'` for JSON; `(cd pkg && swift test)`.
- The simulator drive: `make run`, then relaunch with
  `SIMCTL_CHILD_GLOSSED_ONBOARDING=1` to see FLOW 1; the phone:
  `scratchpad/phone-build.sh`'s shape — build, mtime check, entitlement check,
  `devicectl install`, launch — is in the handoff §0.

## Tooling that fails silently

- A `.task` on a zero-size SwiftUI view never runs. Reserve height while loading.
- A `View`'s static helper called from a `withTaskGroup` child crashes with
  `dispatch_assert_queue_fail`. Mark the loader and its helpers `nonisolated`.
- A new package asset catalog does not reach `Glossed.app` on an incremental
  build: `rm -rf Products/…/Glossed.app/<Package>_<Target>.bundle`, rebuild.
- Everything session 20 listed: unsigned device builds, the keychain across
  uninstall, `db reset` emptying storage buckets, the wedged edge runtime, the
  first stylist request after a `functions serve` restart.

## State at handoff, verified not recalled

**Zero merged, twenty open** (#491–#510). Tests run today, on the branch named:
Onboarding 78 (#509), Profile 106 (#504), DesignSystem 54 (#505). No function
tests run this session. Local stack up, `supabase functions serve` running from
the `glo-145-fitsection-gate` worktree with `ANTHROPIC_API_KEY` +
`ANTHROPIC_WORKSPACE_ID` in its `.env` (this worktree's `.env` has neither —
the server, not the checkout, is what the phone talks to). Sean's phone: the
15:45 build, stylist included, confirmed by `strings` on the debug dylib.
Hosted: unchanged — 0 products, 0 users, no functions, no secrets.

**Driven on the simulator:** the tap targets, sign-out to the hook, the tone
quiz, the payoff's bay, the hair strands and their selected state, the profile
skeleton. **Driven by Sean on his phone:** the first two phone builds (his
notes came from them). **Not driven:** #508 and #509 with a real Apple ID,
#504's after-recording, the copy sweep on a device.
