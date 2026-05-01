#!/usr/bin/env bash
# wizard.sh — entry point for the av-pain-reliever onboarding wizard.
# Usage:
#   ./wizard.sh                  # full first-time install (default)
#   ./wizard.sh install          # same as above
#   ./wizard.sh add-location     # capture USB / audio for one new location
#   ./wizard.sh status           # diagnostic: what's installed, what's running

# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/wizard/lib.sh"

cmd="${1:-install}"
shift || true

case "$cmd" in
  install)
    exec "$SCRIPT_DIR/wizard/install.sh" "$@"
    ;;
  add-location|add)
    exec "$SCRIPT_DIR/wizard/add-location.sh" "$@"
    ;;
  status)
    exec "$SCRIPT_DIR/wizard/status.sh" "$@"
    ;;
  -h|--help|help)
    cat <<EOF
av-pain-reliever wizard

Usage:
  $0                  Run the full first-time install (default).
  $0 install          Same as above.
  $0 add-location     Capture USB devices and audio for one new location.
                      Run this while docked at the location you're capturing.
  $0 status           Show what's installed, what's running, and the recent log.
  $0 help             Show this message.
EOF
    ;;
  *)
    fail "Unknown command: $cmd. Run '$0 help' for usage."
    ;;
esac
