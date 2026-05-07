#!/usr/bin/env bash
# Build a distributable AVPainReliever.app from the SPM executable
# target. Run from the repo root:
#
#   scripts/make-app.sh                        # ad-hoc-signed local dev build
#   VERSION=0.1.0 scripts/make-app.sh          # stamp marketing version
#   MAC_CERT_NAME="Developer ID Application: Eric Willis (TEAMID)" \
#     VERSION=0.1.0 scripts/make-app.sh        # signed release build
#
# Output:
#   dist/AVPainReliever.app          — bundle ready to drag to /Applications
#   dist/AVPainReliever.app.zip      — ditto'd zip for upload / notarization

set -euo pipefail

cd "$(dirname "$0")/.."

# ---------- inputs ----------
APP_NAME="AVPainReliever"
EXEC_NAME="AVPainRelieverApp"
BUNDLE_ID="com.ericwillis.avpainreliever"

# Version: explicit env wins; else strip a leading "v" off git describe;
# else "0.0.0-dev" so unsigned local builds always have something legal.
if [[ -z "${VERSION:-}" ]]; then
    if VERSION="$(git describe --tags --always --dirty 2>/dev/null)"; then
        VERSION="${VERSION#v}"
    else
        VERSION="0.0.0-dev"
    fi
fi

# CFBundleVersion has to be a monotonic integer-ish thing for Sparkle's
# version comparator to work cleanly. Default to the marketing version
# (Sparkle handles dotted strings) but allow override via $BUILD_VERSION.
BUILD_VERSION="${BUILD_VERSION:-$VERSION}"

DIST_DIR="dist"

# Assemble in a temp directory rather than directly under dist/.
# ~/Documents is iCloud-watched on default macOS installs — the
# fileprovider daemon races with codesign, re-adding com.apple.FinderInfo
# to the bundle root in the milliseconds between our xattr scrub and
# codesign's read. Working in /tmp (not synced) sidesteps the race
# entirely. We move the finished bundle back to dist/ at the end.
WORK_DIR="$(mktemp -d -t avpainreliever)"
trap 'rm -rf "$WORK_DIR"' EXIT
APP_BUNDLE="$WORK_DIR/$APP_NAME.app"
FINAL_BUNDLE="$DIST_DIR/$APP_NAME.app"
FINAL_ZIP="$DIST_DIR/$APP_NAME.app.zip"

# ---------- 1. clean ----------
echo "==> cleaning $DIST_DIR/"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# ---------- 2. build universal binary ----------
# `swift build` accepts repeated --arch flags to produce a universal
# binary in one shot. Fallback (lipo two single-arch builds) is documented
# in docs/releasing.md if Apple ever regresses this.
echo "==> swift build (release, universal arm64+x86_64)"
swift build -c release \
    --arch arm64 --arch x86_64 \
    --product "$EXEC_NAME"

BIN_PATH="$(swift build -c release --arch arm64 --arch x86_64 --product "$EXEC_NAME" --show-bin-path)"
SRC_BINARY="$BIN_PATH/$EXEC_NAME"

if [[ ! -f "$SRC_BINARY" ]]; then
    echo "error: built binary not found at $SRC_BINARY" >&2
    exit 1
fi

# ---------- 3. assemble bundle ----------
echo "==> assembling $APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp "$SRC_BINARY" "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"

# SPM only injects @executable_path/../lib as a runtime rpath; the
# Sparkle binary expects to be found under @executable_path/../Frameworks.
# Patch the rpath into the binary post-build.
install_name_tool -add_rpath \
    "@executable_path/../Frameworks" \
    "$APP_BUNDLE/Contents/MacOS/$EXEC_NAME"

cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Stamp the version placeholders in Info.plist as we copy. Use a |
# delimiter for sed so any future URL-bearing placeholder doesn't
# collide with /.
sed \
    -e "s|__MARKETING_VERSION__|$VERSION|g" \
    -e "s|__BUILD_VERSION__|$BUILD_VERSION|g" \
    Resources/Info.plist > "$APP_BUNDLE/Contents/Info.plist"

