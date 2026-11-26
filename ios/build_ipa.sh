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

case "${IOS_EMBED_CLIENT:-0}" in
  1|true|TRUE|yes|YES)
  echo "Staging the original client payload for embedding..."
  IOS_CLIENT_DEST="$SCRIPT_DIR/Launcher/Resources/ClientAssets" \
    "$SCRIPT_DIR/scripts/fetch_client_payload.sh"
    ;;
  *)
    ;;
esac

if [ -n "${SANCTUARY_DIR:-}" ] && [ -d "$SANCTUARY_DIR/src/Resources" ]; then
  echo "Syncing Sanctuary resources from $SANCTUARY_DIR..."
  SANCTUARY_DIR="$SANCTUARY_DIR" "$SCRIPT_DIR/scripts/sync_sanctuary_resources.sh"
fi

CLIENT_INDEX="$SCRIPT_DIR/Launcher/Resources/ClientAssets/client-assets-index.json"
if [ -f "$CLIENT_INDEX" ]; then
  echo "Client payload index found; Xcode will copy ClientAssets into the app."
else
  echo "Warning: no embedded client payload. Set IOS_EMBED_CLIENT=1 to include it." >&2
fi

if [ ! -d "$SCRIPT_DIR/Launcher/Resources/SanctuaryResources" ]; then
  echo "Warning: SanctuaryResources is missing. Run scripts/sync_sanctuary_resources.sh." >&2
fi

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
