#!/usr/bin/env bash
# wizard.sh — entry point for the av-pain-reliever onboarding wizard.
# Usage:
#   ./wizard.sh                        # full first-time install (default)
#   ./wizard.sh install                # same as above
#   ./wizard.sh add-location           # capture USB / audio for one new location
#   ./wizard.sh status                 # diagnostic: what's installed, what's running
#
# Flags:
#   --dry-run, -n   Show what would happen without doing it. Prompts still
#                   appear so you can walk through the flow; nothing is
#                   installed, nothing written, no commands run.

# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Parse flags out of $@ before dispatching to the subcommand.
DRY_RUN=0
positional=()
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n)
      DRY_RUN=1
      ;;
    *)
      positional+=("$arg")
      ;;
  esac
done
export DRY_RUN
set -- "${positional[@]:-}"

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
  $0 [--dry-run] [command]

Commands:
  install          Run the full first-time install (default).
  add-location     Capture USB devices and audio for one new location.
                   Run this while docked at the location you're capturing.
  status           Show what's installed, what's running, and the recent log.
  help             Show this message.

Flags:
  --dry-run, -n    Walk through the flow without doing any actual work.
                   Useful for previewing what install or add-location will do
                   on your machine before committing to the changes.

Examples:
  $0                            # run the full install
  $0 --dry-run install          # preview the install without doing it
  $0 -n add-location            # preview a location capture
  $0 status                     # diagnostic snapshot
EOF
    ;;
  *)
    fail "Unknown command: $cmd. Run '$0 help' for usage."
    ;;
esac
