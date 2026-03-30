SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

APP_NAME := VoiceInput
BUILD_DIR := .build
DIST_DIR := dist
CONFIG ?= debug
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
BIN_PATH = $(shell swift build -c $(CONFIG) --show-bin-path)

.PHONY: build run install clean

build:
	set -eu; swift build -c $(CONFIG) --product VoiceInputApp; rm -rf $(APP_DIR); mkdir -p $(MACOS_DIR) $(RESOURCES_DIR); cp "$(BIN_PATH)/VoiceInputApp" "$(MACOS_DIR)/$(APP_NAME)"; cp Resources/Info.plist $(CONTENTS_DIR)/Info.plist; cp -R Resources/Assets.xcassets "$(RESOURCES_DIR)/Assets.xcassets"; if command -v xcrun >/dev/null 2>&1 && xcrun --find actool >/dev/null 2>&1; then mkdir -p "$(RESOURCES_DIR)/CompiledAssets"; xcrun actool Resources/Assets.xcassets --compile "$(RESOURCES_DIR)/CompiledAssets" --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon --output-format human-readable-text >/dev/null; test -f "$(RESOURCES_DIR)/CompiledAssets/Assets.car"; cp "$(RESOURCES_DIR)/CompiledAssets/Assets.car" "$(RESOURCES_DIR)/Assets.car"; rm -rf "$(RESOURCES_DIR)/CompiledAssets"; fi; if command -v xcrun >/dev/null 2>&1 && xcrun --find iconutil >/dev/null 2>&1; then mkdir -p "$(RESOURCES_DIR)/AppIcon.iconset"; cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-16x16.png "$(RESOURCES_DIR)/AppIcon.iconset/icon_16x16.png"; cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-16x16@2x.png "$(RESOURCES_DIR)/AppIcon.iconset/icon_16x16@2x.png"; cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-32x32.png "$(RESOURCES_DIR)/AppIcon.iconset/icon_32x32.png"; cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-32x32@2x.png "$(RESOURCES_DIR)/AppIcon.iconset/icon_32x32@2x.png"; cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-128x128.png "$(RESOURCES_DIR)/AppIcon.iconset/icon_128x128.png"; cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-128x128@2x.png "$(RESOURCES_DIR)/AppIcon.iconset/icon_128x128@2x.png"; cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256x256.png "$(RESOURCES_DIR)/AppIcon.iconset/icon_256x256.png"; cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256x256@2x.png "$(RESOURCES_DIR)/AppIcon.iconset/icon_256x256@2x.png"; cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-512x512.png "$(RESOURCES_DIR)/AppIcon.iconset/icon_512x512.png"; cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-512x512@2x.png "$(RESOURCES_DIR)/AppIcon.iconset/icon_512x512@2x.png"; xcrun iconutil -c icns "$(RESOURCES_DIR)/AppIcon.iconset" -o "$(RESOURCES_DIR)/AppIcon.icns" >/dev/null; rm -rf "$(RESOURCES_DIR)/AppIcon.iconset"; fi; codesign --force --sign - --entitlements Resources/App.entitlements $(APP_DIR)

run: build
	open $(APP_DIR)

install: build
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_DIR) /Applications/$(APP_NAME).app

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)
