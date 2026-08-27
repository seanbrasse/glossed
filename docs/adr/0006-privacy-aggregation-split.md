# 0006. Privacy: contribution/visibility split enforced in the database

Date: 2026-08-27 | Status: accepted

## Context
PRD's two-axis model: contribution to anonymous aggregates is always on; attributed visibility is always the user's choice (three scopes × four surfaces from design review). A fully private user still improves every leaderboard.

## Options
1. Application-layer checks only — one missed check leaks a shelf.
2. **RLS per surface via one `can_view(owner, surface)` function + aggregates that store no user identifiers**, readable only through min-n-enforcing security-definer RPCs.

## Decision
Option 2. Aggregate tables (`agg_*`, `shade_cooccurrence`) are identifier-free by construction, so "anonymous contribution" is structural, not a filter. Visibility RLS keys off `privacy_scopes` + `follows` + `blocks`. Discoverability (being surfaced to others in shade-based suggestions) is a separate opt-in flag, stated at the toggle. Minors locked private.

## Consequences
Easy: a forgotten app-layer check fails closed; deletion = recompute aggregates, nothing to scrub. Hard: RLS policy tests need a viewer-pair grid (owner/friend/public/blocked/minor) in CI; min-n thresholds live in one place (SQL constants) to stay auditable. Revisit if: RLS performance on hot feed queries demands materialized permission caches.
