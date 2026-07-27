PROJECT := SwiftConcurrencyLab.xcodeproj
SCHEME := SwiftConcurrencyLab
SIMULATOR_NAME ?= iPhone 17 Pro
SIMULATOR_OS ?= $(shell xcrun --sdk iphonesimulator --show-sdk-version)
DESTINATION ?= platform=iOS Simulator,name=$(SIMULATOR_NAME),OS=$(SIMULATOR_OS)
DERIVED_DATA ?= .DerivedData
BUNDLE_ID := io.github.estelledc.SwiftConcurrencyLab

.PHONY: format-check build build-ci build-release run test test-ui test-ui-evidence audit verify-showcase public-scan check release-check open clean

format-check:
	xcrun swift-format lint --strict --recursive Sources SwiftConcurrencyLab Tests SwiftConcurrencyLabUITests

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -sdk iphonesimulator -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

build-ci:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

build-release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

run: build
	xcrun simctl boot "$(SIMULATOR_NAME)" >/dev/null 2>&1 || true
	xcrun simctl bootstatus booted -b
	xcrun simctl install booted '$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/SwiftConcurrencyLab.app'
	xcrun simctl launch --terminate-running-process booted $(BUNDLE_ID)

test:
	swift test

test-ui:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO test

test-ui-evidence:
	SIMULATOR_NAME='$(SIMULATOR_NAME)' SIMULATOR_OS='$(SIMULATOR_OS)' ./scripts/run-ui-evidence.sh

audit:
	python3 scripts/audit-project.py

verify-showcase:
	python3 scripts/audit-showcase.py

public-scan:
	./scripts/public-scan.sh

check: format-check test build-ci audit verify-showcase public-scan

release-check: check test-ui build-release

open:
	open $(PROJECT)

clean:
	rm -rf $(DERIVED_DATA) .build
