#!/usr/bin/env bash
# wizard/install.sh — full first-time install. Idempotent: rerunning skips
# already-done work and re-confirms anything that needs human input.

# shellcheck disable=SC1091,SC2088
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$LIB_DIR/lib.sh"

dryrun_banner

# ============================================================================
# Step 1/15 — Pre-flight checks
# ============================================================================
step "Step 1/15 — Pre-flight checks"
info "Verifying you're on macOS and have Homebrew + GitHub CLI installed and"
info "authenticated. These are the only prerequisites the wizard can't install"
info "for you. If any are missing, you'll get a link to install them and we'll"
info "stop here so you can fix it."
echo
require_macos
require_brew
require_gh
success "macOS ✓  Homebrew ✓  gh (authenticated) ✓"

# ============================================================================
# Step 2/15 — Install gum (the wizard's UI toolkit)
# ============================================================================
step "Step 2/15 — Install gum (nicer prompts for this wizard)"
info "gum is a small TUI toolkit that gives this wizard its colored prompts,"
info "menus, and confirmations. If you don't have it, I'll install it via"
info "Homebrew now (one-time, takes a few seconds)."
echo
bootstrap_gum

# ============================================================================
# Step 3/15 — Welcome
# ============================================================================
banner "AV Pain Reliever — guided setup"
info "Here's the plan:"
info "  • Steps 1-7 are install-and-config (mostly automated, ~2 minutes)."
info "  • Step 8 needs you to grant macOS Accessibility permission to Hammerspoon."
info "  • Step 9 asks for the names of locations you switch between."
info "  • Steps 10-13 set up OBS scenes and the virtual camera."
info "  • Step 14 walks you through Zoom + Slack settings."
info "  • Step 15 captures USB devices and audio for one of your locations,"
info "    so you finish with at least one fully working profile."
echo
info "If anything goes sideways, you can re-run this wizard — it's idempotent"
info "and skips work that's already done."
echo
if ! confirm "Ready to start?"; then
  info "No problem — re-run this wizard whenever you're ready:"
  info "  $REPO_ROOT/wizard.sh"
  exit 0
fi

# ============================================================================
# Step 4/15 — Install Hammerspoon
# ============================================================================
step "Step 4/15 — Install Hammerspoon"
info "Hammerspoon is a free macOS automation framework. It's the engine that"
info "watches USB events and switches your audio defaults. It runs as a small"
info "menu bar app."
echo
if [[ -d "/Applications/Hammerspoon.app" ]]; then
  hs_version=$(defaults read /Applications/Hammerspoon.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "?")
  success "Hammerspoon $hs_version already installed at /Applications/Hammerspoon.app"
else
  info "Installing via Homebrew (this can take 30-60 seconds)..."
  runcmd brew install --cask hammerspoon
  success "Hammerspoon installed"
fi

# ============================================================================
# Step 5/15 — Install OBS Studio (28+)
# ============================================================================
step "Step 5/15 — Install OBS Studio"
info "OBS Studio is the camera scene switcher. We need version 28 or newer"
info "because it ships with the obs-websocket server built in (which is how"
info "we'll switch scenes from Hammerspoon)."
echo
if [[ -d "/Applications/OBS.app" ]]; then
  obs_version=$(defaults read /Applications/OBS.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "0")
  obs_major=$(echo "$obs_version" | cut -d. -f1)
  if [[ "$obs_major" -ge 28 ]]; then
    success "OBS $obs_version already installed (28+, has obs-websocket built in)"
  else
    warn "OBS $obs_version is older than 28 — upgrading via Homebrew"
    runcmd brew install --cask --force obs
    success "OBS upgraded"
  fi
else
  info "Installing via Homebrew (this can take 1-2 minutes)..."
  runcmd brew install --cask obs
  success "OBS installed"
fi

