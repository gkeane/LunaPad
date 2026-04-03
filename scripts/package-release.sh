#!/bin/bash
set -euo pipefail

RELEASE_TAG="${1:-}"

if [ -z "$RELEASE_TAG" ]; then
  echo "Usage: scripts/package-release.sh <release-tag>" >&2
  exit 1
fi

APP_VERSION="${APP_VERSION:-${RELEASE_TAG#v}}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"
DIST_DIR="${DIST_DIR:-dist}"
ZIP_PATH="$DIST_DIR/LunaPad-${RELEASE_TAG}-macOS.zip"
CHECKSUM_PATH="$ZIP_PATH.sha256"

mkdir -p "$DIST_DIR"

APP_VERSION="$APP_VERSION" APP_BUILD_NUMBER="$APP_BUILD_NUMBER" ./bundle-app.sh

rm -f "$ZIP_PATH" "$CHECKSUM_PATH"
ditto -c -k --sequesterRsrc --keepParent "LunaPad.app" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$CHECKSUM_PATH"

echo "Packaged:"
echo "  $ZIP_PATH"
echo "  $CHECKSUM_PATH"
