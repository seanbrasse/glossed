.PHONY: setup dev lint format test db-reset db-test db-test-clean generate functions-test catalog-snapshot catalog-restore catalog-generations

setup:
	brew bundle --no-upgrade
	xcodegen generate
	supabase start || true
	$(MAKE) db-reset

generate:
	xcodegen generate

dev: generate
	open Glossed.xcodeproj

lint:
	swiftlint --strict
	swiftformat --lint .

format:
	swiftformat .

# The tests live in the local SPM packages, so SwiftPM is what runs them. The
# app target has no XCTest bundle, which is why the generated `Glossed` scheme
# has an empty test action — `xcodebuild test -scheme Glossed` only ever
# answered "not currently configured for the test action", so this ran zero
# tests for as long as it pointed there.
#
# This is the same loop as the "Package tests" step of the `build · test (iOS)`
# job in .github/workflows/ci.yml, so a green `make test` and a green CI mean
# the same thing. CI additionally does `xcodebuild build -scheme Glossed` to
# compile app/ — that is a build check, not a test, and Xcode covers it locally.
test:
	@set -e; \
	for pkg in core/*/Package.swift features/*/Package.swift; do \
	  [ -e "$$pkg" ] || continue; \
	  dir=$$(dirname "$$pkg"); \
	  echo "==> swift test $$dir"; \
	  (cd "$$dir" && swift test); \
	done

# GLO-223 — Sean's ruling: user data is expendable at this stage, the catalog is
# not. The catalog is NOT in seed.sql; it is ~22,600 rows the seven import
# scripts in HANDOFF §9 put there over ~50 minutes. So a reset snapshots it
# first and puts it back afterwards, and the SAFE path is the default one
# rather than something to remember. `supabase db reset` by hand still drops it.
#
# The snapshots live in ~/.glossed/catalog (override: GLOSSED_CATALOG_HOME),
# OUTSIDE the repo — a wiped worktree or a `git clean` must not cost the
# catalog. Several dated generations are kept (GLOSSED_CATALOG_KEEP, default 5)
# and a save that would shrink the catalog below GLOSSED_CATALOG_MIN_PCT
# (default 90%) of the last one is refused until you pass --allow-shrink.
# The import scripts refresh it themselves — see scripts/db.ts.
db-reset:
	-./scripts/catalog_snapshot.sh save
	supabase db reset
	-./scripts/catalog_snapshot.sh load

catalog-snapshot:
	./scripts/catalog_snapshot.sh save

catalog-restore:
	./scripts/catalog_snapshot.sh load

# What the store holds right now, newest first, with the row count each
# generation recorded. The question "is my catalog actually backed up" should
# not require reading a script.
catalog-generations:
	./scripts/catalog_snapshot.sh list

# `supabase test db` runs against the LIVE local db — there is no shadow
# database. The pgTAP suite is written to own its users from a clean slate,
# which is correct, so it aborts once anyone has driven the app and the
# fixtures collide with real rows (GLO-221).
db-test:
	supabase test db

# The clean-slate run. Deliberately NOT what `db-test` does: two lanes share
# this database, and a test command that silently resets would take a peer's
# drive out from under them mid-session. HANDOFF's standing rule is to ping
# before you reset — so this is the explicit door, and the catalog survives it.
db-test-clean:
	$(MAKE) db-reset
	supabase test db

# Edge Functions are Deno, so they sit outside the Swift toolchain entirely.
functions-test:
	deno check supabase/functions/*/*.ts
	deno lint supabase/functions
	deno fmt --check --line-width=100 supabase/functions
	# --allow-read is scoped to the functions tree: tests read committed fixtures
	# (feed_diff/fixture_feed.json), never the repo at large.
	deno test --allow-net --allow-import --allow-read=supabase/functions supabase/functions
