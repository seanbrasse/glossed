# features/ — vertical slices

One SPM package per feature (Onboarding, Shelf, Discover, ProductPage, Ranking, AddLadder, Import, Leaderboard, Profile). Each owns its models, service (business logic — no transport, no UI), data access (always through DataKit repositories), UI, and tests together.

Rules: features never import other features — shared logic moves to core or gets an explicit merged contract first. Screens compose DesignSystem primitives; no styled raw elements. Service functions take the session first and are verbs. Every service touching user data has the four-test template: authorized success, unauthenticated, wrong user, cross-user.

Screen source of truth: the design kit — [screen map](https://claude.ai/design/p/38230b94-09d2-4776-9d21-be0722ba54f2?file=ui_kits%2Fglossed-app%2Fscreen-map.html), inventory in `docs/tech/01-phase-1-journal.md` §9. **Open the frame before building the screen**; `docs/DESIGN.md` says how (WebFetch 403s — it needs the browser pane). Building to the tokens is not building to the design: the kit decides what is on the screen, in what order, under what heading, and what the copy says. If you cannot open it, stop and say so.
