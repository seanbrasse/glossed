# Session handoff — Aug 29–30 2026 (session 12: the sweep finished, the discover loop closed, and a harness that could not reach its own bug class)

Where Phase 1 stands, what to do next, and what this session learned. Read
`docs/README.md` first for the design; this file is only about state.

**Up to three lanes ran concurrently and all merged into main.** This file is
now written by more than one of them, and each section says whose work it
describes. The **Phase-1 journal lane** owns shelf, sheet, product page, ladder
and the state sweep; the **Phase-1.5 / taste lane** owns migrations, DataKit
reads, discover and browse; the **onboarding lane** (Aug 30 daytime) owns
leaderboard UI, the GLO-18 flow, tune, and the kit nav; the **feed lane**
(Aug 30 late) owns §-1. **Do not speak for a lane that is not yours** — and
before editing this file, check whether someone else already updated the same
row, because on Aug 30 two lanes refreshed it within the hour (and this
version was written on top of the feed lane's PR before it merged, for the
same reason).

**The journal lane finished GLO-110.** The grid is at 34 cells; every named cell
from the previous round is driven. It filed five issues and closed four in the
same stretch — [#276](https://github.com/seanbrasse/glossed/pull/276) (the
grid), [#280](https://github.com/seanbrasse/glossed/pull/280) (GLO-176 +
GLO-177), [#284](https://github.com/seanbrasse/glossed/pull/284) (GLO-180),
[#286](https://github.com/seanbrasse/glossed/pull/286) (GLO-179). One is left,
[GLO-178](https://linear.app/glossed/issue/GLO-178), waiting on Sean because the
question inside it is a product call, not a code one.

## -1. The feed epic — what the late session built (read this before touching Discover, Looks, Media, or 0043)

**Sean's direction moved twice on Aug 30, both first-hand:** the feed is in V1
(deltas 11–14, `tech/00`), and then *discovery is incorporated into the feed —
there is no separate feed surface* (delta 15). The late session built
everything code alone could deliver:

| Merged | What |
|---|---|
| #314 | Discover is the feed's STREAM — one scroll of self-labeling cards, no sections ("a sectioned page of product cards is a store's shape") |
| #318 | Migration **0043**: `looks`/`look_photos`/`look_tags`. Minor deny in the INSERT policies via `can_post_look()`; public read = `state='public' AND can_view(owner,'looks') AND not blocked`, fail-closed on unknown states. 16 pgTAP assertions |
| #320 | The stream's **injected card slots** — features never import features, so the app composes (the FitPromptCard answer, generalized). Position = final index, ties by id, deterministic. The onboarding lane's tune card is its first consumer |
| #324, #327 | `features/Looks`: the composer, model + UI, four picker states driven against promises written first. A failed save loses NOTHING |
| #330 | **`core/Media` EXISTS** (GLO-148 closed by building it): `PhotoPreparer` (screen → strip-by-omission → bound → JPEG; the strip test proves the fixture carried GPS first) and `PresignedUploader` (deliberately dumb). The SCA seam FAILS CLOSED — a checker that errors blocks |
| #333 | `LooksRepository` under Sean's session opening (spent, expired). Idempotency = client-minted PRIMARY KEY (the first draft invented a `client_id` column 0043 doesn't have — diff against the real migration, always) |
| #334 | `storage_presign`'s third namespace: `look_id` + `position`. Same-predicate-as-policy; one byte-identical 403 (no minor-status oracle); **per-kind content types** — looks take jpeg, cutouts keep png/heic because alpha is the shelf's whole look |

**What the pipeline can and cannot do:** a composer draft flows prepare →
presign → PUT → rows, end to end, idempotently. It cannot SHOW anyone
anything: nothing moves a look to `public` until image moderation exists
(GLO-26, V1-Urgent, vendor is Sean's) — and no copy anywhere promises a
review that is not built (GLO-189's law).

**Open on the epic:** GLO-196 + GLO-200's look-card half (blocked on GLO-26 +
the tab-name/composition rulings; carries GLO-205's body-facts constraint —
never a literal value, match-or-nothing, badge opt-in only). The composer has
no app entry point yet — deliberate; it rides the look-card slice. `searchShelf`
answers empty until the tag-picker sheet lands.

**Sweep-loop note:** the package count is now **16** (Media, Looks, Onboarding,
Leaderboard, Browse all landed inside 24h) and the test total was **644 at
`4aeca47`**. The §9 glob loop found every one of them unaided. Do not trust
either number; re-measure.

## 0. Read this first

**Nothing forces `supabase_migrations.schema_migrations` to agree with the
schema, and on Aug 29 it did not** — the tracker read **29** while the schema
was at **40**. It has since been reconciled (40 tracked, latest
`20260829000040`, against 40 files — checked file by file), so you should find
them in agreement. Treat that agreement as a convenience, not a guarantee.

**The cause is a habit, not a lane.** Applying a migration with
`docker exec … psql < file` (or any direct psql path) does not stamp the
tracker; `supabase migration up` does. Two sessions did this independently on
the same night — 0030–0034 from one lane, 0035–0040 from the other — which is
the point: it is the default behavior of anyone applying by hand, not one
session's quirk. If you apply DDL directly, stamp it, or say so.

**The ordering matters more than the fix.** What established the schema's real
state was evidence: probing `pg_proc` for the object names *grepped out of the
migration files*, and running `discover_rpcs.test.sql` (12 assertions, pass)
against the very migration the tracker claimed was missing. Stamping came
after, and only made the bookkeeping agree with what was already known.
**Bookkeeping is not proof; the probe was.**

**I got this backwards first, and the error shipped in this file's §0** —
worth keeping because it is cheap to repeat. I read 29-against-40, probed
`pg_proc` for `discover_feed` and `refresh_agg_variant_stats`, got zeros, and
concluded eleven migrations were unapplied. **Both names were invented rather
than read out of the migration files** — the real ones are
`discover_for_user` and `refresh_variant_stats`, and all eleven late objects
were present the whole time. **A wrong name in a `count(*)` returns 0 and
reads exactly like absence.** That is session 8's `queued`/`pending` scar in a
new costume, and it was worse here for landing in §0, where it told every
future session to distrust a good pgTAP baseline (546 assertions / 1 known
failure, `shelf_view` 14) and burn ~50 minutes on a reset it did not need.
**Grep the object name out of the file before you query for it.**

**"Verify before you file" has a second half that cost more than the first: a
red you dismiss is a defect you own.** This stretch talked itself out of five
false defects (a stale `.build` cache, an unreachable scrim that was really a
status-bar tap, a "regression" that was a peer's migration, a page mock that
was a missing field, and an import "add 4" affordance that turned out to be
unbuilt-by-design) — and in the same stretch the 1.5 lane discovered that
`shelf_isolation` test 4, which **three sessions had agreed to treat as
drive-drift**, had been correctly reporting GLO-145's view leak the whole
time. It was the only thing in the repo detecting it.

So the rule runs both ways. Check before you file, **and** check before you
dismiss. "Known failure" is a claim that needs the same evidence as "new bug",
and a shared assumption is the easiest place for one to hide.

**"Verify before you dismiss" has a third face, and it nearly cost the journal
lane its best finding: a PLAUSIBLE OUTPUT stops you examining the input.**
Driving the near-match rung's name field I typed twenty-two characters, got
three candidates, and moved on — it looked exactly like success. It was not.
The field had deleted itself after the *first* keystroke and the search ran on
one letter; the stub returned the same three matches for any non-empty query, so
a broken input wore the shape of a working screen. Typing a single `l` is what
made it visible (GLO-176).

That is session 8's `queued`/`pending` and session 11's fabricated migration
deficit in a third costume, and the taste lane hit a fourth the same night
(fixtures that all satisfied a precondition could not tell that the precondition
was load-bearing — §8, GLO-173). All four share one move: a result that looked
right stopped the check. **When a fixture cannot vary its answer, its answer is
not evidence — it only tells you the screen did something.** Give a state the
SMALLEST input that should work rather than a realistic one, and prefer fixtures
whose output depends on their input (`ladder · the whole trip`'s stub filters on
the query for exactly this reason).

**Another session driving the SAME simulator will swap your binary out from
under you, silently.** On Aug 30 the foreground app became a live catalog
product page mid-sweep. No crash log, nothing in my own transcript to explain
it — it was another lane's `simctl terminate/install/launch` for their own
ticket, a normal recipe that happens to replace whatever is installed. The tell
is content you have no fixture for. **The fix is the ping, not a diagnosis**:
`ListAgents`, ask, then re-install your own build before trusting anything you
drove afterwards. The journal lane re-drove the cell its main finding rested on;
the finding held, but it did not know that until it checked.

**Analytics fail SILENTLY, and the drop notices are now visible but only in
the log stream.** Nothing serves functions locally by default — the
edge-runtime container has never served them, and `supabase status` lists it
under *Stopped services*. `track_ingest` was probed this session and returned
**503**, so the Tracker is discarding every batch **by design** (tech/06 §2).
GLO-147 made each drop leave an `os.Logger` line on subsystem
`com.glossed.tracking` — but `print` reaches nobody, because our launch recipe
does not pass `--console`. **Before you conclude anything about events, curl
track_ingest, confirm 200, and read the log stream** (both commands in §9).

**After retargeting a stacked PR to main, CI's scope job can silently reuse a
stale decision and skip (or outright fail) the iOS job** — GLO-71's bug, hit
seven times to date; the preemptive routine has prevented a recurrence since.
A skipped check is not a passed check. The routine: rebase onto the base's
exact tip, retarget, **then** `git commit --amend --no-edit` for a fresh SHA
and push — the amend must come AFTER the retarget or the stale scope decision
survives. Confirm the iOS job actually queued before walking away. **A
docs-only PR skipping iOS is correct, not the bug** — the discriminator is
whether the PR touches `.swift` files, so check the file list, not the badge.

**A FULL DISK takes your shell away entirely, and it is what wedges Docker.**
This happened on Aug 29: the volume hit zero free bytes, and the Bash tool
stopped running *any* command — it must create an output file before it runs,
so even `rm -rf .build` returned `ENOSPC` instead of freeing the space. There
is no working around it from inside the session; a human has to clear the
volume. The same event left the Docker daemon split-brain (the db container
`healthy` per `ps`, `not running` per `exec`) and cost the other lane a
restart. **Check `df -h /` before a long build, and treat SwiftPM `.build`
directories across worktrees as the first thing to delete** — they are
regenerable and they are what fills it.

**Docker/colima can wedge under heavy image i/o, and the daemon then holds
CONTRADICTORY state** — `docker ps` said healthy while `inspect` said exited,
with i/o errors on the container's own metadata files. Trust neither, check
both; `colima restart` is the remedy when metadata i/o fails (volumes
survived; rule out disk-full first — it was 11%). After ANY killed queue
consumer: jobs it claimed stay orphaned as `running` — requeue them, and
crash-window `failed` rows with attempts=1 are infra casualties identifiable
by timestamp, also requeue. **Confirmed live on Aug 29** — the disk-full event
above reproduced the split-brain exactly as described, which is the first time
this note has caught its own case rather than described a past one.

**Never `--delete-branch` in merge automation** (killed #159 through a reused
watcher script). Delete branches only after a stack fully lands, by hand.

**Authorizations are per-session and all expired with this one.** This session
held **self-merge on green** (used on every PR below) and **one migration
authorization, granted by Sean on Aug 29 for GLO-150's `0033`**. It needed
**no DataKit opening** — everything it built routed around the frozen core.
Re-ask for anything you need; rulings on tickets stand.

## 1. Where to start

Tracked in **Linear**: workspace [glossed](https://linear.app/glossed), team
**GLO**, project **GLOSSED — Phase 1: The Journal**.

| Next | Why |
|---|---|
| [GLO-21](https://linear.app/glossed/issue/GLO-21) — routines, mid-flight | **The composer is BUILT and UNDRIVEN** on `feat/GLO-21-routines` (`591be60`): model + view + 7 tests + a debug-picker entry with a fixture shelf, lint clean, app build green. Steps order by tap order; `RoutineStore.create` is a stubbed seam because the write needs a **DataKit opening Sean has been asked for and has NOT granted** (routines/collections CRUD). Drive it first (`routines · composer` in the picker), open its PR, then either get the opening or ship read-only. Schema is already live: `routines`/`routine_steps`/`collections`, own-row policies verified by psql this session |
| [GLO-204](https://linear.app/glossed/issue/GLO-204) — display name + bio editor | The avatar half merged as [#328](https://github.com/seanbrasse/glossed/pull/328) (not this lane's). What remains is the name/bio form — and the **bio moderation trap** (§7): `public_texts` rows land `pending` and nothing approves them, so a naive editor writes bios nobody will ever see. Get Sean's call before building the save path |
| [#335](https://github.com/seanbrasse/glossed/pull/335) — the kit nav | Open at handoff, iOS running. Icon-only tabs with drawn glyphs (`KitIcons`), your initial as the third tab, plus outside the capsule. Merges itself on green under the standing grant; if the session died first it is one squash-merge — the drive passed, screenshots went to Sean |
| [GLO-23](https://linear.app/glossed/issue/GLO-23) — real auth | The account steps (#312) run the full UI against a stubbed `AccountStore`; Sign in with Apple + Twilio phone codes need **Sean at the keyboard** (capabilities, secrets). When it lands: the real entry point replaces the debug door, the returning-user path, the tour-seen marker, and an XCUITest over the trip |
| ~~`features/Leaderboard` — GLO-20's last surface~~ | **DONE by the onboarding lane** — built to `G.Leaderboard` ([#293](https://github.com/seanbrasse/glossed/pull/293)), both doors into the board wired ([#294](https://github.com/seanbrasse/glossed/pull/294), [#297](https://github.com/seanbrasse/glossed/pull/297)). The scoped ConfidenceMeter stayed deferred-not-decorated, as instructed |: 0042's `leaderboard()` (claims nulled below min-n, rows never hidden, lowest board carries thresholded dislike reasons, 'yours' resolved server-side) and the DataKit read (#285, `LeaderboardRow.isRankable`). The kit frame is REAL for this screen — pull `G.Leaderboard` via docs/DESIGN.md's GetFile recipe and build to it: rank numbers fade to "—" below min-n, empty copy is exactly "not enough face-offs yet · n of 5", butter badge, footer rule line. One frame element deferred deliberately: the scoped ConfidenceMeter has no defined live source — do not invent a number for it. Then wire the product page's `onLeaderboard` (a dead closure since GLO-151) |
| ~~[#287](https://github.com/seanbrasse/glossed/pull/287) — trending-on-discover wiring~~ | **MERGED** (`43d0ac0`) — the watcher did its job |
| Save/wishlist — the registry's +0.5 row | **A mapping decision before code**: tech/07 §2 reserved +0.5 for "save", and the app's existing save-shaped concept is `want_to_try` — but 0035 deliberately EXCLUDES want_to_try from affinity ("unworn is not evidence"). Those reconcile (intent ≠ experience evidence; +0.5 is an intent weight) but that is a ruling to get from Sean, not to slip into a migration comment |
| [GLO-184](https://linear.app/glossed/issue/GLO-184) — migration comment density | Sean's correction, lands on BOTH lanes: 0030–0034 and 0035–0042 run 40–60% comments against the repo's 7–9%. Future migrations at house density; the ticket carries what should survive in the merged ones |
| [GLO-110](https://linear.app/glossed/issue/GLO-110) — the sweep's two remaining AXES | **Still the highest-yield instrument in the repo, but what is left changed shape.** 34 cells driven and every named cell done, so this is no longer a list of cells: it is (a) **Dynamic Type on the nine surfaces nobody has checked** — GLO-172 found the shelf unusable at accessibility sizes and no other screen has been looked at above default (`xcrun simctl ui <udid> content_size accessibility-extra-large`, underscore); and (b) **the rest of the ladder's transitions**, drivable at last via `ladder · the whole trip` (GLO-180). Two paths are driven; a log that fails mid-trip is not, and neither is GLO-96's own question, which that entry exists to ask — finish a trip, the flow restarts on a fresh id, *does it come back empty?* |
| [GLO-178](https://linear.app/glossed/issue/GLO-178) — import's screenshot source | **Low, and it needs one sentence from Sean, not code.** `screenshot of a haul · we read the text, you confirm` opens the same bare `TextEditor` as the other two sources — no photo picker anywhere, because photo extract is unbuilt (GLO-19). The question is whether a card should promise a capability we do not have; the codebase's own precedent says no (`import · nothing matched` was recorded clean *for having no add button rather than a dead one*), but the card is the kit's. There is a safe half needing no ruling: the editor carries `.accessibilityLabel("your list, one product per line")` and **no visible placeholder**, so VoiceOver users are told what to type and nobody else is |
| [GLO-172](https://linear.app/glossed/issue/GLO-172) — accessibility text sizes | **High, and it needs a design call, not more code.** At accessibility-extra-large the shelf's control row overflows and clips the products. The obvious fix (wrap `controls` in a ScrollView) works completely *and* clips the view toggle at the DEFAULT size — because `sortPills`/`viewToggle` carry `.fixedSize()` and the row had been silently compressing to fit. `ViewThatFits` does not help; it picks by ideal size. Three candidate fixes are written on the ticket; **pick one with Sean** rather than re-deriving them |
| [GLO-156](https://linear.app/glossed/issue/GLO-156) — chip order | **Needs Sean, not code.** The per-category vocabulary means likes and dislikes now interleave alphabetically in the sheet. Grouping by valence is one line in `ShelfChipsModel`; *which group leads, and whether they should be separated rather than merely ordered*, is a feel question — the same class as the shelf label and the fit gate, both of which he ruled on directly. Render both against real chips and let him pick |
| [GLO-164](https://linear.app/glossed/issue/GLO-164) — the duplicated Fit ↔ FitAnswer mapping | Low, small, and self-contained. `Shelf` and `ProductPage` each carry a private copy of the same two switches. It cannot move to a feature (features never import features), so it is a DesignSystem or DataKit call — which makes it **an opening question, not a refactor** |
| [GLO-152](https://linear.app/glossed/issue/GLO-152) — product links | Decided (build now, swap to affiliate links later) and **routes through the 1.5 lane's migration slot** for `product_links`. Part 1 is script-only: `shopify_import.ts` never captured the `handle` that `/products.json` returns, so 2,202 URLs were thrown away. Verified against a live payload |
| [GLO-148](https://linear.app/glossed/issue/GLO-148) — `core/Media` | Both CLAUDE.md files document a package that **has never existed**. One-line doc fix, and it stops the next agent's sweep loop reporting "NO TESTS" for a directory that is not there |
| Beauty API key + Vercel project | Unchanged, still keyboard-minutes for Sean, still the long pole for GLO-90/91/93 |
| [GLO-85](https://linear.app/glossed/issue/GLO-85) queue consumer | Unchanged. **Do not start without Sean's direct word** |
| GLO-16's matched-barcode gap | A log from a matched barcode carries no category, so no fit prompt and no event. **Not drivable in the simulator** (no camera) — needs a device or a seam that fakes the scan |

**Done by the onboarding lane, Aug 30 daytime: sixteen PRs merged, one in CI.**
GLO-20's UI closed — the board built to frame
([#293](https://github.com/seanbrasse/glossed/pull/293), 16 tests), both doors
([#294](https://github.com/seanbrasse/glossed/pull/294),
[#297](https://github.com/seanbrasse/glossed/pull/297)), and
`variableFont` actually scaling on iOS
([#298](https://github.com/seanbrasse/glossed/pull/298)). Then **GLO-18
end-to-end behind the debug door** (`onboarding · the whole trip`): the
reordered quiz ([#304](https://github.com/seanbrasse/glossed/pull/304)) on the
kit's `ShadeAnchorPicker` ([#300](https://github.com/seanbrasse/glossed/pull/300)),
the payoff that runs evidence-backed or stays quiet
([#306](https://github.com/seanbrasse/glossed/pull/306)), account steps with a
typed birthday gate ([#312](https://github.com/seanbrasse/glossed/pull/312)),
the tour + welcome ([#309](https://github.com/seanbrasse/glossed/pull/309)),
the shelf starter's four doors
([#323](https://github.com/seanbrasse/glossed/pull/323)), and tune — screen
([#325](https://github.com/seanbrasse/glossed/pull/325)), DataKit opening
([#326](https://github.com/seanbrasse/glossed/pull/326)), and the card in the
stream, offered by facts and gone when tuned
([#329](https://github.com/seanbrasse/glossed/pull/329) — driven live on both
sides of the gate). Two Sean-granted DataKit openings, **both spent and
expired**: [#301](https://github.com/seanbrasse/glossed/pull/301)
(`ProfileRepository`) and #326 (brand affinities + the anchor read; the anchor
*write* dissolved — `user_shade_anchor` is a VIEW, logging + fit IS setting
it). Also: shopify handles stopped being thrown away
([#295](https://github.com/seanbrasse/glossed/pull/295)), and 44 Onboarding
tests, all counts verified at merge time.

**Done by the journal lane on Aug 30: four PRs, all merged.**
[#276](https://github.com/seanbrasse/glossed/pull/276) finished the sweep grid
(26 → 34 cells) and filed GLO-176/177/178/179/180;
[#280](https://github.com/seanbrasse/glossed/pull/280) fixed the near-match
rung's self-deleting name field and its "check the photo" claim;
[#284](https://github.com/seanbrasse/glossed/pull/284) added `ladder · the whole
trip`, the first fixture able to drive a rung-to-rung transition at all;
[#286](https://github.com/seanbrasse/glossed/pull/286) gave the ladder's failed
lookups something to press.

**Done earlier — 26 PRs merged into main between
[#234](https://github.com/seanbrasse/glossed/pull/234) and
[#262](https://github.com/seanbrasse/glossed/pull/262), across both lanes.**

This lane (Phase 1, journal): fit persists on the product page and stops being
offered where it cannot be answered ([#235](https://github.com/seanbrasse/glossed/pull/235),
[#236](https://github.com/seanbrasse/glossed/pull/236),
[#260](https://github.com/seanbrasse/glossed/pull/260) — GLO-47/165); a blank
shelf says *why* it is blank, four causes ([#237](https://github.com/seanbrasse/glossed/pull/237)
— GLO-166); the events partitions are born locked
([#239](https://github.com/seanbrasse/glossed/pull/239) — GLO-150, the one
authorized migration); the 40-shade sheet gets a fixture and its cap gets a
guard ([#242](https://github.com/seanbrasse/glossed/pull/242) — GLO-168); and
the state sweep in four rounds ([#254](https://github.com/seanbrasse/glossed/pull/254),
[#256](https://github.com/seanbrasse/glossed/pull/256),
[#257](https://github.com/seanbrasse/glossed/pull/257),
[#262](https://github.com/seanbrasse/glossed/pull/262) — GLO-110).

Earlier in the same stretch, also this lane: the sheet asks whether you would
buy it again (GLO-87), the item sheet is held to the screen (GLO-160), the
shelf's label band and scale-down (GLO-149/155), the live chip + note store
(GLO-16), the dead "full page" button becomes a real one (GLO-151), and
analytics drops became visible (GLO-147).

The 1.5 lane, for context only: migrations 0033–0040 (taste engine, four
aggregate writers, the discover read path), five DataKit repositories
(Privacy, Social, Safety, Browse), `inci_enrich`, and `docs/tech/07`.

**The taste/discover lane, Aug 29 evening (a third concurrent session): the
loop is CLOSED and LIVE.** Discover became a real tab (#266) and then a
teaching surface: impressions/taps instrumented (#272/#273 — and #281 fixed
that AppSession never passed the tracker, so they were silently dark until
then), tap-through to product pages (#274, variant dialog for multi-shade),
the dismissal signal end to end (GLO-181: 0041's `rec_dismissals` +
exclusions + the −0.75 affinity term, #278's idempotent write, #281's
long-press gesture — driven live: the #1 pick dismissed, feed re-ranked,
row reverted after). Plus the leaderboard's data half (0042 + #285) and
trending reachable from discover (#287, the cross-lane seam). Migrations
0041–0042 are applied AND verified on hosted (ACLs + crons checked via MCP,
the 0030 precedent). tech/07 §2's registry claim held at first contact:
the dismissal cost exactly one CTE, one weight, one union arm.

## 2. What exists

| Layer | State |
|---|---|
| Schema | **42 migration files, all applied and stamped** (the tracker read 29 on Aug 29 and was reconciled the same night — §0; 0041–0042 stamped at apply time). 0033–0042 landed Aug 29, split across the 1.5 and taste lanes. The slot rotates by announcement — claim it in a message to the other lanes, never infer it from `gh pr list` (§8). **Hosted is at 42 and verified** — the taste lane applied 0035–0042 there via MCP and checked ACLs + cron rows after each, never inferring from local |
| Catalog data | **3,206 products / 9,019 variants / 7,625 images / 497 brands / 22 categories**, local-only; **2,112 pending merge_candidates**, image queue ZERO. (Counted just now against the local DB.) Every image meets the standard (OBF's 588 sub-800px purged, GLO-104). Search knows what things ARE: product_type/tags/origin live on 1,836+ rows. Restore recipe: §9 — now SEVEN scripts. Maya's shelf carries drive-drift rows — fine for dev; a pgTAP run wants a reset + ping |
| `core/DataKit` | **Frozen; openings are per-session and every one granted so far is spent and expired.** The taste lane's opening added the discover reads, `LeaderboardRow`, and `TasteRepository`; the onboarding lane's two (Aug 30) added `ProfileRepository` — `own()`, `saveProfile` with typed validation, `anchor()` off the view, and `brandAffinities` that **encodes only when asked: `nil` leaves the column untouched, `[]` deliberately wipes** (#301/#326); the feed lane's added `LooksRepository` (#333, §-1). A fourth (routines/collections writes) is ASKED, not granted. Test count has moved past 85 — re-measure |
| `core/DesignSystem` | + `YesNoControl`, scaling `ProductSticker`, the kit's `ShadeAnchorPicker` (#300), the GLO-186 Dynamic Type series (#313/#316/#317/#319, another lane's), and the `Avatar` aligned to the kit. [#335](https://github.com/seanbrasse/glossed/pull/335) (in CI at handoff) rewrites `FloatingNav` to the kit — icon-only, drawn `KitIcons` glyphs, initial avatar tab — and *removes* GLO-201's label scaling, superseded with Sean's knowledge. Test count moved past 42 — re-measure |
| `core/Tracking` | track() real, and **a dropped batch now says so** — `os.Logger` on `com.glossed.tracking` in DEBUG, plus `droppedCount` (GLO-147). 15 tests |
| `features/Shelf` | + fit gated on tried (GLO-145), live chip + note store (GLO-16), "would you buy it again?" (GLO-87), a bounded scrolling sheet (GLO-160), the label band and scale-down (GLO-149/155), four named empty states (GLO-166). 133 tests |
| `features/ProductPage` | + the catalog image (GLO-153), and the fit answer now persists and is offered only where a `userItemID` exists to persist it to (GLO-47/165). 20 tests |
| `features/AddLadder` | + GLO-93's scan-miss fill (`BarcodeFilling`/`BarcodeFillSuggestion` live HERE, not in DataKit), the 40-shade fixture and its cap guard (GLO-168), and the journal lane's rung fixes: the name field survives being typed into, the photo instruction only appears where photos do (GLO-176/177), and both failed lookups now offer a retry (GLO-179). **118 tests** |
| `features/Privacy` | Landed by the 1.5 lane in [#259](https://github.com/seanbrasse/glossed/pull/259). Four surfaces, one derived summary. 11 tests |
| `features/Profile` | Landed by the 1.5 lane in [#265](https://github.com/seanbrasse/glossed/pull/265) — the handle claim screen. 11 tests |
| `features/Discover` | Picks, crosswalk, the wander (#263) — then LIVE as tab 1 (#266), instrumented (#273/#281), tap-through (#274), the dismissal gesture (#281), and the trending seam (#287). Then Aug 30: the sectioned page became the feed's STREAM (#314, §-1), grew **injected card slots** (#320), and the tune card rides slot 0 when the gate says so (#329). Wire-level event assertions throughout; test count moved past 10 — re-measure |
| `features/Browse` | Trending (#282, 1.5 lane, 7 tests) — reachable from discover once #287 lands. Routines browse in flight (#288, theirs) |
| `features/Leaderboard` | NEW (onboarding lane, #293) — built to `G.Leaderboard`: slug→ID resolution, yours/everyone scope, ranks skip unrankable rows, sub-min-n rows say so instead of hiding. Reached from the product page's both doors (#294/#297). 16 tests |
| `features/Onboarding` | NEW (onboarding lane, #304–#329) — hook → quiz → payoff → account → build → welcome, plus the tour overlay and tune. **Runs end to end behind the debug door only**; `AccountStore` is stubbed until GLO-23. Steps derive live from domain answers; the payoff renders only what the RPC evidence-backs. 44 tests |
| `features/Looks` / `core/Media` | Feed lane, §-1. Composer has no app entry yet, deliberately |
| `features/Routines` | **Branch only** — `feat/GLO-21-routines` (`591be60`), built + 7 tests, UNDRIVEN, write seam stubbed pending the opening. Not on main |
| `features/Ranking` / `features/Import` | Untouched this stretch. 29 / 12 tests |
| `app/` | Tracker wiring, fit-at-log seam + FitPromptCard (the prompt lives HERE, not in Shelf), catalogImageBase, `AppShellProductPage`, and the debug screen picker — **now including `ladder · the whole trip`, the only entry hosting `LadderFlowView` rather than a bare rung** (GLO-180). The app target has NO test target (`project.yml` scheme `test.targets: []`); every test lives in a package |
| `web/landing/` | Static landing page for the affiliate applications. On main, NOT deployed (§7) |
| `scripts/` | shopify_import, obf_import (+ `--brands`), shopify_images, catalog_images, obf_requalify, brand_merge, merge_feeder, **inci_enrich** (new, GLO-170) |
| `supabase/functions` | **8 functions, 82 deno tests, all passing, none deployed** (re-run at `63739aa`); nothing serves them by default and the silence is dangerous (§0) |

**Verified totals — 514 Swift tests across 12 packages, counted at `63739aa`**
(DataKit 85, DesignSystem 42, Tracking 15, Shelf 133, AddLadder 118, Ranking 29,
ProductPage 20, Import 12, Privacy 11, Profile 32, Discover 10, Browse 7) —
**plus 82 deno across 8 functions.** This replaces the 469/11 figure; the taste
lane had already flagged it as stale without restating it.

**Do not trust that number either; re-measure it.** It has gone 438 → 453 →
469 → 499 → 500 → 513 → 514, and the package count 8 → 9 → 11 → 12. The journal
lane was rebased mid-PR because `features/Browse` landed underneath it, and the
§9 loop found the new package unaided because it globs. The count is
stamped with the commit it was taken at for exactly that reason. **§9's sweep
loop discovers packages by glob rather than listing them** — copy that loop,
never a list, because a list cannot notice a package that did not exist when
it was written. **pgTAP: 567 assertions / 1 known LOCAL failure (`shelf_view` 14; CI is
zero)** — the taste lane's count after 0042's suite landed. The Swift totals
above predate that lane's evening (Discover 5→10, DataKit 83→85, + Browse 7);
re-measure with §9's glob loop rather than trusting any list here. **These
totals predate Aug 30 entirely** — the freshest count is §-1's 644 across 16
packages at `4aeca47`, carrying the same re-measure warning. `core/Media`
exists now (#330 built it; [GLO-148](https://linear.app/glossed/issue/GLO-148)
closed by construction).

The sentence that is true about all of it: **the app is live against the local
stack only** — and as of Aug 29 evening the discover tab is real end to end
against that stack: picks ranked by the caller's own signals, dismissals
teaching the engine back, every claim carrying whose n it is. Hosted has the
schema and no data, no functions, no storage; the catalog's future sources
(feeds, Beauty API) are account-gated on Sean, not code-gated.

## 3. How this session worked

Unchanged: branches `feat/GLO-<n>-desc` (also `fix/`, `docs/`, `test/`), ≤5
files/400 lines (`size-override` + reason when the shape demands it), squash
merges, one migration PR at a time, drive-then-psql on everything, two lanes
coordinating by direct message with file-level ownership announced before
touching.

**The loop that worked, and produced six merged fixes in one stretch:**

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
restore (§9, seven scripts, ~50 min). Current baseline: **567 assertions / 1
known LOCAL failure (`shelf_view` 14; CI is zero)** — the taste lane's count
after 0042's suite landed, and the number §2 carries. The journal lane did not
re-run it.

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
| `core/Media` is documented in both CLAUDE.md files but has never existed | [GLO-148](https://linear.app/glossed/issue/GLO-148) |
| Hosted Supabase has the schema and zero reference rows — no category tree, no chip vocabulary | [GLO-158](https://linear.app/glossed/issue/GLO-158) |
| Typeless storefronts (missha, murad, tatcha, supergoop at ~0 despite the tree) — feeds/Beauty-API bucket, not tree-gated | GLO-99 finding |
| OBF foreign names (category crawl only — brand mode sidesteps); krave maps 0 | [GLO-84](https://linear.app/glossed/issue/GLO-84) / [GLO-79](https://linear.app/glossed/issue/GLO-79) |
| `glossed.app` domain is TAKEN — tech/02's share-URL plan needs a new domain (glossed.beauty was $1.99 at check) | GLO-89 finding |
| A browse TAB: trending + routines-browse are "what other people do", discover is "what fits you" — a real seam, and the kit's nav is three tabs + plus | parked with Sean (GLO-20 thread) |
| ~~`features/Leaderboard` + the product page's dead `onLeaderboard`~~ — **closed**, #293/#294/#297 | [GLO-20](https://linear.app/glossed/issue/GLO-20) / §1 |
| GLO-21 routines: composer undriven on its branch, write seam stubbed, opening asked-not-granted; collections composer unstarted; the + drawer's `collection`/`routine` options still dead | [GLO-21](https://linear.app/glossed/issue/GLO-21) / §1 |
| GLO-204's remaining half (name + bio editor) is one moderation decision away from buildable | [GLO-204](https://linear.app/glossed/issue/GLO-204) / §7 |
| Hair-type privacy: profile badges must never name a body fact — ruling filed off the tune-card work, db half in [#331](https://github.com/seanbrasse/glossed/pull/331) (another lane's, open at handoff) | [GLO-205](https://linear.app/glossed/issue/GLO-205) |
| The tour has no real-entry trigger — it mounts from the debug door; wiring it to first-launch is part of GLO-23's entry work | [GLO-23](https://linear.app/glossed/issue/GLO-23) |
| The scoped ConfidenceMeter in G.Leaderboard has no defined live data source — deferred, not decorated | GLO-20 / §1 |
| Save/wishlist (+0.5) needs the want_to_try-as-intent ruling before code | tech/07 §2 / §1 |
| Un-dismiss management UI (the row is deletable by construction; no surface offers it yet) | [GLO-181](https://linear.app/glossed/issue/GLO-181) note |

## 7. Blocked on a human, not on code

| Blocked thing | On what | Who |
|---|---|---|
| [GLO-172](https://linear.app/glossed/issue/GLO-172)'s fix | **A design decision, not a slot.** Three candidate fixes are on the ticket; the correct one changes how the shelf's control row behaves at default size, which is Sean's call | Sean |
| [GLO-156](https://linear.app/glossed/issue/GLO-156) chip order | Same class — render both and let him pick | Sean |
| [GLO-178](https://linear.app/glossed/issue/GLO-178)'s card | One sentence: should `screenshot of a haul` stay while photo extract is unbuilt? The codebase's precedent says an absent affordance beats a dead one, but the card is the kit's. The placeholder half needs no ruling | Sean |
| Landing-page deploy (→ Rakuten/Impact applications) | Vercel MCP token cannot create projects (403, team role). Create an empty project named `glossed` OR raise the integration's role; the deploy payload is one command away | Sean |
| Rakuten + Impact publisher accounts | Signups (GLO-90/91 carry the exact steps); need the channel URL above | Sean |
| Beauty API key | Free Sandbox+Barcode signup at thebeautyapi.com → `BEAUTY_API_KEY` secret | Sean |
| Any DataKit opening | Per-session authorization. Aug 29 saw two, Aug 30 three more (onboarding lane's #301 + #326, feed lane's #333) — **all spent and expired**. A routines/collections-write opening was ASKED and not answered; re-ask, don't assume | Sean |
| GLO-204's bio save path | `public_texts` rows land `pending` and no moderation approves them (GLO-26 parked) — auto-approve for beta, an "in review" state, or hold the editor? One sentence decides whether the feature is buildable | Sean |
| GLO-23 Apple + phone auth | Sign in with Apple capability + Twilio account/secrets are keyboard-minutes; every account screen already exists against the stub | Sean |
| The browse-tab IA question | Trending + routines browse both exist now; whether they earn a fourth tab or stay one tap behind discover is a nav decision the kit does not answer | Sean |
| Save/wishlist mapping | Whether `want_to_try` IS the +0.5 save signal (intent, distinct from 0035's unworn-is-not-evidence rule) | Sean |
| Any migration slot | Per-migration. Sean authorized `0033` for GLO-150 on Aug 29 after it was flagged as not-purely-additive; that authorization is spent | Sean |
| GLO-85 queue consumer | Needs `ANTHROPIC_API_KEY` **and** Sean's direct word — a relayed hand-off of this lane was retracted once already | Sean |
| R2, function secrets, Apple/Twilio, GLO-71's real fix | Unchanged from #163 | Sean / any human |

## 8. What went wrong, so you don't repeat it

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
`com.glossed.app` — launching `co.glossed.app` from memory got
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
supabase test db          # 567 assertions / 1 known LOCAL failure (shelf_view 14)
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

**The simulator canon: iPhone 16 Pro (iOS 18.0), UDID
`0E1EF64B-E2E3-4A51-B322-29BBEFCEEFE1` — one booted device, always;** shut
down strays, borrow with a ping when two lanes run. Bundle id
`com.glossed.app` (read `project.yml`, don't recall it). **Screenshot pixels
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
