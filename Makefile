# Run `make` after cloning and after editing any project.yml.
# The .xcodeproj files are generated and gitignored: edit project.yml, not the project.

APPS := $(patsubst Apps/%/project.yml,%,$(wildcard Apps/*/project.yml))
DERIVED_DATA := .build/DerivedData

.PHONY: generate build test test-report open clean

generate:
	@for app in $(APPS); do Scripts/xcodegen generate --quiet --spec Apps/$$app/project.yml || exit 1; done

# Debug build of every app, signed ad hoc so it works before a team ID is set.
build: generate
	@for app in $(APPS); do \
		echo "Building $${app}..."; \
		xcodebuild build -quiet -workspace MiniApps.xcworkspace -scheme $$app \
			-configuration Debug -destination 'generic/platform=macOS' \
			-derivedDataPath $(DERIVED_DATA) \
			CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= || exit 1; \
	done

# Unit tests for every app that has a test target.
test: generate
	@for app in $(APPS); do \
		if grep -q "bundle.unit-test" Apps/$$app/project.yml; then \
			echo "Testing $${app}..."; \
			xcodebuild test -quiet -workspace MiniApps.xcworkspace -scheme $$app \
				-configuration Debug -destination 'platform=macOS' \
				-derivedDataPath $(DERIVED_DATA) \
				CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= || exit 1; \
		fi; \
	done

# Runs Posture Pet's tests (even if some fail), renders Mochi with simulated
# AirPods, and opens an HTML report from .build/TestReport.
test-report: build
	-@$(MAKE) --no-print-directory test
	@Apps/PosturePet/Scripts/test-report

open: generate
	open MiniApps.xcworkspace

clean:
	rm -rf .build Apps/*/*.xcodeproj
