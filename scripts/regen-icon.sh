#!/usr/bin/env bash
# Regenerate Resources/AppIcon.icns from the Swift drawing in
# Sources/AVPainRelieverApp/AppIcon.swift.
#
# Steps:
#   1. Render the icon at 1024×1024 to a PNG via render-app-icon.swift.
#   2. Use sips to downscale to every size a .icns wants.
#   3. Pack the iconset directory with iconutil.
#
# Run after any change to AppIcon.swift's drawing routine. Commit the
# updated .icns alongside the source change so Finder + Dock show
# what the runtime drawing shows.
#
# Usage:
#   scripts/regen-icon.sh
#
# Exits non-zero on the first failing step.

set -euo pipefail

cd "$(dirname "$0")/.."

ICONSET_DIR="$(mktemp -d -t avpain-iconset)/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

MASTER_PNG="$ICONSET_DIR/icon_512x512@2x.png"

echo "==> rendering 1024×1024 master via render-app-icon.swift"
swift scripts/render-app-icon.swift "$MASTER_PNG"

echo "==> downscaling for all .icns sizes"
# iconutil expects this exact filename pattern for each size variant.
# Pairs are: <target-filename> <pixel-dimension>.
declare -a sizes=(
    "icon_16x16.png 16"
    "icon_16x16@2x.png 32"
    "icon_32x32.png 32"
    "icon_32x32@2x.png 64"
    "icon_128x128.png 128"
    "icon_128x128@2x.png 256"
    "icon_256x256.png 256"
    "icon_256x256@2x.png 512"
    "icon_512x512.png 512"
    # icon_512x512@2x.png is the master itself — already 1024.
)
for entry in "${sizes[@]}"; do
    name="${entry% *}"
    px="${entry##* }"
    sips -z "$px" "$px" "$MASTER_PNG" --out "$ICONSET_DIR/$name" >/dev/null
done

echo "==> packing into Resources/AppIcon.icns"
iconutil -c icns "$ICONSET_DIR" -o Resources/AppIcon.icns

echo
echo "✓ wrote Resources/AppIcon.icns"
echo "  preview the iconset dir at: $ICONSET_DIR"
