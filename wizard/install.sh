#!/usr/bin/env bash
# wizard/install.sh — full first-time install. Idempotent: rerunning skips
# already-done work and re-confirms anything that needs human input.

# shellcheck disable=SC1091,SC2088
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/lib.sh"

# ---------- step 1: pre-flight ----------
step "Step 1/15 — Pre-flight checks"
require_macos
require_brew
require_gh
success "macOS, Homebrew, and authenticated gh present"

# ---------- step 2: bootstrap gum ----------
step "Step 2/15 — Setup the wizard's UI toolkit"
bootstrap_gum

# ---------- step 3: welcome banner ----------
banner "AV Pain Reliever — guided setup"
info "This wizard installs Hammerspoon, OBS, and the av-pain-reliever engine,"
info "then walks you through capturing one of your dock setups. About 10 minutes."
info ""
info "You'll need to be docked at one of your work locations for the last step."
info ""
if ! confirm "Ready to start?"; then
  info "No problem — re-run this wizard whenever you're ready."
  exit 0
fi

# ---------- step 4: install Hammerspoon ----------
step "Step 4/15 — Install Hammerspoon"
if [[ -d "/Applications/Hammerspoon.app" ]]; then
  success "Hammerspoon already installed"
else
  brew install --cask hammerspoon
  success "Hammerspoon installed"
fi

# ---------- step 5: install OBS Studio ----------
step "Step 5/15 — Install OBS Studio (28+)"
if [[ -d "/Applications/OBS.app" ]]; then
  obs_version=$(defaults read /Applications/OBS.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "0")
  obs_major=$(echo "$obs_version" | cut -d. -f1)
  if [[ "$obs_major" -ge 28 ]]; then
    success "OBS $obs_version present (28+ has obs-websocket built in)"
  else
    warn "OBS $obs_version is older than 28 — upgrading via Homebrew"
    brew install --cask --force obs
  fi
else
  brew install --cask obs
  success "OBS installed"
fi

# ---------- step 6: install obs-cmd ----------
step "Step 6/15 — Install obs-cmd"
INSTALL_DIR=$(obs_cmd_install_dir)
OBS_CMD_PATH="$INSTALL_DIR/obs-cmd"
if [[ -x "$OBS_CMD_PATH" ]]; then
  success "obs-cmd already installed at $OBS_CMD_PATH"
else
  ASSET=$(obs_cmd_asset)
  URL="https://github.com/grigio/obs-cmd/releases/latest/download/$ASSET"
  info "Downloading $ASSET from grigio/obs-cmd releases"
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  curl -sSL -o "$TMPDIR/obs-cmd.tar.gz" "$URL"
  tar -xzf "$TMPDIR/obs-cmd.tar.gz" -C "$TMPDIR"
  info "Installing to $OBS_CMD_PATH (sudo password may be required)"
  sudo mv "$TMPDIR/obs-cmd" "$OBS_CMD_PATH"
  sudo chmod +x "$OBS_CMD_PATH"
  trap - EXIT
  rm -rf "$TMPDIR"
  success "obs-cmd $($OBS_CMD_PATH --version)"
fi

# ---------- step 7: symlink ~/.hammerspoon -> repo ----------
step "Step 7/15 — Wire ~/.hammerspoon to this repo"
if [[ -L "$HAMMERSPOON_DIR" ]]; then
  current=$(readlink "$HAMMERSPOON_DIR")
  if [[ "$current" == "$REPO_ROOT" ]]; then
    success "~/.hammerspoon already symlinked to $REPO_ROOT"
  else
    warn "~/.hammerspoon currently points at $current"
    if confirm "Replace with a link to $REPO_ROOT?"; then
      backup="$HAMMERSPOON_DIR.backup-$(date +%Y%m%d-%H%M%S)"
      mv "$HAMMERSPOON_DIR" "$backup"
      ln -s "$REPO_ROOT" "$HAMMERSPOON_DIR"
      success "Old link backed up to $backup"
    else
      fail "Can't proceed without ~/.hammerspoon pointing at this repo."
    fi
  fi
elif [[ -e "$HAMMERSPOON_DIR" ]]; then
  warn "~/.hammerspoon exists as a real directory (not a symlink)."
  backup="$HAMMERSPOON_DIR.backup-$(date +%Y%m%d-%H%M%S)"
  if confirm "Move it to $backup and create the symlink?"; then
    mv "$HAMMERSPOON_DIR" "$backup"
    ln -s "$REPO_ROOT" "$HAMMERSPOON_DIR"
    success "Backed up to $backup; new symlink in place"
  else
    fail "Can't proceed without ~/.hammerspoon pointing at this repo."
  fi
else
  ln -s "$REPO_ROOT" "$HAMMERSPOON_DIR"
  success "~/.hammerspoon -> $REPO_ROOT"
fi

# ---------- step 8: launch Hammerspoon + Accessibility ----------
step "Step 8/15 — Launch Hammerspoon and grant Accessibility"
if pgrep -x Hammerspoon >/dev/null 2>&1; then
  success "Hammerspoon already running"
else
  open -a Hammerspoon
  sleep 1
fi
info "Hammerspoon needs Accessibility permission to read USB events and switch audio."
info "I'll open the right System Settings pane — toggle Hammerspoon on, enter your password if prompted."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true
if confirm "Done — Hammerspoon is toggled on in Accessibility?"; then
  success "Accessibility granted"
else
  warn "Skipping for now. Audio + USB switching won't work until you grant it."
fi

