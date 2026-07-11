#!/bin/bash
# Regenerate the Cobalt Flow app icon (Resources/AppIcon.icns) from the vector
# drawing in make_icon.swift. Run from the project root: scripts/make_icon.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift scripts/make_icon.swift

OUT="scripts/.icon-out"
ICONSET="$OUT/AppIcon.iconset"
M="$OUT/master-1024.png"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"

specs=("16:icon_16x16.png" "32:icon_16x16@2x.png" "32:icon_32x32.png" \
       "64:icon_32x32@2x.png" "128:icon_128x128.png" "256:icon_128x128@2x.png" \
       "256:icon_256x256.png" "512:icon_256x256@2x.png" "512:icon_512x512.png" \
       "1024:icon_512x512@2x.png")
for s in "${specs[@]}"; do
  px="${s%%:*}"; name="${s##*:}"
  sips -z "$px" "$px" "$M" --out "$ICONSET/$name" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "==> wrote Resources/AppIcon.icns"
