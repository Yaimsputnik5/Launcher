#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$SCRIPT_DIR/Launcher.xcodeproj"
SCHEME="Launcher"
BUILD_DIR="$SCRIPT_DIR/build"
IPA="$SCRIPT_DIR/Launcher.ipa"

if [ ! -d "$PROJECT" ]; then
  echo "Xcode project not found: $PROJECT" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Run this script on a macOS host with Xcode installed." >&2
  exit 1
fi

cd "$SCRIPT_DIR"
rm -rf "$BUILD_DIR" "$SCRIPT_DIR/Payload" "$IPA"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  BUILD_DIR="$BUILD_DIR" \
  clean build

APP="$BUILD_DIR/Release-iphoneos/$SCHEME.app"
if [ ! -d "$APP" ]; then
  echo "Expected app bundle not found: $APP" >&2
  exit 1
fi

mkdir -p "$SCRIPT_DIR/Payload"
cp -R "$APP" "$SCRIPT_DIR/Payload/$SCHEME.app"
zip -qry "$IPA" Payload
rm -rf "$SCRIPT_DIR/Payload"

echo "Built $IPA"
echo "Install it with AltStore/SideStore; they will apply your signing identity."
