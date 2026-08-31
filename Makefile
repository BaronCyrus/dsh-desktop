-include Config/Local.make

APP_VERSION ?= 1.2.0
BUILD_NUMBER ?= 4
BUNDLE_ID ?= io.github.baroncyrus.dsh-desktop
DEFAULT_PROXY_URL ?=
ARCHITECTURES ?= arm64 x86_64

export APP_VERSION BUILD_NUMBER BUNDLE_ID DEFAULT_PROXY_URL ARCHITECTURES

.PHONY: test build run verify dmg notarize appcast clean

test:
	swift run DSHDesktopCoreChecks

build:
	./scripts/build-app.sh

run: build
	open build/DSH.app

verify:
	./scripts/verify.sh

dmg: build verify
	./scripts/package-dmg.sh

notarize:
	./scripts/notarize.sh

appcast:
	./scripts/generate-appcast.sh

clean:
	./scripts/clean.sh
