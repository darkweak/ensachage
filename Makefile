# Ensachage 🍏 — build & run helper
#
#   make build   Compile the app (Debug) into ./build
#   make run     Build then launch Ensachage.app
#   make release Compile the app (Release)
#   make clean   Remove build artifacts
#   make open    Open the project in Xcode
#   make reset   Wipe the app's saved data (settings, journal, photos)

APP        := Ensachage
PROJECT    := $(APP).xcodeproj
SCHEME     := $(APP)
CONFIG     ?= Debug
DERIVED    := build
BUNDLE_ID  := com.darkweak.ensachage.app
PRODUCT    := $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app
RELEASE_APP := $(DERIVED)/Build/Products/Release/$(APP).app
DISTDIR    := dist

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED)

.PHONY: all build release run clean open dist doctor watch-auth reset

all: build

build:
	$(XCODEBUILD) -configuration $(CONFIG) build

release:
	$(MAKE) build CONFIG=Release

run: build
	@echo "▶ Launching $(APP)…"
	@open "$(PRODUCT)"

clean:
	$(XCODEBUILD) clean
	@rm -rf $(DERIVED)

open:
	@open $(PROJECT)

# Build Release and package the .app into a shareable zip (dist/Ensachage.zip).
dist:
	@echo "📦 Building Release…"
	$(XCODEBUILD) -configuration Release build
	@mkdir -p $(DISTDIR)
	@rm -f "$(DISTDIR)/$(APP).zip"
	@ditto -c -k --keepParent "$(RELEASE_APP)" "$(DISTDIR)/$(APP).zip"
	@echo ""
	@echo "✓ Created $(DISTDIR)/$(APP).zip  ($$(du -h "$(DISTDIR)/$(APP).zip" | cut -f1))"
	@echo "  Share this zip. On first launch a colleague must right-click the app →"
	@echo "  « Ouvrir » (Gatekeeper), or run:"
	@echo "      xattr -dr com.apple.quarantine /Applications/$(APP).app"

# Print signature, entitlements and key Info.plist values for the built app.
doctor:
	@APP_PATH="$(PRODUCT)"; \
	if [ ! -d "$$APP_PATH" ]; then echo "✗ $$APP_PATH introuvable — lancez d'abord: make run"; exit 1; fi; \
	echo "🩺 Ensachage — diagnostic"; \
	echo "App : $$APP_PATH"; \
	echo; \
	echo "── Signature ───────────────────────────────"; \
	codesign -dvvv "$$APP_PATH" 2>&1 | grep -iE "^Identifier|^Authority|^TeamIdentifier|^Signature|adhoc|Sealed" || echo "  (non signé)"; \
	echo; \
	echo "── Entitlements ────────────────────────────"; \
	codesign -d --entitlements - "$$APP_PATH" 2>/dev/null | grep -iE "com\.apple\.security|sandbox|device\.camera|apple-events" || echo "  (aucun / non signé)"; \
	echo; \
	echo "── Info.plist ──────────────────────────────"; \
	PL="$$APP_PATH/Contents/Info.plist"; \
	printf "  Bundle id    : %s\n" "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$$PL" 2>/dev/null)"; \
	printf "  LSUIElement  : %s\n" "$$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$$PL" 2>/dev/null)"; \
	printf "  Icon name    : %s\n" "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$$PL" 2>/dev/null)"; \
	printf "  Camera usage : %s\n" "$$(/usr/libexec/PlistBuddy -c 'Print :NSCameraUsageDescription' "$$PL" 2>/dev/null)"; \
	printf "  AppleEvents  : %s\n" "$$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$$PL" 2>/dev/null)"; \
	echo; \
	echo "── Gatekeeper ──────────────────────────────"; \
	spctl -a -vvv "$$APP_PATH" 2>&1 | head -3

watch-auth:
	@echo "🔎 Lock the screen and FAIL an unlock (bad password / fingerprint / PIN)."
	@echo "   The matching log lines print below — copy them into Settings ▸ Avancé."
	@echo "   Press Ctrl+C to stop."
	@log stream --style compact --level info --predicate 'process == "loginwindow" AND eventMessage CONTAINS "authFailWithMessage" AND eventMessage CONTAINS "authentication failed"' \
		| grep --line-buffered -iE "fail|no match|not match|pin|verif|invalid|denied|wrong|error"

reset:
	@echo "⚠  Removing saved settings, journal and intruder photos…"
	@defaults delete $(BUNDLE_ID) 2>/dev/null || true
	@rm -rf "$(HOME)/Library/Application Support/Ensachage"
	@tccutil reset Camera $(BUNDLE_ID) || true
	@tccutil reset Microphone $(BUNDLE_ID) || true
	@tccutil reset ScreenCapture $(BUNDLE_ID) || true
	@tccutil reset Accessibility $(BUNDLE_ID) || true
	@tccutil reset Contacts $(BUNDLE_ID) || true
	@tccutil reset Calendar $(BUNDLE_ID) || true
	@tccutil reset Photos $(BUNDLE_ID) || true
	@tccutil reset Reminders $(BUNDLE_ID) || true
	@tccutil reset Location $(BUNDLE_ID) || true
	@echo "Done."
