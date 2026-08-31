#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_ROOT/build"
APP_DIR="$BUILD_DIR/DSH.app"
STAGING_DIR="$BUILD_DIR/dmg-root"

if [[ ! -d "$APP_DIR" ]]; then
    print -u2 "missing $APP_DIR; run make build first"
    exit 1
fi

version=$(plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")
DMG_PATH=${DMG_PATH:-"$BUILD_DIR/DSH-$version.dmg"}

clean_build_path() {
    local target=$1
    if [[ "$target" != "$BUILD_DIR"/* ]]; then
        print -u2 "refusing to clean path outside build directory: $target"
        exit 1
    fi
    if [[ -e "$target" || -L "$target" ]]; then
        find "$target" -depth -delete
    fi
}

clean_build_path "$STAGING_DIR"
clean_build_path "$DMG_PATH"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/DSH.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "DSH" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

print "Created $DMG_PATH"
