#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_ROOT/build"

if [[ "$PROJECT_ROOT:t" != "DSH-macOS" || "$BUILD_DIR" != "$PROJECT_ROOT/build" ]]; then
    print -u2 "refusing to clean an unexpected project path"
    exit 1
fi

if [[ -e "$BUILD_DIR" ]]; then
    find "$BUILD_DIR" -depth -delete
fi

swift package --package-path "$PROJECT_ROOT" clean
print "Cleaned generated build products"
