#!/usr/bin/env bash
# Sign an .app.zip with the Sparkle EdDSA private key and emit a
# ready-to-paste <item> block for appcast.xml.
#
# Usage:
#   SPARKLE_PRIVATE_KEY="$(cat key.txt)" \
#   VERSION=0.1.0 \
#   scripts/sign-appcast.sh dist/AVPainReliever.app.zip
#
# Or, when working from your login keychain (no env var):
#   VERSION=0.1.0 scripts/sign-appcast.sh dist/AVPainReliever.app.zip
#
# Optional inputs:
#   - $RELEASE_NOTES_HTML  Pre-rendered HTML embedded as the item's
#                          <description>. Sparkle uses this to populate
#                          its "What's New" panel.
#
# Outputs to stdout:
#   - The full <item> block (URL placeholder included; replace before
#     committing to appcast.xml).
# Outputs to stderr:
#   - Progress + diagnostic notes.

set -euo pipefail

cd "$(dirname "$0")/.."

ZIP="${1:?usage: sign-appcast.sh <path-to-app-zip>}"
if [[ ! -f "$ZIP" ]]; then
    echo "error: $ZIP not found" >&2
    exit 1
fi

VERSION="${VERSION:-}"
if [[ -z "$VERSION" ]]; then
    echo "error: VERSION env var required (e.g. VERSION=0.1.0)" >&2
    exit 1
fi

SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
if [[ ! -x "$SIGN_UPDATE" ]]; then
    echo "error: sign_update not found at $SIGN_UPDATE — run 'swift package resolve' first" >&2
    exit 1
fi

# sign_update reads the private key from one of:
#   - $SPARKLE_PRIVATE_KEY env var (used in CI)
#   - login keychain via the avpainreliever account (used locally)
# It writes a `sparkle:edSignature="..." length="..."` line to stdout.
echo "==> signing $ZIP" >&2
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    SIG_LINE="$(echo -n "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - "$ZIP")"
else
    SIG_LINE="$("$SIGN_UPDATE" --account avpainreliever "$ZIP")"
fi
echo "==> got: $SIG_LINE" >&2

ZIP_NAME="$(basename "$ZIP")"
PUBDATE="$(LC_TIME=en_US.UTF-8 TZ=UTC date '+%a, %d %b %Y %H:%M:%S +0000')"
ASSET_URL="https://github.com/superic/av-pain-reliever/releases/download/v$VERSION/$ZIP_NAME"

# Optional: $RELEASE_NOTES_HTML is rendered HTML for the <description>
# field. When set, Sparkle expands its update window with a "What's
# New" panel. CDATA-wrapping keeps the HTML's `<` / `>` characters
# legal inside the appcast XML.
DESCRIPTION_BLOCK=""
if [[ -n "${RELEASE_NOTES_HTML:-}" ]]; then
    DESCRIPTION_BLOCK="            <description><![CDATA[
${RELEASE_NOTES_HTML}
]]></description>
"
fi

cat <<XML
        <item>
            <title>Version $VERSION</title>
${DESCRIPTION_BLOCK}            <pubDate>$PUBDATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="$ASSET_URL"
                       type="application/octet-stream"
                       $SIG_LINE />
        </item>
XML
