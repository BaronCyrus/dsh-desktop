#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_ROOT/build"

if [[ -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    print -u2 "set NOTARY_KEYCHAIN_PROFILE to a profile created with xcrun notarytool store-credentials"
    exit 2
fi

if [[ -n "${DMG_PATH:-}" ]]; then
    dmg_path=$DMG_PATH
else
    dmg_candidates=("$BUILD_DIR"/DSH-*.dmg(Nom))
    if (( ${#dmg_candidates} == 0 )); then
        print -u2 "no DMG found in $BUILD_DIR; run make dmg first"
        exit 1
    fi
    dmg_path=${dmg_candidates[1]}
fi

xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"

print "Notarized $dmg_path"
