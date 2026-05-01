#!/usr/bin/env bash
# wizard/lib.sh — shared helpers sourced by every wizard subscript.

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$LIB_DIR")"
HAMMERSPOON_DIR="$HOME/.hammerspoon"
PROFILES_FILE="$REPO_ROOT/profiles.lua"
LOG_FILE="$HAMMERSPOON_DIR/logs/av-pain-reliever.log"

export LIB_DIR REPO_ROOT HAMMERSPOON_DIR PROFILES_FILE LOG_FILE

# ---------- styling ----------

# Print a styled banner. Falls back to plain text if gum isn't installed yet.
banner() {
  if command -v gum >/dev/null 2>&1; then
    gum style --border double --margin "1 0" --padding "0 2" --border-foreground 212 "$@"
  else
    printf '\n══ %s ══\n\n' "$*"
  fi
}

step() {
  if command -v gum >/dev/null 2>&1; then
    gum style --foreground 212 --bold "▶ $*"
  else
    printf '\n▶ %s\n' "$*"
  fi
}

info()    { printf '  %s\n' "$*"; }
success() { printf '  ✓ %s\n' "$*"; }
warn()    { printf '  ⚠ %s\n' "$*" >&2; }
fail()    { printf '  ✗ %s\n' "$*" >&2; exit 1; }

# ---------- prompts (gum wrappers) ----------

# confirm "Question?" -> exits with 0 if yes, 1 if no. Use in `if confirm ...; then`.
confirm() {
  if command -v gum >/dev/null 2>&1; then
    gum confirm "$*"
  else
    local reply
    read -r -p "$* [y/N] " reply
    [[ "$reply" =~ ^[Yy] ]]
  fi
}

# choose_one "Prompt" "opt1" "opt2" ... -> echoes selected option
choose_one() {
  local prompt="$1"; shift
  if command -v gum >/dev/null 2>&1; then
    gum choose --header "$prompt" "$@"
  else
    PS3="$prompt "
    select choice in "$@"; do
      [[ -n "$choice" ]] && { echo "$choice"; return 0; }
    done
  fi
}

# choose_multi "Prompt" "opt1" "opt2" ... -> echoes newline-separated selection
choose_multi() {
  local prompt="$1"; shift
  if command -v gum >/dev/null 2>&1; then
    gum choose --no-limit --header "$prompt" "$@"
  else
    warn "Multi-select fallback without gum is not implemented. Install gum: brew install gum"
    return 1
  fi
}

# input_text "Prompt" [placeholder] -> echoes entered text
input_text() {
  local prompt="$1"
  local placeholder="${2:-}"
  if command -v gum >/dev/null 2>&1; then
    gum input --header "$prompt" --placeholder "$placeholder"
  else
    local reply
    read -r -p "$prompt: " reply
    echo "$reply"
  fi
}

# input_lines "Prompt" -> echoes multi-line input until empty line / Ctrl-D
input_lines() {
  local prompt="$1"
  if command -v gum >/dev/null 2>&1; then
    gum write --header "$prompt" --width 60 --height 8
  else
    info "$prompt (one per line, blank line to finish):"
    local line
    while IFS= read -r line; do
      [[ -z "$line" ]] && break
      echo "$line"
    done
  fi
}

# ---------- prerequisites ----------

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "This wizard only runs on macOS."
}

require_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    fail "Homebrew is required. Install it from https://brew.sh and re-run this wizard."
  fi
}

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    fail "GitHub CLI (gh) is required. Install with: brew install gh"
  fi
  if ! gh auth status >/dev/null 2>&1; then
    fail "GitHub CLI is installed but not authenticated. Run: gh auth login"
  fi
}

bootstrap_gum() {
  if command -v gum >/dev/null 2>&1; then return 0; fi
  step "Installing gum (one-time, gives this wizard a nicer UI)"
  brew install gum >/dev/null
  command -v gum >/dev/null 2>&1 || fail "gum install failed"
  success "gum installed"
}

# ---------- slug helpers ----------

# Convert "Home Office" -> "home-office"
to_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Convert "home-office" -> "Home Office"
to_pretty() {
  printf '%s' "$1" | tr '-' ' ' | awk '{ for (i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print }'
}

# ---------- arch helpers ----------

obs_cmd_asset() {
  case "$(uname -m)" in
    arm64) echo "obs-cmd-arm64-macos.tar.gz" ;;
    x86_64) echo "obs-cmd-x64-macos.tar.gz" ;;
    *) fail "Unsupported architecture: $(uname -m)" ;;
  esac
}

obs_cmd_install_dir() {
  if [[ -d /opt/homebrew/bin ]]; then
    echo "/opt/homebrew/bin"
  else
    echo "/usr/local/bin"
  fi
}
