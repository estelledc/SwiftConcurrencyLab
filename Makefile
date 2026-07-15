PROJECT := SwiftConcurrencyLab.xcodeproj
SCHEME := SwiftConcurrencyLab
SIMULATOR_NAME ?= iPhone 17 Pro
DESTINATION ?= platform=iOS Simulator,name=$(SIMULATOR_NAME),OS=latest
DERIVED_DATA := .DerivedData
BUNDLE_ID := io.github.estelledc.SwiftConcurrencyLab

.PHONY: build run test test-ui verify-showcase public-scan check release-check open clean

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -sdk iphonesimulator -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

run: build
	xcrun simctl boot "$(SIMULATOR_NAME)" >/dev/null 2>&1 || true
	xcrun simctl bootstatus booted -b
	xcrun simctl install booted '$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/SwiftConcurrencyLab.app'
	xcrun simctl launch --terminate-running-process booted $(BUNDLE_ID)

test:
	swift test

test-ui:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO test

verify-showcase:
	python3 scripts/audit-showcase.py

public-scan:
	./scripts/public-scan.sh

check: test build verify-showcase public-scan

release-check: check test-ui

open:
	open $(PROJECT)

clean:
	rm -rf $(DERIVED_DATA) .build
