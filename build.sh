#!/bin/bash
set -e

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/swiftpm-module-cache}"

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

swift build -c release
./bundle-app.sh

APP_DEST="/Applications/LunaPad.app"
rm -rf "$APP_DEST"
cp -R "LunaPad.app" "$APP_DEST"

echo "Done. Open with: open /Applications/LunaPad.app"
