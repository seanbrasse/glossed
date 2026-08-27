# GLOSSED — docs

Read in this order:

1. [`domain.md`](domain.md) — vocabulary, entities, lifecycles, permission matrix, data classification, retention. The schema's source of truth.
2. [`tech/00-architecture.md`](tech/00-architecture.md) — project card, stack, system diagram, repo layout, environments, design system, **design-review deltas that supersede the PRD**.
3. [`tech/01-phase-1-journal.md`](tech/01-phase-1-journal.md) — build-ready V1: schema, auth + onboarding, ranking, catalog pipeline, chips, ingest paths, images, recs Stage 0–1, tests, metrics, launch checklist, build order.
4. [`tech/02-phase-15-public-identity.md`](tech/02-phase-15-public-identity.md) — privacy scope matrix, profiles, following, routines browse, swatches, link cards.
5. [`tech/03-phase-2-social.md`](tech/03-phase-2-social.md) — looks, feed, comments, contacts, gap cards, the seam, the Stylist, full moderation stack.
6. [`tech/04-phase-3-depth.md`](tech/04-phase-3-depth.md) — price history/alerts, Kendall-tau neighbors, ingredient conflicts, creator points.
7. [`tech/05-phase-4-reach.md`](tech/05-phase-4-reach.md) — brand pages, targeted sampling, native video, community cleanup.
8. [`tech/06-instrumentation.md`](tech/06-instrumentation.md) — first-party analytics: event taxonomy, user-facts cohorts, the weekly standing questions.
9. [`adr/`](adr/) — the six decisions expensive to reverse.

Spec depth is deliberate: Phase 1 is build-ready; 1.5/2/3/4 pin the architecture, schema shapes, and hard rules so nothing in Phase 1 blocks them. Each gets its build-ready pass (full DDL, screen inventory, ticket breakdown) at phase entry, informed by Phase-1 data and the design kit's coverage of those surfaces.

Source inputs: PRD v2.0 (`~/Downloads/glossed-prd-v2.0.md`), Greenfield Handbook (`~/Downloads/GREENFIELD_HANDBOOK_1.md` — fork into `docs/HANDBOOK.md` when the repo is initialized), and the GLOSSED design system + UI kit (Claude Design project: tokens, 26 components, `screens.jsx`, screen map).
