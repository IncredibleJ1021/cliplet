.PHONY: build test run package clean

build:
	swift build

test:
	swift test

run:
	swift run Clip

package:
	./scripts/package_app.sh

clean:
	rm -rf .build dist
