.PHONY: build test run verify package dmg clean

build:
	swift build

test:
	swift test

verify:
	bash -n scripts/*.sh Tests/ScriptTests/*.sh
	node --check npm/cliplet.js
	plutil -lint Resources/Info.plist
	npm run pack:check
	./Tests/ScriptTests/create_release_tag_test.sh
	swift build
	swift test

run:
	swift run cliplet

package:
	./scripts/package_app.sh

dmg: package
	./scripts/package_dmg.sh

clean:
	rm -rf .build dist
