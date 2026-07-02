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

.PHONY: all build release run clean open dist watch-auth reset

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
	@echo "Done."
