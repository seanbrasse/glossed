# Architectural backlog / decision log

Running log of known-open work and decisions deferred on purpose. Anything here is *intentionally* not done yet — if it becomes urgent, it becomes a ticket. Companion to `adr/` (decided things) — this file holds the not-yet-decided and not-yet-written.

## Open — specs to write later

- [x] **Phase 1.5 build-ready spec** — written ([GLO-114](https://linear.app/glossed/issue/GLO-114)). `tech/02` now carries full DDL, the 34-row screen inventory, the ≥170-assertion viewer-pair grid, and the PR plan behind GLO-25/27–31. Two things it deliberately did not decide are now open rows below: the share domain and frames for 1.5.
- [ ] **Phase 2 build-ready spec** — same treatment; moderation stack needs vendor selection (cloud image moderation, text moderation) + cost quotes before entry. Design kit needs looks/feed/comments coverage beyond the one Feed frame.
- [ ] **Phase 3 build-ready spec** — same; neighbor-pipeline offline-eval harness design; push-notification infra detail (APNs setup runbook).
- [ ] **Phase 4** — remains outline-by-design until scale/funding exists.

- [ ] **Saves — keeping other people's looks, collections and routines** (Sean, Sep 2). Spec written: `tech/03` §1a — private pointers, never a feed event, weak taste signal, a `saved` tab on the profile — routines · products · collections · looks — that becomes want-to-try's home (Sean's ruling: it moves out of collections), `SaveIcon` on the three stranger surfaces, and a `reference_saved` tool for the stylist. Eight tickets (SAV-1–8) threaded on GLO-224 while the workspace is at its issue cap; SAV-2 needs the migration slot after STY-8.

## Open — numbers to tune with real data

- [ ] Onboarding payoff evidence threshold (currently n ≥ 8 for the exact shade — a chosen starting point, not validated). `tech/01` §2.
- [ ] Aggregate min-n per surface (leaderboard face-off min is 5 per design; other aggregate views need their own thresholds). `tech/01` §1.3.
- [ ] Trending window length + per-skin-type min-n (Phase 1.5) — **still open, now with an address.** Shipped in 0030 ([GLO-127](https://linear.app/glossed/issue/GLO-127)) as `trending_window_days()` = 30 and `min_n_trending()` = 5, written as constant functions so tuning is a one-line change. Neither is measured: 30d is one restock cycle, and 5 is copied from `min_n_faceoffs()` so the two evidence surfaces do not disagree about what counts as enough people. Phase-1 log velocity is what sizes them — and see the row below, because there is not any yet.
- [x] ~~**`agg_variant_stats` has no writer**~~ **It does now — 0036** ([GLO-157](https://linear.app/glossed/issue/GLO-157)): `refresh_variant_stats()` writes the full cohort lattice (tone × skin × **hair** — the key gained its third axis) per variant, hourly via pg_cron, service-role only. `payoff_for_variant()` learned the third axis in the same migration so fits don't double-count through hair cohorts. What remains open from the original row: the chip *query* surface that reads `chip_counts` is still unbuilt, and thresholds still can't be tuned until real log velocity exists.
- [x] ~~**Chip aggregate min-n — pick it before the writer ships.**~~ **Picked in 0036**: `min_n_chip_claims()` = 5, provisional and untuned, chosen equal to `min_n_faceoffs()`/`min_n_trending()` so the evidence surfaces agree on what counts as enough people. The writer stores every cell including n=1 — **min-n gates the render, never the data** — so tuning it later is a one-line change that re-gates instantly.
- [ ] Shrinkage constant k≈10 **and the affinity signal weights** (rank ±3.0 · dislike+chip −2.0 · like+chip +1.5 · bare ±1.0 · ownership +0.25) — shipped in 0035 ([GLO-169](https://linear.app/glossed/issue/GLO-169)) as constants in `affinity_for_user()`'s one body, encoding `tech/01` §8's *ordering*, not measured truth. Also untuned: whether opposite-valence chips on a liked item should count (deliberately not, at launch — tech/07 §2). Tuning is a one-line change with twelve assertions watching.
- [ ] Dedupe auto-band confidence thresholds (watch merge-queue depth). `tech/01` §4.
- [ ] **`events` is not named in the deletion list.** `props` legitimately carries Regulated values (`fit`/`fits` on Phase-1's own events, in-house by design), so `events` inherits Regulated classification — but `domain.md` §6's account-deletion list does not mention it. Surfaced while writing `tech/02` §2.3; a Phase-1 gap, not a 1.5 one, and not fixable inside a 1.5 migration.
- [ ] Capture-guide friction vs cutout quality (PRD §19.19) — instrument `cutout_captured` retake rate first.

## Open — blocked on Sean (Phase 1.5 entry)

- [ ] **The share domain — a reach, deferred (Sean, Aug 29).** `glossed.app` is taken; no domain is being bought yet and [GLO-30](https://linear.app/glossed/issue/GLO-30) is not being picked up until later. `glossed.beauty` ($1.99/yr) and `getglossed.app` ($9.99/yr) were free at check time. The bindings in `tech/02` §6.1 stand for whenever it is revisited — minted share URLs are irreversible whenever they get minted. Also gates GLO-89 → GLO-90/91.
- [ ] **The Phase-1.5 DataKit opening bundle** — ~19 methods across four new repository files (`PrivacyRepository`, `SocialRepository`, `BrowseRepository`, `SwatchRepository`). Every DataKit RPC is a bespoke typed method by design, so each 1.5 RPC is a new one. Openings are per-session authorizations — this wants one sized bundle, not nineteen asks. `tech/02` §10.1.
- [x] **Frames for Phase 1.5 — decided (Sean, Aug 29): no frames, build from the design system.** Phase 1's no-frames route (GLO-16, Aug 28) extends to 1.5. All 34 screens are built from `core/DesignSystem` tokens and components; the two existing kit frames (`privacy · all four`, `privacy · mixed`) are reference, not specification, and the stale `discoverable` row in them is superseded rather than a gap to fill. Sean workshops in the PR — `tech/02` §8.

- [ ] **Bios auto-approve, and it must be switched off before public launch.** `bios_auto_approve()` (0045, [GLO-207](https://linear.app/glossed/issue/GLO-207)) returns `true`, so a bio is published the moment it is written. Sean's ruling, Aug 30 — correct while the beta is closed and hand-recruited, because moderation is parked and a gated bio would otherwise never appear at all. **There is no cohort table**: the switch is global, so it does not stop applying when the app opens up. Flipping it is one line; the backlog it leaves is `select * from public_texts where kind = 'bio' and verdict ? 'auto_approved'`, which is deliberately queryable for exactly this.

## Open — infrastructure & process

- [ ] **Dev machine disk is critically full** (~1GB free of 460GB, Aug 27 2026). Local Supabase/Docker cannot run until space is freed — `supabase start` needs ~4GB of images. Until then the CI `db` job is the only database verification. (Colima VM from the first attempt was corrupted by the full disk and deleted.)
- [ ] **No branch protection on `main`** — requires GitHub Pro on private repos. Protection is procedural (CLAUDE.md: agents never push to main, human merges every PR). Enable real protection if the repo goes public or the plan upgrades.
- [ ] **`ANTHROPIC_API_KEY` repo secret not set** — the automated visual-recap workflow skips until it exists (Settings → Secrets → Actions). The hosted interactive /visual-recap also needs the Plan MCP connector, which isn't connected in the build environment; the CI comment recap is the working substitute.

- [ ] Fork the Greenfield Handbook into `docs/HANDBOOK.md`, fill the project card, delete non-applying sections.
- [ ] **Moderation is parked (Sean, Aug 29) — "skip the moderation for now."** No named human for §3, so `docs/runbook.md` stays non-operative and the moderation queue is not staffed. The text-moderation Edge Function ([GLO-141](https://linear.app/glossed/issue/GLO-141)) and the reports table are built and tested; nothing runs them. Revisit before any surface goes public, because §0's gate assumes a reviewer exists.
- [ ] `docs/runbook.md` — **exists** ([GLO-144](https://linear.app/glossed/issue/GLO-144)): moderation queue triage, decision codes, the `underage` and `self_harm` paths, the both-parties notification rule, and the NCMEC draft. **Still missing: deploy, rollback, restore drill, common failures.** And the file is *not operative* until its §3 checklist clears — a named human owns the escalation paths, and counsel reviews §2 (its preservation rule contradicts `domain.md` §6's deletion posture on purpose, and that conflict has to be reconciled in code, not remembered under pressure).
- [ ] Root + per-directory agent instruction files (CLAUDE.md tree) once code exists; DataKit + migrations marked do-not-touch.
- [ ] **Moderation queue UI decision point** — v0 is Supabase Studio only (`tech/02` §7), with GLO-31 5/5's runbook as the interface. Revisit when working the queue costs more than ~an hour a week, or when more than one person reviews. Same shape as the analytics-UI row below, and the same rule: build the surface when the manual path hurts, not before.
- [ ] Analytics UI decision point: revisit when weekly SQL review exceeds ~an hour or funnels need self-serve exploration — candidates + rules in `tech/06` §1. Postgres events table stays the source of truth regardless.
- [ ] Affiliate feed publisher-account applications (Rakuten/Impact) — lead time unknown, apply early in Phase 1.
- [ ] Licensed catalog snapshot: get quotes but do not buy until hit-rate data says to (ADR 0003).

## Decided-in-passing (promote to ADR if contested)

- First-party analytics in Postgres; any future vendor gets behavioral events only, never body facts (`tech/06`).
- Events are invisible to the recommendation pipeline (no grants) — the no-engagement-optimization boundary is structural.
