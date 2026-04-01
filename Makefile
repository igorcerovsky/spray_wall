PROJECT ?= SprayWall.xcodeproj
SCHEME ?= SprayWall
CONFIGURATION ?= Debug
DERIVED_DATA ?= .build/xcode-derived-data

IOS_BUILD_DESTINATION ?= generic/platform=iOS
IOS_TEST_DESTINATION ?= platform=iOS Simulator,name=iPhone 17

.PHONY: help xcodeproj ensure-xcodeproj ios-destinations ios-build ios-test

help:
	@echo "Targets:"
	@echo "  make xcodeproj         # Regenerate SprayWall.xcodeproj"
	@echo "  make ios-destinations  # Show available Xcode destinations"
	@echo "  make ios-build         # Build for iOS (generic destination)"
	@echo "  make ios-test          # Run tests on simulator destination"
	@echo
	@echo "Overrides:"
	@echo "  IOS_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17'"
	@echo "  CONFIGURATION=Release"

xcodeproj:
	ruby Tools/generate_xcodeproj.rb

ensure-xcodeproj:
	@test -d "$(PROJECT)" || (echo "Missing $(PROJECT). Run: make xcodeproj" && exit 1)

ios-destinations: ensure-xcodeproj
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -showdestinations

ios-build: ensure-xcodeproj
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination '$(IOS_BUILD_DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO \
		build

ios-test: ensure-xcodeproj
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination '$(IOS_TEST_DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO \
		test
