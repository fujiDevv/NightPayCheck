SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
SIMULATOR_ID ?= $(shell python3 scripts/simulator-id.py)
DERIVED_DATA ?= $(CURDIR)/.build/xcode
BUNDLE_ID := com.fujidevv.NightPayCheck

.PHONY: build run test test-ui
build:
	@test -n "$(SIMULATOR_ID)" || { echo "Set SIMULATOR_ID to an available iPhone UDID."; exit 1; }
	@mkdir -p "$(DERIVED_DATA)"
	@xcodebuild -project NightPayCheck.xcodeproj -scheme NightPayCheck -configuration Debug -destination 'id=$(SIMULATOR_ID)' -derivedDataPath "$(DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO build > "$(DERIVED_DATA)/build.log" 2>&1 || { tail -80 "$(DERIVED_DATA)/build.log"; exit 1; }
	@tail -3 "$(DERIVED_DATA)/build.log"

run: build
	@xcrun simctl bootstatus "$(SIMULATOR_ID)" -b
	@if [ -d "$$(xcode-select -p)/Applications/Simulator.app" ]; then open -a "$$(xcode-select -p)/Applications/Simulator.app"; else open -a "$$(xcode-select -p)/../Applications/DeviceHub.app"; fi
	@xcrun simctl install "$(SIMULATOR_ID)" "$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/NightPayCheck.app"
	@xcrun simctl launch "$(SIMULATOR_ID)" "$(BUNDLE_ID)"

test:
	@swift test --scratch-path "$(CURDIR)/.build/core"

test-ui:
	@xcodebuild -project NightPayCheck.xcodeproj -scheme NightPayCheck -destination 'id=$(SIMULATOR_ID)' -derivedDataPath "$(DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO -only-testing:NightPayCheckUITests test
