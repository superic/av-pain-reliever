#!/usr/bin/env bash
# Re-render Resources/AppIcon.icns from the inline pill design in
# scripts/icon-exporter.swift. Run from the repo root. Output is a
# committed binary artifact — re-run only when the icon design changes.

set -euo pipefail

cd "$(dirname "$0")/.."

ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
trap 'rm -rf "$(dirname "$ICONSET_DIR")"' EXIT

mkdir -p "$ICONSET_DIR"

echo "==> rendering PNGs into $ICONSET_DIR"
swift scripts/icon-exporter.swift "$ICONSET_DIR"

echo "==> packaging into Resources/AppIcon.icns"
mkdir -p Resources
iconutil -c icns "$ICONSET_DIR" -o Resources/AppIcon.icns

echo "==> done. Resources/AppIcon.icns is $(stat -f%z Resources/AppIcon.icns) bytes"
