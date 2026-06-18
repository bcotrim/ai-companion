.PHONY: build run test start stop restart status install-hooks uninstall-hooks validate-pet clean app signed-app notarized-app

APP = dist/AICompanion.app
ZIP = dist/AICompanion.zip
SIGN_IDENTITY ?= -
NOTARY_PROFILE ?= ai-companion

ifeq ($(SIGN_IDENTITY),-)
CODESIGN_ARGS = --force --sign -
else
CODESIGN_ARGS = --force --sign "$(SIGN_IDENTITY)" --timestamp --options runtime --entitlements app/entitlements.plist
endif

app: build
	rm -rf dist
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/pets $(APP)/Contents/MacOS/pets
	cp -R .build/release/pets_pets.bundle $(APP)/Contents/Resources/
	cp app/Info.plist $(APP)/Contents/Info.plist
	cp scripts/install-hooks.sh $(APP)/Contents/Resources/install-hooks.sh
	codesign $(CODESIGN_ARGS) $(APP)
	cd dist && ditto -c -k --keepParent AICompanion.app AICompanion.zip
	cd dist && shasum -a 256 AICompanion.zip > AICompanion.zip.sha256
	@echo "built $(ZIP)"
	@cat $(ZIP).sha256

signed-app:
	@test "$(SIGN_IDENTITY)" != "-" || (echo "usage: make signed-app SIGN_IDENTITY='Developer ID Application: Name (TEAMID)'" >&2; exit 2)
	$(MAKE) app SIGN_IDENTITY="$(SIGN_IDENTITY)"
	codesign --verify --strict --verbose=2 $(APP)
	spctl --assess --type execute --verbose=4 $(APP) || true

notarized-app:
	@test "$(SIGN_IDENTITY)" != "-" || (echo "usage: make notarized-app SIGN_IDENTITY='Developer ID Application: Name (TEAMID)' NOTARY_PROFILE=ai-companion" >&2; exit 2)
	$(MAKE) signed-app SIGN_IDENTITY="$(SIGN_IDENTITY)"
	xcrun notarytool submit $(ZIP) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(APP)
	xcrun stapler validate $(APP)
	cd dist && ditto -c -k --keepParent AICompanion.app AICompanion.zip
	cd dist && shasum -a 256 AICompanion.zip > AICompanion.zip.sha256
	@echo "built notarized $(ZIP)"
	@cat $(ZIP).sha256

build:
	swift build -c release

test:
	./scripts/test.sh

run: build
	.build/release/pets

start stop restart status:
	./scripts/petctl.sh $@

install-hooks:
	./scripts/install-hooks.sh

uninstall-hooks:
	./scripts/install-hooks.sh --remove

validate-pet:
	@test -n "$(PET)" || (echo "usage: make validate-pet PET=/path/to/pet-folder-or.zip" >&2; exit 2)
	./scripts/validate-pet.sh "$(PET)"

clean:
	swift package clean