# ============================================================================
# Step 6/15 — Install obs-cmd
# ============================================================================
step "Step 6/15 — Install obs-cmd"
info "obs-cmd is a small command-line tool that talks to OBS's WebSocket"
info "server. The engine uses it to switch OBS scenes when you dock at a"
info "different location. It's not in Homebrew so we download a pre-built"
info "binary directly from its GitHub releases."
echo
INSTALL_DIR=$(obs_cmd_install_dir)
OBS_CMD_PATH="$INSTALL_DIR/obs-cmd"
if [[ -x "$OBS_CMD_PATH" ]]; then
  success "obs-cmd already installed at $OBS_CMD_PATH ($($OBS_CMD_PATH --version))"
else
  ASSET=$(obs_cmd_asset)
  URL="https://github.com/grigio/obs-cmd/releases/latest/download/$ASSET"
  if [[ "$DRY_RUN" == "1" ]]; then
    would "would download $URL"
    would "would extract obs-cmd binary from the tarball"
    would "would sudo-move the binary to $OBS_CMD_PATH and chmod +x"
  else
    info "Downloading $ASSET from grigio/obs-cmd releases..."
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT
    curl -sSL -o "$TMPDIR/obs-cmd.tar.gz" "$URL"
    tar -xzf "$TMPDIR/obs-cmd.tar.gz" -C "$TMPDIR"
    info "Installing to $OBS_CMD_PATH (sudo password may be required)..."
    sudo mv "$TMPDIR/obs-cmd" "$OBS_CMD_PATH"
    sudo chmod +x "$OBS_CMD_PATH"
    trap - EXIT
    rm -rf "$TMPDIR"
    success "obs-cmd installed: $($OBS_CMD_PATH --version)"
  fi
fi

# ============================================================================
# Step 7/15 — Wire ~/.hammerspoon to this repo
# ============================================================================
step "Step 7/15 — Wire ~/.hammerspoon to this repo"
info "Hammerspoon expects its config at ~/.hammerspoon. We make that path a"
info "symlink to this repo, so when you 'git pull' updates, Hammerspoon picks"
info "them up on the next reload."
echo
if [[ -L "$HAMMERSPOON_DIR" ]]; then
  current=$(readlink "$HAMMERSPOON_DIR")
  if [[ "$current" == "$REPO_ROOT" ]]; then
    success "~/.hammerspoon already symlinked to this repo"
  else
    warn "~/.hammerspoon currently symlinks to $current (a different location)."
    info "If you replace it, the existing link will be moved to a backup, not deleted."
    if confirm "Replace it with a link to this repo?"; then
      backup="$HAMMERSPOON_DIR.backup-$(date +%Y%m%d-%H%M%S)"
      runcmd mv "$HAMMERSPOON_DIR" "$backup"
      runcmd ln -s "$REPO_ROOT" "$HAMMERSPOON_DIR"
      success "Old link backed up to $backup"
      success "~/.hammerspoon -> $REPO_ROOT"
    else
      fail "Can't proceed without ~/.hammerspoon pointing at this repo. Aborting."
    fi
  fi
elif [[ -e "$HAMMERSPOON_DIR" ]]; then
  warn "~/.hammerspoon exists as a real directory (not a symlink)."
  warn "It probably has someone else's Hammerspoon config in it."
  backup="$HAMMERSPOON_DIR.backup-$(date +%Y%m%d-%H%M%S)"
  info "If you continue, your existing config will be moved to:"
  info "  $backup"
  info "Nothing is deleted; you can restore it later by removing the new symlink"
  info "and renaming the backup back to ~/.hammerspoon."
  if confirm "Move existing ~/.hammerspoon to backup and create the symlink?"; then
    runcmd mv "$HAMMERSPOON_DIR" "$backup"
    runcmd ln -s "$REPO_ROOT" "$HAMMERSPOON_DIR"
    success "Existing config backed up to $backup"
    success "~/.hammerspoon -> $REPO_ROOT"
  else
    fail "Can't proceed without ~/.hammerspoon pointing at this repo. Aborting."
  fi
else
  runcmd ln -s "$REPO_ROOT" "$HAMMERSPOON_DIR"
  success "~/.hammerspoon -> $REPO_ROOT (created fresh)"