# Embed Sparkle.framework. The SPM artifact ships as an xcframework;
# we copy the universal macOS slice into Contents/Frameworks so the
# main binary's @rpath resolves at runtime. Sparkle's framework
# already contains its own helper apps (Updater.app, Autoupdate,
# Downloader.xpc, Installer.xpc) that codesign treats as nested
# bundles — we sign each one individually below.
SPARKLE_FRAMEWORK_SRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK_SRC" ]]; then
    echo "error: Sparkle framework not found at $SPARKLE_FRAMEWORK_SRC — run 'swift package resolve' first" >&2
    exit 1
fi
echo "==> embedding Sparkle.framework"
cp -R "$SPARKLE_FRAMEWORK_SRC" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# ---------- 4. sign ----------
# Each codesign call scrubs xattrs first via the sign_path helper —
# macOS re-adds com.apple.provenance on every copy, so a one-shot
# scrub up here would not stick.
ENTITLEMENTS="Resources/AVPainReliever.entitlements"

# Sparkle's nested helper bundles + XPC services must be signed
# individually (inside-out) so each gets a designated requirement
# matching our Team ID. Apple's deep-sign flag is deprecated and
# notarization rejects it; signing nested bundles by path is the
# supported approach. Order: deepest leaves first, then framework,
# then the main app.
SPARKLE_DIR="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
SPARKLE_NESTED=(
    "$SPARKLE_DIR/XPCServices/Downloader.xpc"
    "$SPARKLE_DIR/XPCServices/Installer.xpc"
    "$SPARKLE_DIR/Updater.app"
    "$SPARKLE_DIR/Autoupdate"
)

if [[ -n "${MAC_CERT_NAME:-}" ]]; then
    SIGN_IDENTITY="$MAC_CERT_NAME"
    SIGN_OPTS=(--options runtime --timestamp)
    echo "==> codesign with Developer ID: $SIGN_IDENTITY"
else
    SIGN_IDENTITY="-"
    SIGN_OPTS=()
    echo "==> ad-hoc sign (MAC_CERT_NAME unset; this build is dev-only)"
fi

# Sparkle's tarball ships with com.apple.FinderInfo on several inner
# files; macOS also auto-adds it to bundle roots on filesystem touch.
# codesign refuses to sign anything carrying that xattr. We scrub
# both recursively (catches the inherited ones) and once more at the
# target path immediately before signing (catches the racy re-adds).
sign_path() {
    local path="$1"
    shift
    xattr -cr "$path" 2>/dev/null || true
    xattr -d com.apple.FinderInfo "$path" 2>/dev/null || true
    codesign --force --sign "$SIGN_IDENTITY" ${SIGN_OPTS[@]+"${SIGN_OPTS[@]}"} "$@" "$path"
}

for path in "${SPARKLE_NESTED[@]}"; do
    [[ -e "$path" ]] && sign_path "$path"
done

sign_path "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Main app (with entitlements). The XPCs and Updater.app intentionally
# don't take our entitlements — they have their own from the Sparkle
# project and must keep them.
sign_path "$APP_BUNDLE" --entitlements "$ENTITLEMENTS"

echo "==> verify codesign"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

# ---------- 5. move into dist/ + zip ----------
# Use ditto rather than mv: it preserves bundle structure cleanly
# even across filesystems and won't reintroduce xattrs that codesign
# would have rejected (we're already signed, so xattrs from this
# point on don't matter).
echo "==> moving signed bundle to $FINAL_BUNDLE"
ditto "$APP_BUNDLE" "$FINAL_BUNDLE"

echo "==> ditto $FINAL_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$FINAL_BUNDLE" "$FINAL_ZIP"

echo
echo "✓ built $FINAL_BUNDLE"
echo "  version: $VERSION  (build $BUILD_VERSION)"
echo "  zip:     $FINAL_ZIP ($(stat -f%z "$FINAL_ZIP") bytes)"
echo
echo "next: open $FINAL_BUNDLE  # or drag it to /Applications"
