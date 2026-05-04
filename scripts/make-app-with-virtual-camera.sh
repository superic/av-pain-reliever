#!/usr/bin/env bash
# Build a v0.2.0+ AVPainReliever.app with the Camera Extension
# embedded. The default v0.1.x pipeline (`scripts/make-app.sh`) is
# untouched — that script keeps shipping the no-virtual-camera build
# from `main` while v0.2.0 is built from `feature/virtual-camera`.
#
# This script is the parallel-track v0.2.0 builder. Same SPM build,
# additional Camera Extension target, additional embedding step,
# different entitlements file.
#
# Run from the repo root:
#
#   scripts/make-app-with-virtual-camera.sh                       # ad-hoc dev build
#   VERSION=0.2.0 scripts/make-app-with-virtual-camera.sh         # stamp version
#   MAC_CERT_NAME="Developer ID Application: Eric Willis (TEAMID)" \
#     VERSION=0.2.0 scripts/make-app-with-virtual-camera.sh       # signed release build
#
# Output:
#   dist/AVPainReliever.app          — bundle with embedded camera extension
#   dist/AVPainReliever.app.zip      — ditto'd zip
#
# Dev workflow note: ad-hoc-signed builds will only activate on a
# machine with `systemextensionsctl developer on`. See
# docs/VIRTUAL_CAMERA_DEV.md for the full local-test recipe.

set -euo pipefail

cd "$(dirname "$0")/.."

# ---------- inputs ----------
APP_NAME="AVPainReliever"
EXEC_NAME="AVPainRelieverApp"
BUNDLE_ID="com.ericwillis.avpainreliever"

EXT_PRODUCT="AVPainRelieverCameraExtension"
EXT_BUNDLE_ID="${BUNDLE_ID}.CameraExtension"
EXT_DIR_NAME="${EXT_BUNDLE_ID}.systemextension"

if [[ -z "${VERSION:-}" ]]; then
    if VERSION="$(git describe --tags --always --dirty 2>/dev/null)"; then
        VERSION="${VERSION#v}"
    else
        VERSION="0.0.0-dev"
    fi
fi

BUILD_VERSION="${BUILD_VERSION:-$VERSION}"

DIST_DIR="dist"

WORK_DIR="$(mktemp -d -t avpainreliever)"
trap 'rm -rf "$WORK_DIR"' EXIT
APP_BUNDLE="$WORK_DIR/$APP_NAME.app"
EXT_BUNDLE="$APP_BUNDLE/Contents/Library/SystemExtensions/$EXT_DIR_NAME"
FINAL_BUNDLE="$DIST_DIR/$APP_NAME.app"
FINAL_ZIP="$DIST_DIR/$APP_NAME.app.zip"

APP_ENTITLEMENTS="Resources/AVPainReliever-WithVirtualCamera.entitlements"
EXT_ENTITLEMENTS="Resources/AVPainRelieverCameraExtension.entitlements"

# ---------- 1. clean ----------
echo "==> cleaning $DIST_DIR/"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# ---------- 2. build both products ----------
echo "==> swift build (release, universal arm64+x86_64, both products)"
swift build -c release \
    --arch arm64 --arch x86_64 \
    --product "$EXEC_NAME"
swift build -c release \
    --arch arm64 --arch x86_64 \
    --product "$EXT_PRODUCT"

BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --product "$EXEC_NAME" --show-bin-path)"
APP_BINARY="$BIN_PATH/$EXEC_NAME"
EXT_BINARY="$BIN_PATH/$EXT_PRODUCT"

[[ -f "$APP_BINARY" ]] || { echo "error: app binary not built at $APP_BINARY" >&2; exit 1; }
[[ -f "$EXT_BINARY" ]] || { echo "error: extension binary not built at $EXT_BINARY" >&2; exit 1; }

# ---------- 3. assemble main app bundle ----------
echo "==> assembling $APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Library/SystemExtensions"

cp "$APP_BINARY" "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"