fi

# ============================================================================
# Step 8/15 — Launch Hammerspoon and grant Accessibility
# ============================================================================
step "Step 8/15 — Launch Hammerspoon and grant Accessibility permission"
info "Hammerspoon needs macOS Accessibility permission so it can read USB"
info "events (when you dock/undock) and change the system audio defaults."
info "macOS only grants this once; you don't have to do it again."
echo
if pgrep -x Hammerspoon >/dev/null 2>&1; then
  success "Hammerspoon is already running"
else
  info "Launching Hammerspoon..."
  runcmd open -a Hammerspoon
  [[ "$DRY_RUN" != "1" ]] && sleep 2
fi
echo
info "I'll open the System Settings → Privacy & Security → Accessibility pane"
info "for you. Find Hammerspoon in the list and toggle the switch ON."
info "(You'll be prompted for your Mac password — that's normal.)"
echo
if [[ "$DRY_RUN" == "1" ]]; then
  would 'would open System Settings → Privacy & Security → Accessibility pane'
else
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true
  sleep 1
fi
if confirm "Done — Hammerspoon is toggled ON in Accessibility?"; then
  success "Accessibility permission granted"
else
  warn "You skipped the Accessibility step. The engine will partially work but"
  warn "won't be able to switch system audio defaults until you grant it. Open"
  warn "System Settings → Privacy & Security → Accessibility and toggle Hammerspoon on."
fi

# ============================================================================
# Step 9/15 — Name your locations
# ============================================================================
step "Step 9/15 — Name your locations"
info "What physical setups do you switch between? Common examples:"
info "  • Home Office       (your dock at home)"
info "  • Work Office       (your dock at the office)"
info "  • Conference Room   (a meeting room with its own dock or peripherals)"
info "  • Coffee Shop       (just laptop + earbuds)"
info "  • Client Site       (anywhere with a different mic/speaker setup)"
echo
info "Don't worry about getting it perfect — you can add more locations later"
info "with: ~/av-pain-reliever/wizard.sh add-location"
echo
info "Type one location name per line. Press Ctrl+D (or leave a blank line"
info "and Enter) when you're done."
echo
raw_locations=$(input_lines "Locations (one per line)")
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
  echo
  info "Adding 'Laptop' to your list — that's the fallback profile for when"
  info "nothing's plugged in (just your MacBook on its own)."
  locations=("Laptop" "${locations[@]}")
fi

