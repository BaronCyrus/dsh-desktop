#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_ROOT/build"
APP_DIR="$BUILD_DIR/DSH.app"
RELEASE_DIR="$BUILD_DIR/release"
GENERATE_APPCAST="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"

if [[ ! -d "$APP_DIR" ]]; then
    print -u2 "missing $APP_DIR; run make dmg first"
    exit 1
fi

version=$(plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")
archive_path=${DMG_PATH:-"$BUILD_DIR/DSH-$version.dmg"}
release_tag=${RELEASE_TAG:-"v$version"}
download_url_prefix=${DOWNLOAD_URL_PREFIX:-"https://github.com/BaronCyrus/dsh-desktop/releases/download/$release_tag/"}
sparkle_key_account=${SPARKLE_KEY_ACCOUNT:-"BaronCyrus/dsh-desktop"}
release_notes_path=${RELEASE_NOTES_PATH:-"$PROJECT_ROOT/ReleaseNotes/$version.md"}

if [[ ! -f "$archive_path" ]]; then
    print -u2 "missing $archive_path; run make dmg first"
    exit 1
fi
if [[ ! -x "$GENERATE_APPCAST" ]]; then
    print -u2 "missing Sparkle generate_appcast tool; run swift package resolve"
    exit 1
fi

if [[ -e "$RELEASE_DIR" ]]; then
    if [[ "$RELEASE_DIR" != "$BUILD_DIR"/* ]]; then
        print -u2 "refusing to clean path outside build directory: $RELEASE_DIR"
        exit 1
    fi
    find "$RELEASE_DIR" -depth -delete
fi
mkdir -p "$RELEASE_DIR"

archive_name=${archive_path:t}
staged_archive="$RELEASE_DIR/$archive_name"
ditto "$archive_path" "$staged_archive"

if [[ -f "$release_notes_path" ]]; then
    ditto "$release_notes_path" "$RELEASE_DIR/${archive_name:r}.md"
fi

appcast_options=(
    --download-url-prefix "$download_url_prefix"
    --link "https://github.com/BaronCyrus/dsh-desktop"
    --maximum-versions 1
    --maximum-deltas 0
    --embed-release-notes
    -o "$RELEASE_DIR/appcast.xml"
)

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    print -rn -- "$SPARKLE_PRIVATE_KEY" | \
        "$GENERATE_APPCAST" "${appcast_options[@]}" --ed-key-file - "$RELEASE_DIR"
else
    "$GENERATE_APPCAST" "${appcast_options[@]}" --account "$sparkle_key_account" "$RELEASE_DIR"
fi

appcast_path="$RELEASE_DIR/appcast.xml"
if [[ ! -s "$appcast_path" ]]; then
    print -u2 "Sparkle did not create $appcast_path"
    exit 1
fi

print "Prepared release assets in $RELEASE_DIR"
print "$staged_archive"
print "$appcast_path"
