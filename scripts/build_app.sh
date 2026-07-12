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
# Strip extended attributes (quarantine, provenance, resource forks) that macOS adds when
# the app is launched — codesign refuses to sign a bundle carrying them ("detritus not allowed").
xattr -cr "$APP"

echo "==> codesign (identity: $SIGN_ID)"
codesign --force --deep --sign "$SIGN_ID" \
  --entitlements "$ROOT/Resources/FlowLocal.entitlements" \
  --options runtime \
  "$APP"

# Fail loudly rather than shipping a stale/ad-hoc binary: a broken signature silently
# breaks Accessibility (TCC) and thus the global hotkey. Use the non-strict check that TCC
# itself uses — --strict trips on the harmless com.apple.FinderInfo xattr that iCloud stamps
# on the bundle when the repo lives in a synced folder (e.g. ~/Desktop).
codesign --verify "$APP" || { echo "❌ codesign verify failed"; exit 1; }
codesign --verify -R="anchor trusted" "$APP" >/dev/null 2>&1 || \
  codesign --display -r- "$APP" 2>&1 | grep -q "com.oxygenflow.app" || \
  { echo "❌ signature does not satisfy the expected designated requirement"; exit 1; }

echo "==> done: $APP"
echo "    Launch with: open \"$APP\"   (or run the binary directly: $CONTENTS/MacOS/FlowLocal)"
