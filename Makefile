.PHONY: build run start stop restart status install-hooks uninstall-hooks clean

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
