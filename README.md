# glossed*

your whole shelf, ranked. iOS app — see [docs/README.md](docs/README.md) for the full technical design.

## Setup

1. Install Xcode 26+ and [Homebrew](https://brew.sh)
2. `git clone git@github.com:seanbrasse/glossed.git && cd glossed`
3. `make setup` — installs CLI tools (xcodegen, supabase, swiftlint, swiftformat), generates `Glossed.xcodeproj`, starts the local Supabase stack, resets + seeds the database
4. `cp .env.example .env` and fill in values (local defaults work out of the box)
5. `make dev` — opens Xcode; run the `Glossed` scheme on an iOS 17+ simulator

Working app with seeded data — if that's not true, it's a P1 bug against this repo.

## Everyday commands

| Command | Does |
|---|---|
| `make dev` | regenerate project + open Xcode |
| `make lint` / `make format` | SwiftLint / SwiftFormat over the tree |
| `make test` | Xcode unit tests |
| `make db-reset` | rebuild local DB from migrations + seed |
| `make db-test` | pgTAP suite incl. isolation tests |
