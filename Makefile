.PHONY: setup dev lint format test db-reset db-test generate functions-test

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

test: generate
	xcodebuild test -project Glossed.xcodeproj -scheme Glossed \
	  -destination 'platform=iOS Simulator,name=iPhone 17' | xcbeautify || \
	xcodebuild test -project Glossed.xcodeproj -scheme Glossed \
	  -destination 'platform=iOS Simulator,name=iPhone 17'

db-reset:
	supabase db reset

db-test:
	supabase test db

# Edge Functions are Deno, so they sit outside the Swift toolchain entirely.
functions-test:
	deno check supabase/functions/*/*.ts
	deno lint supabase/functions
	deno fmt --check --line-width=100 supabase/functions
	# --allow-read is scoped to the functions tree: tests read committed fixtures
	# (feed_diff/fixture_feed.json), never the repo at large.
	deno test --allow-net --allow-import --allow-read=supabase/functions supabase/functions
