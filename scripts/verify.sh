#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_ROOT/build"
APP_DIR="$BUILD_DIR/DSH.app"
INFO_PLIST="$APP_DIR/Contents/Info.plist"
EXECUTABLE="$APP_DIR/Contents/MacOS/DSH"
ICON="$APP_DIR/Contents/Resources/ApplicationIcon.icns"
SPARKLE_FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
VERIFY_DIR="$BUILD_DIR/verify-icon.iconset"

for required in "$INFO_PLIST" "$EXECUTABLE" "$ICON" "$SPARKLE_FRAMEWORK"; do
    if [[ ! -e "$required" ]]; then
        print -u2 "missing required app resource: $required"
        exit 1
    fi
done

plutil -lint "$INFO_PLIST"
plutil -extract SUFeedURL raw "$INFO_PLIST" >/dev/null
plutil -extract SUPublicEDKey raw "$INFO_PLIST" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
otool -L "$EXECUTABLE" | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle'
otool -l "$EXECUTABLE" | grep -q '@executable_path/../Frameworks'

if [[ -e "$VERIFY_DIR" ]]; then
    find "$VERIFY_DIR" -depth -delete
fi
iconutil -c iconset "$ICON" -o "$VERIFY_DIR"
for size in 16 32 128 256 512; do
    test -f "$VERIFY_DIR/icon_${size}x${size}.png"
    test -f "$VERIFY_DIR/icon_${size}x${size}@2x.png"
done

print "Verified $APP_DIR"
file "$EXECUTABLE"