install_name_tool -add_rpath \
    "@executable_path/../Frameworks" \
    "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"

cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

sed \
    -e "s|__MARKETING_VERSION__|$VERSION|g" \
    -e "s|__BUILD_VERSION__|$BUILD_VERSION|g" \
    Resources/Info.plist > "$APP_BUNDLE/Contents/Info.plist"

# ---------- 4. assemble Camera Extension bundle ----------
echo "==> assembling $EXT_DIR_NAME"
mkdir -p "$EXT_BUNDLE/Contents/MacOS"

cp "$EXT_BINARY" "$EXT_BUNDLE/Contents/MacOS/$EXT_PRODUCT"
chmod +x "$EXT_BUNDLE/Contents/MacOS/$EXT_PRODUCT"

sed \
    -e "s|__MARKETING_VERSION__|$VERSION|g" \
    -e "s|__BUILD_VERSION__|$BUILD_VERSION|g" \
    Resources/AVPainRelieverCameraExtension-Info.plist \
    > "$EXT_BUNDLE/Contents/Info.plist"

# ---------- 5. embed Sparkle (same as v0.1.x) ----------
SPARKLE_FRAMEWORK_SRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK_SRC" ]]; then
    echo "error: Sparkle framework not found at $SPARKLE_FRAMEWORK_SRC — run 'swift package resolve' first" >&2
    exit 1
fi
echo "==> embedding Sparkle.framework"
cp -R "$SPARKLE_FRAMEWORK_SRC" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# ---------- 6. sign (inside-out) ----------
if [[ -n "${MAC_CERT_NAME:-}" ]]; then
    SIGN_IDENTITY="$MAC_CERT_NAME"
    SIGN_OPTS=(--options runtime --timestamp)
    echo "==> codesign with Developer ID: $SIGN_IDENTITY"
else
    SIGN_IDENTITY="-"
    SIGN_OPTS=()
    echo "==> ad-hoc sign (MAC_CERT_NAME unset; dev-only — needs systemextensionsctl developer on)"
fi

sign_path() {
    local path="$1"
    shift
    xattr -cr "$path" 2>/dev/null || true
    xattr -d com.apple.FinderInfo "$path" 2>/dev/null || true
    codesign --force --sign "$SIGN_IDENTITY" ${SIGN_OPTS[@]+"${SIGN_OPTS[@]}"} "$@" "$path"
}

# Sparkle nested bundles (inside-out, same as make-app.sh)
SPARKLE_DIR="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
SPARKLE_NESTED=(
    "$SPARKLE_DIR/XPCServices/Downloader.xpc"
    "$SPARKLE_DIR/XPCServices/Installer.xpc"
    "$SPARKLE_DIR/Updater.app"
    "$SPARKLE_DIR/Autoupdate"
)
for path in "${SPARKLE_NESTED[@]}"; do
    [[ -e "$path" ]] && sign_path "$path"
done
sign_path "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Camera Extension — signed before the host app so the host's
# signature covers a finalized extension bundle.
sign_path "$EXT_BUNDLE" --entitlements "$EXT_ENTITLEMENTS"

# Main app, with v0.2.0 entitlements (system-extension.install).
sign_path "$APP_BUNDLE" --entitlements "$APP_ENTITLEMENTS"

echo "==> verify codesign"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$EXT_BUNDLE"

# ---------- 7. move into dist/ + zip ----------
echo "==> moving signed bundle to $FINAL_BUNDLE"
ditto "$APP_BUNDLE" "$FINAL_BUNDLE"

echo "==> ditto $FINAL_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$FINAL_BUNDLE" "$FINAL_ZIP"

echo
echo "✓ built $FINAL_BUNDLE"
echo "  version:   $VERSION  (build $BUILD_VERSION)"
echo "  extension: $EXT_DIR_NAME"
echo "  zip:       $FINAL_ZIP ($(stat -f%z "$FINAL_ZIP") bytes)"
echo
echo "next: see docs/VIRTUAL_CAMERA_DEV.md for activation + Zoom test"
