# Architectural backlog / decision log

Running log of known-open work and decisions deferred on purpose. Anything here is *intentionally* not done yet — if it becomes urgent, it becomes a ticket. Companion to `adr/` (decided things) — this file holds the not-yet-decided and not-yet-written.

## Open — specs to write later

- [x] **Phase 1.5 build-ready spec** — written ([GLO-114](https://linear.app/glossed/issue/GLO-114)). `tech/02` now carries full DDL, the 34-row screen inventory, the ≥170-assertion viewer-pair grid, and the PR plan behind GLO-25/27–31. Two things it deliberately did not decide are now open rows below: the share domain and frames for 1.5.
- [ ] **Phase 2 build-ready spec** — same treatment; moderation stack needs vendor selection (cloud image moderation, text moderation) + cost quotes before entry. Design kit needs looks/feed/comments coverage beyond the one Feed frame.
- [ ] **Phase 3 build-ready spec** — same; neighbor-pipeline offline-eval harness design; push-notification infra detail (APNs setup runbook).
- [ ] **Phase 4** — remains outline-by-design until scale/funding exists.

## Open — numbers to tune with real data

- [ ] Onboarding payoff evidence threshold (currently n ≥ 8 for the exact shade — a chosen starting point, not validated). `tech/01` §2.
- [ ] Aggregate min-n per surface (leaderboard face-off min is 5 per design; other aggregate views need their own thresholds). `tech/01` §1.3.
- [ ] Trending window length + per-skin-type min-n (Phase 1.5) — **still open, now with an address.** Shipped in 0030 ([GLO-127](https://linear.app/glossed/issue/GLO-127)) as `trending_window_days()` = 30 and `min_n_trending()` = 5, written as constant functions so tuning is a one-line change. Neither is measured: 30d is one restock cycle, and 5 is copied from `min_n_faceoffs()` so the two evidence surfaces do not disagree about what counts as enough people. Phase-1 log velocity is what sizes them — and see the row below, because there is not any yet.
- [ ] **`agg_variant_stats` has no writer.** Migrations 0001–0029 create the table, enable RLS on it, and read it from `payoff_for_variant()` — but nothing anywhere populates it, so the onboarding payoff currently returns `n=0, evidence_backed=false` for every variant. Found while building trending (GLO-127), which needed velocity the table cannot express and got its own `refresh_trending()` in 0030. A Phase-1 gap, not a 1.5 one. It is also why the two thresholds above could not be tuned from data.
- [ ] Shrinkage constant k≈10 in Stage-1 recs. `tech/01` §8.
- [ ] Dedupe auto-band confidence thresholds (watch merge-queue depth). `tech/01` §4.
- [ ] **`events` is not named in the deletion list.** `props` legitimately carries Regulated values (`fit`/`fits` on Phase-1's own events, in-house by design), so `events` inherits Regulated classification — but `domain.md` §6's account-deletion list does not mention it. Surfaced while writing `tech/02` §2.3; a Phase-1 gap, not a 1.5 one, and not fixable inside a 1.5 migration.
- [ ] Capture-guide friction vs cutout quality (PRD §19.19) — instrument `cutout_captured` retake rate first.

## Open — blocked on Sean (Phase 1.5 entry)

- [ ] **The share domain — a reach, deferred (Sean, Aug 29).** `glossed.app` is taken; no domain is being bought yet and [GLO-30](https://linear.app/glossed/issue/GLO-30) is not being picked up until later. `glossed.beauty` ($1.99/yr) and `getglossed.app` ($9.99/yr) were free at check time. The bindings in `tech/02` §6.1 stand for whenever it is revisited — minted share URLs are irreversible whenever they get minted. Also gates GLO-89 → GLO-90/91.
- [ ] **The Phase-1.5 DataKit opening bundle** — ~19 methods across four new repository files (`PrivacyRepository`, `SocialRepository`, `BrowseRepository`, `SwatchRepository`). Every DataKit RPC is a bespoke typed method by design, so each 1.5 RPC is a new one. Openings are per-session authorizations — this wants one sized bundle, not nineteen asks. `tech/02` §10.1.
- [ ] **Frames for Phase 1.5.** 32 of 34 screens have no kit frame; the one that exists (`G.Privacy`) is missing the `discoverable` row. Supply frames, or extend Phase 1's no-frames ruling (GLO-16, Aug 28) to 1.5 — `tech/02` §8.

## Open — infrastructure & process

- [ ] **Dev machine disk is critically full** (~1GB free of 460GB, Aug 27 2026). Local Supabase/Docker cannot run until space is freed — `supabase start` needs ~4GB of images. Until then the CI `db` job is the only database verification. (Colima VM from the first attempt was corrupted by the full disk and deleted.)
- [ ] **No branch protection on `main`** — requires GitHub Pro on private repos. Protection is procedural (CLAUDE.md: agents never push to main, human merges every PR). Enable real protection if the repo goes public or the plan upgrades.
- [ ] **`ANTHROPIC_API_KEY` repo secret not set** — the automated visual-recap workflow skips until it exists (Settings → Secrets → Actions). The hosted interactive /visual-recap also needs the Plan MCP connector, which isn't connected in the build environment; the CI comment recap is the working substitute.

- [ ] Fork the Greenfield Handbook into `docs/HANDBOOK.md`, fill the project card, delete non-applying sections.
- [ ] `docs/runbook.md` — **exists** ([GLO-144](https://linear.app/glossed/issue/GLO-144)): moderation queue triage, decision codes, the `underage` and `self_harm` paths, the both-parties notification rule, and the NCMEC draft. **Still missing: deploy, rollback, restore drill, common failures.** And the file is *not operative* until its §3 checklist clears — a named human owns the escalation paths, and counsel reviews §2 (its preservation rule contradicts `domain.md` §6's deletion posture on purpose, and that conflict has to be reconciled in code, not remembered under pressure).
- [ ] Root + per-directory agent instruction files (CLAUDE.md tree) once code exists; DataKit + migrations marked do-not-touch.
- [ ] **Moderation queue UI decision point** — v0 is Supabase Studio only (`tech/02` §7), with GLO-31 5/5's runbook as the interface. Revisit when working the queue costs more than ~an hour a week, or when more than one person reviews. Same shape as the analytics-UI row below, and the same rule: build the surface when the manual path hurts, not before.
- [ ] Analytics UI decision point: revisit when weekly SQL review exceeds ~an hour or funnels need self-serve exploration — candidates + rules in `tech/06` §1. Postgres events table stays the source of truth regardless.
- [ ] Affiliate feed publisher-account applications (Rakuten/Impact) — lead time unknown, apply early in Phase 1.
- [ ] Licensed catalog snapshot: get quotes but do not buy until hit-rate data says to (ADR 0003).

## Decided-in-passing (promote to ADR if contested)

- First-party analytics in Postgres; any future vendor gets behavioral events only, never body facts (`tech/06`).
- Events are invisible to the recommendation pipeline (no grants) — the no-engagement-optimization boundary is structural.
