#!/bin/bash
# Build FlowLocal and assemble a signed .app bundle.
# Usage: scripts/build_app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/FlowLocal"
APP="$ROOT/FlowLocal.app"
CONTENTS="$APP/Contents"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/FlowLocal"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

echo "==> codesign with 'FlowLocal Dev' certificate (with entitlements)"
codesign --force --deep --sign "FlowLocal Dev" \
  --entitlements "$ROOT/Resources/FlowLocal.entitlements" \
  --options runtime \
  "$APP" 2>/dev/null || \
codesign --force --deep --sign "FlowLocal Dev" \
  --entitlements "$ROOT/Resources/FlowLocal.entitlements" \
  "$APP"

echo "==> done: $APP"
echo "    Launch with: open \"$APP\"   (or run the binary directly: $CONTENTS/MacOS/FlowLocal)"
