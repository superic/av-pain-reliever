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
# docs/virtual-camera-dev.md for the full local-test recipe.

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

# Team ID is parsed out of MAC_CERT_NAME for the extension's
# CMIOExtensionMachServiceName, which must be "<TEAMID>.<bundleID>".
# Apple's CodeSigningHelper validates the registered service name
# against the bundle's signing identity at activation time.
if [[ -n "${MAC_CERT_NAME:-}" ]]; then
    TEAM_ID="$(printf '%s' "$MAC_CERT_NAME" | sed -nE 's/.*\(([A-Z0-9]+)\)$/\1/p')"
    if [[ -z "$TEAM_ID" ]]; then
        echo "error: could not parse team ID from MAC_CERT_NAME='$MAC_CERT_NAME'" >&2
        echo "       expected format: 'Developer ID Application: Name (TEAMID)'" >&2
        exit 1
    fi
else
    # Ad-hoc builds won't activate properly anyway; placeholder keeps
    # the substitution from leaving the literal __TEAM_ID__ in the
    # plist and confusing diagnostics later.
    TEAM_ID="ADHOC"
fi

DIST_DIR="dist"

WORK_DIR="$(mktemp -d -t avpainreliever)"
trap 'rm -rf "$WORK_DIR"' EXIT
APP_BUNDLE="$WORK_DIR/$APP_NAME.app"
EXT_BUNDLE="$APP_BUNDLE/Contents/Library/SystemExtensions/$EXT_DIR_NAME"
FINAL_BUNDLE="$DIST_DIR/$APP_NAME.app"
FINAL_ZIP="$DIST_DIR/$APP_NAME.app.zip"

APP_ENTITLEMENTS="Resources/AVPainReliever-WithVirtualCamera.entitlements"
EXT_ENTITLEMENTS="Resources/AVPainRelieverCameraExtension.entitlements"
APP_PROVISIONING_PROFILE="Resources/AVPainReliever.provisionprofile"

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
    -e "s|__TEAM_ID__|$TEAM_ID|g" \
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

# ---------- 6. embed provisioning profile ----------
# System extensions activated outside `systemextensionsctl developer
# on` mode must be backed by a provisioning profile that grants the
# `com.apple.developer.system-extension.install` entitlement to the
# host app. The profile is generated once at developer.apple.com
# (Profiles → New → Developer ID, bound to the host App ID with the
# System Extension capability enabled) and dropped into Resources/.
# It is gitignored — each developer / CI environment ships its own.
#
# We require it for Developer-ID-signed builds and warn (but allow)
# ad-hoc builds without it, since the ad-hoc path is for the
# fallback developer-mode workflow that doesn't honour profiles
# anyway. See docs/virtual-camera-dev.md.
if [[ -n "${MAC_CERT_NAME:-}" ]]; then
    if [[ ! -f "$APP_PROVISIONING_PROFILE" ]]; then
        cat <<EOF >&2
error: MAC_CERT_NAME is set but no provisioning profile is present at:
         $APP_PROVISIONING_PROFILE

Developer-ID-signed builds that bundle a system extension MUST
embed a provisioning profile carrying the
'com.apple.developer.system-extension.install' entitlement, or the
extension activation request will fail at runtime.

Generate one at developer.apple.com:
  - Identifiers: ensure App ID 'com.ericwillis.avpainreliever' has
    the 'System Extension' capability enabled.
  - Profiles: New → Developer ID → select the App ID → download.

Save the .provisionprofile at the path above (it's gitignored).
See docs/virtual-camera-dev.md for the full walkthrough.
EOF
        exit 1
    fi
    echo "==> embedding provisioning profile"
    cp "$APP_PROVISIONING_PROFILE" "$APP_BUNDLE/Contents/embedded.provisionprofile"
elif [[ -f "$APP_PROVISIONING_PROFILE" ]]; then
    # Ad-hoc + profile present is a misconfiguration — codesign will
    # accept it but macOS won't honour an unsigned profile at runtime.
    echo "warning: ad-hoc sign with provisioning profile present — profile will be ignored. Set MAC_CERT_NAME for a properly-signed build." >&2
fi

# ---------- 7. sign (inside-out) ----------
if [[ -n "${MAC_CERT_NAME:-}" ]]; then
    SIGN_IDENTITY="$MAC_CERT_NAME"
    SIGN_OPTS=(--options runtime --timestamp)
    echo "==> codesign with Developer ID: $SIGN_IDENTITY"
else
    SIGN_IDENTITY="-"
    SIGN_OPTS=()
    echo "==> ad-hoc sign (MAC_CERT_NAME unset; needs systemextensionsctl developer on + SIP off — see docs/virtual-camera-dev.md fallback)"
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

# ---------- 8. notarize (required for system extension activation) ----------
# Even with valid Developer ID signing, macOS refuses to activate a
# system extension whose bundle isn't notarized. The validation
# error in sysextd surfaces as "bundle code signature is not valid
# - does not satisfy requirement: -67050" with "Error checking with
# notarization daemon."
#
# Gated by NOTARIZE_KEYCHAIN_PROFILE so quick iteration builds
# (e.g., compile-only sanity checks) can skip the round trip. The
# CI pipeline uses APPLE_ID + APPLE_ID_PASSWORD + APPLE_TEAM_ID
# instead — set NOTARIZE_KEYCHAIN_PROFILE locally to use the
# `avpain-notary` keychain profile instead of typing the password.
if [[ -n "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
    echo "==> notarizing (keychain profile: $NOTARIZE_KEYCHAIN_PROFILE)"
    NOTARIZE_ZIP="$WORK_DIR/notarize.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$NOTARIZE_ZIP"
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE" \
        --wait
    echo "==> stapling notarization ticket"
    # Staple the app first; the embedded extension inherits the
    # ticket through the bundle structure.
    xcrun stapler staple "$APP_BUNDLE"
elif [[ -n "${MAC_CERT_NAME:-}" ]]; then
    echo "warning: signed build without notarization. System-extension"
    echo "         activation will fail with sysextd code -67050."
    echo "         Set NOTARIZE_KEYCHAIN_PROFILE=avpain-notary to fix." >&2
fi

# ---------- 9. move into dist/ + zip ----------
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
echo "next: see docs/virtual-camera-dev.md for activation + Zoom test"
