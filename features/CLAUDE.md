# features/ — vertical slices

One SPM package per feature (Onboarding, Shelf, Discover, ProductPage, Ranking, AddLadder, Import, Leaderboard, Profile). Each owns its models, service (business logic — no transport, no UI), data access (always through DataKit repositories), UI, and tests together.

Rules: features never import other features — shared logic moves to core or gets an explicit merged contract first. Screens compose DesignSystem primitives; no styled raw elements. Service functions take the session first and are verbs. Every service touching user data has the four-test template: authorized success, unauthenticated, wrong user, cross-user.

Screen source of truth: the design kit (`screens.jsx` in the Claude Design project) via `docs/tech/01-phase-1-journal.md` §9.
