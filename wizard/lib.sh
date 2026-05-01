#!/usr/bin/env bash
# wizard/lib.sh — shared helpers sourced by every wizard subscript.

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(dirname "$LIB_DIR")}"
HAMMERSPOON_DIR="${HAMMERSPOON_DIR:-$HOME/.hammerspoon}"
PROFILES_FILE="${PROFILES_FILE:-$REPO_ROOT/profiles.lua}"
LOG_FILE="${LOG_FILE:-$HAMMERSPOON_DIR/logs/av-pain-reliever.log}"

# DRY_RUN=1 means "show what you would do, don't actually do it." Set by the
# --dry-run flag parsed in wizard.sh. Default off.
DRY_RUN="${DRY_RUN:-0}"

export LIB_DIR REPO_ROOT HAMMERSPOON_DIR PROFILES_FILE LOG_FILE DRY_RUN

# ---------- dry-run helpers ----------

# Print a "would do X" line, color-coded yellow so it stands out.
would() {
  if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    printf '  \033[33m[dry-run]\033[0m %s\n' "$*"
  else
    printf '  [dry-run] %s\n' "$*"
  fi
}

# runcmd <cmd> [args...]
# In normal mode: runs the command. In dry-run mode: prints what it would
# have run, returns 0. Use this for commands that have side effects.
runcmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    would "would run: $*"
    return 0
  fi
  "$@"
}

# runstep <description> <cmd> [args...]
# Like runcmd but with a human-readable description for dry-run output.
# Use when the underlying command is opaque (like a long sudo invocation
# or a script call) and the user benefits from a clearer summary.
runstep() {
  local desc="$1"; shift
  if [[ "$DRY_RUN" == "1" ]]; then
    would "$desc"
    return 0
  fi
  "$@"
}

# write_file <path> [content_via_stdin]
# In normal mode: writes stdin to <path>. In dry-run mode: prints what would
# have been written and a preview of the first few lines.
write_file_dryrun_aware() {
  local path="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    would "would write file: $path"
    local content
    content=$(cat)
    local line_count
    line_count=$(printf '%s' "$content" | wc -l | tr -d ' ')
    would "  (${line_count} lines; first 5 below)"
    printf '%s\n' "$content" | head -5 | sed 's/^/    │ /' | while IFS= read -r line; do
      if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
        printf '  \033[33m[dry-run]\033[0m %s\n' "$line"
      else
        printf '  [dry-run] %s\n' "$line"
      fi
    done
    return 0
  fi
  cat > "$path"
}

# Bail-out helper: emit a one-line dry-run banner if active.
dryrun_banner() {
  [[ "$DRY_RUN" == "1" ]] || return 0
  if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    printf '\n  \033[1;33m━━━ DRY-RUN MODE ━━━\033[0m\n'
    printf '  \033[33mNo files will be written, no commands run, no apps installed.\n'
    printf '  Prompts still appear so you can walk through the flow.\033[0m\n\n'
  else
    printf '\n  ━━━ DRY-RUN MODE ━━━\n'
    printf '  No files will be written, no commands run, no apps installed.\n'
    printf '  Prompts still appear so you can walk through the flow.\n\n'
  fi
}

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
  if [[ "$DRY_RUN" == "1" ]]; then
    would "would 'brew install gum'"
    info "(gum isn't installed yet, so dry-run prompts will use plain bash"
    info " fallbacks instead of gum's colored UI for this run.)"
    return 0
  fi
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

# ---------- Hammerspoon control ----------

# Reload the engine. init.lua calls hs.allowAppleScript(true) on load so this
# works after at least one initial load. Returns 0 on success, nonzero on
# failure (e.g. Hammerspoon not running, AppleScript not enabled yet).
hammerspoon_reload() {
  osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' >/dev/null 2>&1
}

# Reload Hammerspoon and gracefully fall back to a manual prompt if AppleScript
# isn't enabled yet (which happens on the very first install before init.lua's
# hs.allowAppleScript(true) has run). Always returns 0 — caller assumes reload
# happened by the time it returns.
hammerspoon_reload_with_fallback() {
  if hammerspoon_reload; then return 0; fi
  warn "Couldn't reload Hammerspoon programmatically (AppleScript not enabled yet)."
  info "Please click the Hammerspoon menu bar icon (the hammer) and choose 'Reload Config' now."
  if command -v gum >/dev/null 2>&1; then
    gum confirm "Done?" || true
  else
    read -r -p "Press Enter once you've clicked Reload Config: " _
  fi
}
