#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_ROOT/build"
APP_DIR="$BUILD_DIR/DSH.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
ICONSET_DIR="$BUILD_DIR/ApplicationIcon.iconset"
ICON_PATH="$RESOURCES_DIR/ApplicationIcon.icns"
SPARKLE_FRAMEWORK_SOURCE="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_FRAMEWORK="$FRAMEWORKS_DIR/Sparkle.framework"

APP_VERSION=${APP_VERSION:-1.2.0}
BUILD_NUMBER=${BUILD_NUMBER:-4}
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
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$BUILD_DIR/bin"

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

if [[ ! -d "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
    print -u2 "missing Sparkle framework at $SPARKLE_FRAMEWORK_SOURCE"
    print -u2 "run swift package resolve and try again"
    exit 1
fi
ditto "$SPARKLE_FRAMEWORK_SOURCE" "$SPARKLE_FRAMEWORK"
ditto "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
ditto "$PROJECT_ROOT/ThirdParty/DeepSeek-DSH-LICENSE.txt" "$RESOURCES_DIR/DeepSeek-DSH-LICENSE.txt"
ditto "$PROJECT_ROOT/ThirdParty/Sparkle-LICENSE.txt" "$RESOURCES_DIR/Sparkle-LICENSE.txt"

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

sign_options=(--force --sign "$CODE_SIGN_IDENTITY")
if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
    sign_options+=(--options runtime --timestamp)
fi

sparkle_version_dir="$SPARKLE_FRAMEWORK/Versions/B"
if [[ -d "$sparkle_version_dir/XPCServices/Installer.xpc" ]]; then
    codesign "${sign_options[@]}" "$sparkle_version_dir/XPCServices/Installer.xpc"
fi
if [[ -d "$sparkle_version_dir/XPCServices/Downloader.xpc" ]]; then
    codesign "${sign_options[@]}" --preserve-metadata=entitlements "$sparkle_version_dir/XPCServices/Downloader.xpc"
fi
codesign "${sign_options[@]}" "$sparkle_version_dir/Autoupdate"
codesign "${sign_options[@]}" "$sparkle_version_dir/Updater.app"
codesign "${sign_options[@]}" "$SPARKLE_FRAMEWORK"
codesign "${sign_options[@]}" "$APP_DIR"

print "Built $APP_DIR"
file "$MACOS_DIR/DSH"
