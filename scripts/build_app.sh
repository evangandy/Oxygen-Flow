#!/bin/bash
# Build Oxygen Flow and assemble a signed .app bundle.
# Usage: scripts/build_app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/FlowLocal"
APP="$ROOT/Oxygen Flow.app"
CONTENTS="$APP/Contents"

echo "==> assembling $APP"
rm -rf "$APP" "$ROOT/FlowLocal.app" "$ROOT/Cobalt Flow.app"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/FlowLocal"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# Use the local 'FlowLocal Dev' cert if it exists; otherwise ad-hoc sign ("-") so the app
# builds on any Mac without a certificate (fine for a locally-built, non-distributed app).
SIGN_ID="-"
if security find-identity -v 2>/dev/null | grep -q "FlowLocal Dev"; then
  SIGN_ID="FlowLocal Dev"
fi
echo "==> codesign (identity: $SIGN_ID)"
codesign --force --deep --sign "$SIGN_ID" \
  --entitlements "$ROOT/Resources/FlowLocal.entitlements" \
  --options runtime \
  "$APP" 2>/dev/null || \
codesign --force --deep --sign "$SIGN_ID" \
  --entitlements "$ROOT/Resources/FlowLocal.entitlements" \
  "$APP"

echo "==> done: $APP"
echo "    Launch with: open \"$APP\"   (or run the binary directly: $CONTENTS/MacOS/FlowLocal)"
