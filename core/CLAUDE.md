# core/ — shared packages

What belongs here: DesignSystem (tokens + primitives only, no app knowledge), DataKit (**frozen core — agents never modify once merged**), Media (cutouts, EXIF strip, uploads), Tracking (the `track()` wrapper + compiler-checked event enum).

What does not: business logic (lives in the owning feature's service), screens, feature-specific components. Core imports nothing from `features/` or `app/`.

A new DesignSystem primitive is its own PR, reviewed separately from the feature that wants it. No raw colors or spacing values anywhere — tokens only.
