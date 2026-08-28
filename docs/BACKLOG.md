# Architectural backlog / decision log

Running log of known-open work and decisions deferred on purpose. Anything here is *intentionally* not done yet — if it becomes urgent, it becomes a ticket. Companion to `adr/` (decided things) — this file holds the not-yet-decided and not-yet-written.

## Open — specs to write later

- [ ] **Phase 1.5 build-ready spec** — full DDL, screen inventory (design kit only covers the privacy frames today), viewer-pair RLS test grid, ticket breakdown. Write at phase entry, informed by Phase-1 data. (`tech/02` currently pins architecture + hard rules only.)
- [ ] **Phase 2 build-ready spec** — same treatment; moderation stack needs vendor selection (cloud image moderation, text moderation) + cost quotes before entry. Design kit needs looks/feed/comments coverage beyond the one Feed frame.
- [ ] **Phase 3 build-ready spec** — same; neighbor-pipeline offline-eval harness design; push-notification infra detail (APNs setup runbook).
- [ ] **Phase 4** — remains outline-by-design until scale/funding exists.

## Open — numbers to tune with real data

- [ ] Onboarding payoff evidence threshold (currently n ≥ 8 for the exact shade — a chosen starting point, not validated). `tech/01` §2.
- [ ] Aggregate min-n per surface (leaderboard face-off min is 5 per design; other aggregate views need their own thresholds). `tech/01` §1.3.
- [ ] Shrinkage constant k≈10 in Stage-1 recs. `tech/01` §8.
- [ ] Dedupe auto-band confidence thresholds (watch merge-queue depth). `tech/01` §4.
- [ ] Capture-guide friction vs cutout quality (PRD §19.19) — instrument `cutout_captured` retake rate first.

## Open — infrastructure & process

- [ ] **Dev machine disk is critically full** (~1GB free of 460GB, Aug 27 2026). Local Supabase/Docker cannot run until space is freed — `supabase start` needs ~4GB of images. Until then the CI `db` job is the only database verification. (Colima VM from the first attempt was corrupted by the full disk and deleted.)
- [ ] **No branch protection on `main`** — requires GitHub Pro on private repos. Protection is procedural (CLAUDE.md: agents never push to main, human merges every PR). Enable real protection if the repo goes public or the plan upgrades.
- [ ] **`ANTHROPIC_API_KEY` repo secret not set** — the automated visual-recap workflow skips until it exists (Settings → Secrets → Actions). The hosted interactive /visual-recap also needs the Plan MCP connector, which isn't connected in the build environment; the CI comment recap is the working substitute.

- [ ] Fork the Greenfield Handbook into `docs/HANDBOOK.md`, fill the project card, delete non-applying sections.
- [ ] `docs/runbook.md` — deploy, rollback, restore drill steps, common failures, NCMEC runbook (draft due in Phase 1.5).
- [ ] Root + per-directory agent instruction files (CLAUDE.md tree) once code exists; DataKit + migrations marked do-not-touch.
- [ ] Analytics UI decision point: revisit when weekly SQL review exceeds ~an hour or funnels need self-serve exploration — candidates + rules in `tech/06` §1. Postgres events table stays the source of truth regardless.
- [ ] Affiliate feed publisher-account applications (Rakuten/Impact) — lead time unknown, apply early in Phase 1.
- [ ] Licensed catalog snapshot: get quotes but do not buy until hit-rate data says to (ADR 0003).

## Decided-in-passing (promote to ADR if contested)

- First-party analytics in Postgres; any future vendor gets behavioral events only, never body facts (`tech/06`).
- Events are invisible to the recommendation pipeline (no grants) — the no-engagement-optimization boundary is structural.