if [[ ${#locations[@]} -lt 2 ]]; then
  fail "Need at least one docked location in addition to Laptop. Re-run the wizard."
fi

echo
info "Your locations:"
for l in "${locations[@]}"; do
  info "  • $l"
done

# ============================================================================
# Step 10/15 — Generate profiles.lua
# ============================================================================
step "Step 10/15 — Generate profiles.lua (the engine's config file)"
info "profiles.lua is the file the engine reads to know which audio devices and"
info "OBS scene to switch to at each location. I'll generate one with a block"
info "for each location you named — empty placeholders for now, filled in"
info "later by the add-location step."
echo
if grep -q '^-- WIZARD_PROFILE_' "$PROFILES_FILE" 2>/dev/null; then
  warn "profiles.lua already exists in wizard format. Overwriting will reset all"
  warn "captured device data — you'll need to re-run add-location at each spot."
  if ! confirm "Overwrite anyway?"; then
    info "Keeping existing profiles.lua. Skipping generation."
  else
    runstep "would generate profiles.lua with ${#locations[@]} location(s): ${locations[*]}" \
      "$LIB_DIR/_generate-profiles.sh" "${locations[@]}"
    success "profiles.lua regenerated with ${#locations[@]} location(s)"
  fi
else
  if [[ -f "$PROFILES_FILE" ]]; then
    backup="$PROFILES_FILE.backup-$(date +%Y%m%d-%H%M%S)"
    runcmd cp "$PROFILES_FILE" "$backup"
    info "Backed up existing profiles.lua to $backup"
  fi
  runstep "would generate profiles.lua with ${#locations[@]} location(s): ${locations[*]}" \
    "$LIB_DIR/_generate-profiles.sh" "${locations[@]}"
  success "profiles.lua written with ${#locations[@]} location(s)"
fi
echo
info "Asking Hammerspoon to reload its config so the new profiles are live..."
if [[ "$DRY_RUN" == "1" ]]; then
  would "would reload Hammerspoon (osascript reload)"
else
  hammerspoon_reload_with_fallback
fi

# ============================================================================
# Step 11/15 — Enable OBS WebSocket server
# ============================================================================
step "Step 11/15 — Enable OBS WebSocket server"
info "OBS Studio has a built-in WebSocket server (since v28) that lets external"
info "tools control it. We need to turn it on so obs-cmd can switch scenes."
echo
if ! pgrep -x OBS >/dev/null 2>&1; then
  info "Launching OBS (give it a few seconds to start)..."
  runcmd open -a OBS
  [[ "$DRY_RUN" != "1" ]] && sleep 4
fi
if obs-cmd info >/dev/null 2>&1; then
  success "OBS WebSocket already enabled and reachable on localhost:4455"
elif [[ "$DRY_RUN" == "1" ]]; then
  would "would prompt you to enable OBS WebSocket server in Tools → WebSocket Server Settings"
  would "would verify connection with: obs-cmd info"
else
  echo
  info "Click into the OBS window. Then in the OBS menu bar at the top:"
  info "  1. Click 'Tools' → 'WebSocket Server Settings'"
  info "  2. ✓ Check 'Enable WebSocket server'"
  info "  3. ✗ UNCHECK 'Enable Authentication' (only listens on localhost,"
  info "       so a local-only password adds friction without real benefit)"
  info "  4. Leave the Server Port at the default (4455)"
  info "  5. Click 'Apply' or 'OK'"
  echo
  while true; do
    confirm "Done with the OBS WebSocket settings?" || true
    if obs-cmd info >/dev/null 2>&1; then
      success "OBS WebSocket reachable on localhost:4455"
      break
    fi
    warn "Still can't reach the OBS WebSocket. Is OBS open? Did you check"
    warn "'Enable WebSocket server'? Did you click Apply?"
    if ! confirm "Try again?"; then
      warn "Skipping OBS scene setup. You can re-run this wizard later to retry."
      SKIP_OBS=1
      break
    fi
  done
fi

# ============================================================================
# Step 12/15 — Create OBS scenes
# ============================================================================
step "Step 12/15 — Create one OBS scene per location"
info "Each location in profiles.lua maps to an OBS scene by name. I'll create"
info "an empty scene for each one now. You'll add the actual camera source"
info "to each scene in the next step (we can't do that automatically — OBS's"
info "API doesn't let us enumerate your physical cameras)."
echo
if [[ "${SKIP_OBS:-0}" == "1" ]]; then
  warn "Skipping (OBS WebSocket not reachable)."
elif [[ "$DRY_RUN" == "1" ]]; then
  for loc in "${locations[@]}"; do
    pretty=$(to_pretty "$(to_slug "$loc")")
    would "would create OBS scene '$pretty' (skipped if it already exists)"
  done
else
  existing_scenes=$(obs-cmd scene list 2>/dev/null || echo "")
  for loc in "${locations[@]}"; do
    pretty=$(to_pretty "$(to_slug "$loc")")
    if echo "$existing_scenes" | grep -qF "$pretty"; then
      success "Scene '$pretty' already exists — left as-is"
    else
      if obs-cmd scene create "$pretty" >/dev/null 2>&1; then
        success "Created scene: $pretty"
      else
        warn "Couldn't create scene '$pretty'. Add it manually in OBS later."
      fi
    fi
  done
fi

# ============================================================================
# Step 13/15 — Start OBS Virtual Camera + add sources
# ============================================================================
step "Step 13/15 — Start OBS Virtual Camera and add camera sources"
if [[ "${SKIP_OBS:-0}" == "1" ]]; then
  warn "Skipping (OBS WebSocket not reachable)."
else
  info "Starting the OBS Virtual Camera output. This is what Zoom and Slack"
  info "will see as your camera. It persists across OBS launches; you only"
  info "need to do this once."
  echo
  runcmd obs-cmd virtual-camera start
  success "Virtual camera started"
  echo
  info "Now add a camera source to each scene (one-time, ~30 seconds per scene):"
  info "  1. In OBS, click on a scene name in the 'Scenes' panel (lower-left)."
  info "  2. In the 'Sources' panel (next to it), click '+'."
  info "  3. Pick 'Video Capture Device'."
  info "  4. Name it (any name) and click OK."
  info "  5. Pick the camera you use at that location from the 'Device' dropdown."
  info "  6. Repeat for each scene."
  echo
  info "Tip: at locations you don't physically reach today, you can add the"
  info "camera source later. The scene just needs to exist now so the engine"
  info "doesn't error when it tries to switch."
  echo
  confirm "Done with at least one scene? (You can finish the others later)" || true
fi

# ============================================================================
# Step 14/15 — Configure Zoom and Slack
# ============================================================================
step "Step 14/15 — Configure Zoom and Slack to follow the system + OBS"
info "The whole point of this setup: Zoom and Slack inherit from system audio"
info "(which the engine switches per location) and use the OBS Virtual Camera"
info "(which OBS switches per location). So you set them to 'Same as System'"
info "and 'OBS Virtual Camera' once, and never touch them again."
echo
configure_app() {
  local app="$1" path="$2"
  if [[ ! -d "$path" ]]; then
    info "$app isn't installed on this Mac — skipping"
    return
  fi
  info "Opening $app for you to configure..."
  runcmd open -a "$app"
  echo
  info "In $app's settings:"
  info "  • Microphone → Same as System"
  info "  • Speaker → Same as System"
  info "  • Camera → OBS Virtual Camera"
  echo
  info "(The exact wording varies. Anything like 'System Default' or 'Default'"
  info "for audio works. For camera, look for 'OBS Virtual Camera' in the list.)"
  echo
  confirm "Done with $app's settings?" || true
}
configure_app "zoom.us" "/Applications/zoom.us.app"
configure_app "Slack"   "/Applications/Slack.app"

# ============================================================================
# Step 15/15 — Capture your first dock location
# ============================================================================
step "Step 15/15 — Capture your first dock location"
info "Last step. We'll capture USB devices and audio for one of your docked"
info "locations so you finish with at least one fully working profile."
echo
info "For this to work, you need to be physically AT one of your docked"
info "locations RIGHT NOW with everything plugged in (dock, monitor, mic,"
info "speakers, anything else that's part of that setup)."
echo
if confirm "Are you docked at a location and ready to capture it now?"; then
  if [[ "$DRY_RUN" == "1" ]]; then
    would "would launch the add-location subcommand to capture this dock setup"
    info "(In a real run, this is where you'd pick USB devices, microphone,"
    info " and speaker for your current location.)"
  else
    "$LIB_DIR/add-location.sh"
  fi
else
  info "No problem. Whenever you're ready, run:"
  info "  $REPO_ROOT/wizard.sh add-location"
fi

banner "Setup complete"
info "What you've got now:"
info "  • Hammerspoon engine running, watching USB events"
info "  • OBS Studio with one scene per location, virtual camera live"
info "  • Zoom and Slack pointing at 'Same as System' + OBS Virtual Camera"
info "  • profiles.lua wired up for your locations"
echo
info "Useful commands:"
info "  ~/av-pain-reliever/wizard.sh add-location   # capture another location"
info "  ~/av-pain-reliever/wizard.sh status         # diagnostic snapshot"
info "  ~/av-pain-reliever/wizard.sh help           # all options"
echo
info "If something stops working, check the live log:"
info "  tail -f ~/.hammerspoon/logs/av-pain-reliever.log"