# ---------- step 9: collect locations ----------
step "Step 9/15 — Name your locations"
info "Enter the locations you switch between. Examples: Home Office, Work Office,"
info "Conference Room, Coffee Shop, Client Site. (You can add more later.)"
info ""
raw_locations=$(input_lines "Locations (one per line, blank to finish)")
declare -a locations=()
while IFS= read -r line; do
  line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  [[ -n "$line" ]] && locations+=("$line")
done <<< "$raw_locations"

# Always include "Laptop" as the undocked fallback at the front of the list.
have_laptop=false
for l in "${locations[@]}"; do
  [[ "$(to_slug "$l")" == "laptop" ]] && have_laptop=true
done
if ! $have_laptop; then
  info "Adding 'Laptop' as the undocked fallback profile."
  locations=("Laptop" "${locations[@]}")
fi

if [[ ${#locations[@]} -lt 2 ]]; then
  fail "Need at least one docked location in addition to Laptop."
fi

info "Locations: ${locations[*]}"

# ---------- step 10: generate profiles.lua ----------
step "Step 10/15 — Generate profiles.lua"
if grep -q '^-- WIZARD_PROFILE_' "$PROFILES_FILE" 2>/dev/null; then
  if ! confirm "profiles.lua already wizard-managed. Overwrite (you'll lose any unsaved manual edits)?"; then
    info "Keeping existing profiles.lua."
  else
    "$LIB_DIR/_generate-profiles.sh" "${locations[@]}"
    success "profiles.lua regenerated"
  fi
else
  if [[ -f "$PROFILES_FILE" ]]; then
    backup="$PROFILES_FILE.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$PROFILES_FILE" "$backup"
    info "Backed up existing profiles.lua to $backup"
  fi
  "$LIB_DIR/_generate-profiles.sh" "${locations[@]}"
  success "profiles.lua written"
fi

# Reload Hammerspoon so it picks up the new profiles.
osascript -e 'tell application "Hammerspoon" to reload' >/dev/null 2>&1 || true

# ---------- step 11: configure obs-websocket ----------
step "Step 11/15 — Enable OBS WebSocket server"
if ! pgrep -x OBS >/dev/null 2>&1; then
  open -a OBS
  info "Launching OBS..."
  sleep 3
fi
if obs-cmd info >/dev/null 2>&1; then
  success "OBS WebSocket already enabled and reachable"
else
  info "In OBS: Tools → WebSocket Server Settings"
  info "  1. Tick 'Enable WebSocket server'"
  info "  2. UNTICK 'Enable Authentication' (local-only, low risk)"
  info "  3. Click Apply / OK"
  while true; do
    confirm "Done?" || true
    if obs-cmd info >/dev/null 2>&1; then
      success "OBS WebSocket reachable"
      break
    fi
    warn "Couldn't reach OBS WebSocket. Make sure OBS is open and the server is enabled."
    if ! confirm "Try again?"; then
      warn "Skipping OBS scene creation. You can re-run the wizard later."
      SKIP_OBS=1
      break
    fi
  done
fi

# ---------- step 12: create OBS scenes ----------
step "Step 12/15 — Create OBS scenes"
if [[ "${SKIP_OBS:-0}" == "1" ]]; then
  warn "Skipping (OBS WebSocket not reachable)"
else
  existing_scenes=$(obs-cmd scene list 2>/dev/null || echo "")
  for loc in "${locations[@]}"; do
    pretty=$(to_pretty "$(to_slug "$loc")")
    if echo "$existing_scenes" | grep -qF "$pretty"; then
      success "Scene '$pretty' already exists"
    else
      if obs-cmd scene create "$pretty" >/dev/null 2>&1; then
        success "Created OBS scene: $pretty"
      else
        warn "Failed to create scene '$pretty' — create it manually in OBS"
      fi
    fi
  done
fi

# ---------- step 13: start virtual camera ----------
step "Step 13/15 — Start OBS Virtual Camera"
if [[ "${SKIP_OBS:-0}" == "1" ]]; then
  warn "Skipping (OBS WebSocket not reachable)"
else
  obs-cmd virtual-camera start >/dev/null 2>&1 || true
  success "Virtual camera output started (it persists across OBS launches)"
  info ""
  info "Now in OBS, click each scene in turn and add your camera as a Video"
  info "Capture Device source. We can't pick the camera for you."
  confirm "Done with at least one scene? (You can finish the rest later)" || true
fi

# ---------- step 14: configure Zoom + Slack ----------
step "Step 14/15 — Configure Zoom and Slack"
configure_app() {
  local app="$1" path="$2"
  if [[ ! -d "$path" ]]; then
    info "$app not installed — skipping"
    return
  fi
  open -a "$app" >/dev/null 2>&1 || true
  info "In $app:"
  info "  • Mic = Same as System"
  info "  • Speaker = Same as System"
  info "  • Camera = OBS Virtual Camera"
  confirm "Done with $app?" || true
}
configure_app "zoom.us" "/Applications/zoom.us.app"
configure_app "Slack"   "/Applications/Slack.app"

# ---------- step 15: capture first location ----------
step "Step 15/15 — Capture your first dock location"
if confirm "Capture USB devices and audio for a location now? (You can do more later with: $REPO_ROOT/wizard.sh add-location)"; then
  "$LIB_DIR/add-location.sh"
fi

banner "Setup complete"
info "Reload Hammerspoon any time with the menu bar icon → Reload Config."
info ""
info "Add another location later:"
info "  $REPO_ROOT/wizard.sh add-location"
info ""
info "Diagnostic snapshot:"
info "  $REPO_ROOT/wizard.sh status"
