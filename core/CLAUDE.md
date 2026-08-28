# core/ — shared packages

What belongs here: DesignSystem (tokens + primitives only, no app knowledge), DataKit (**FROZEN CORE — do not modify**), Media (cutouts, EXIF strip, uploads), Tracking (the `track()` wrapper + compiler-checked event enum).

What does not: business logic (lives in the owning feature's service), screens, feature-specific components. Core imports nothing from `features/` or `app/`.

A new DesignSystem primitive is its own PR, reviewed separately from the feature that wants it. No raw colors or spacing values anywhere — tokens only.

## DataKit is frozen

`core/DataKit` is the one path every query takes, which is why it is worth
protecting: a mistake here is a mistake everywhere, and it is the layer where a
missing session check stops being a bug and becomes a data leak.

Do not modify it. If a feature needs data DataKit does not expose, that is a
ticket against DataKit reviewed on its own — not an edit made in passing while
building something else. The same goes for widening a repository's return type
or relaxing a `throws(GlossedError)` signature to make a call site simpler.

What lives here: session handling, typed errors, and repositories over
PostgREST/RPC. What does not: business rules. Ranking order, wear-in gating,
and unlock thresholds belong to the features that own them — DataKit carries
results across the boundary, it does not decide them.
