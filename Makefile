.PHONY: setup dev lint format test db-reset db-test generate

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
