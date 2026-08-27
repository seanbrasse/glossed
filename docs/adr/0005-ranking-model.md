# 0005. Ranking: immutable face-off log + derived positions, percentile aggregation

Date: 2026-08-27 | Status: accepted

## Context
Beli-style pairwise insertion, no stars, per-category lists, 3-item unlock, per-category skincare wear-in delay, aggregate leaderboards that must never publish thin cells.

## Options
1. Elo/TrueSkill scores — opaque, over-engineered for lists of 3–30, contradicts "the list is the product."
2. Positions only (no comparison log) — loses the ability to recompute, audit, or power rank-correlation neighbors later.
3. **Immutable `face_offs` log + derived `rank_positions`**, binary insertion capped at 4 comparisons, later contradictions resolved by minimal adjacent moves.

## Decision
Option 3. Aggregation: per-user percentile `1−(pos−1)/(len−1)` → cohort mean; a product needs **≥5 face-offs in a scope** to render ranked (design decision); n always shown; roll up (category parent / tone band) instead of rendering thin cells. Kendall-tau neighbors (Phase 3) read the same log.

## Consequences
Easy: explainable, replayable, cheap; skips are data. Hard: contradiction-resolution needs careful tests; scoped buckets (everyday/full-glam) multiply lists — schema keys on `scope_key` from day one so adding scopes is data, not migration. Revisit if: users demand manual drag-reorder (compatible: it writes synthetic positions, log preserved).
