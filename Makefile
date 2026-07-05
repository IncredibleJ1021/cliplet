.PHONY: build test run package dmg clean

build:
	swift build

test:
	swift test

run:
	swift run cliplet

package:
	./scripts/package_app.sh

dmg: package
	./scripts/package_dmg.sh

clean:
	rm -rf .build dist
