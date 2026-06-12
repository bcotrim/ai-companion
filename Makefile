.PHONY: build run start stop restart status install-hooks uninstall-hooks clean app

APP = dist/AICompanion.app

app: build
	rm -rf dist
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/pets $(APP)/Contents/MacOS/pets
	cp -R .build/release/pets_pets.bundle $(APP)/Contents/Resources/
	cp app/Info.plist $(APP)/Contents/Info.plist
	cp scripts/install-hooks.sh $(APP)/Contents/Resources/install-hooks.sh
	codesign --force --sign - $(APP)
	cd dist && ditto -c -k --keepParent AICompanion.app AICompanion.zip
	@echo "built dist/AICompanion.zip"

build:
	swift build -c release

run: build
	.build/release/pets

start stop restart status:
	./scripts/petctl.sh $@

install-hooks:
	./scripts/install-hooks.sh

uninstall-hooks:
	./scripts/install-hooks.sh --remove

clean:
	swift package clean
