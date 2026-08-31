#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_ROOT/build"
APP_DIR="$BUILD_DIR/DSH.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/ApplicationIcon.iconset"
ICON_PATH="$RESOURCES_DIR/ApplicationIcon.icns"

APP_VERSION=${APP_VERSION:-1.1.0}
BUILD_NUMBER=${BUILD_NUMBER:-3}
BUNDLE_ID=${BUNDLE_ID:-io.github.baroncyrus.dsh-desktop}
DEFAULT_PROXY_URL=${DEFAULT_PROXY_URL:-}
ARCHITECTURES=${ARCHITECTURES:-$(uname -m)}
CODE_SIGN_IDENTITY=${CODE_SIGN_IDENTITY:--}

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

clean_build_path "$APP_DIR"
clean_build_path "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BUILD_DIR/bin"

binary_paths=()
for architecture in ${(z)ARCHITECTURES}; do
    print "Building DSH for $architecture…"
    swift build \
        --package-path "$PROJECT_ROOT" \
        -c release \
        --arch "$architecture" \
        --product DSH
    bin_dir=$(swift build \
        --package-path "$PROJECT_ROOT" \
        -c release \
        --arch "$architecture" \
        --show-bin-path)
    staged_binary="$BUILD_DIR/bin/DSH-$architecture"
    ditto "$bin_dir/DSH" "$staged_binary"
    binary_paths+=("$staged_binary")
done

if (( ${#binary_paths} == 1 )); then
    ditto "${binary_paths[1]}" "$MACOS_DIR/DSH"
else
    xcrun lipo -create "${binary_paths[@]}" -output "$MACOS_DIR/DSH"
fi
chmod 755 "$MACOS_DIR/DSH"

print "Generating application icon…"
xcrun swift "$PROJECT_ROOT/Tools/generate-icon.swift" \
    "$PROJECT_ROOT/Assets/favicon.svg" \
    "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"

ditto "$PROJECT_ROOT/Config/Info.plist" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
plutil -replace DSHDefaultProxyURL -string "$DEFAULT_PROXY_URL" "$CONTENTS_DIR/Info.plist"

if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP_DIR"
fi

print "Built $APP_DIR"
file "$MACOS_DIR/DSH"
