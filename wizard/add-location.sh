#!/usr/bin/env bash
# wizard/add-location.sh — capture USB fingerprint + audio for one location.
# Run while docked at the location you want to capture.

# shellcheck disable=SC1091
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$LIB_DIR/lib.sh"

bootstrap_gum

# ============================================================================
# Step 1 — Pick which location to capture
# ============================================================================
banner "Capture a dock location"
info "This subcommand captures the USB devices and audio devices visible at"
info "your current physical location, and writes them to profiles.lua so the"
info "engine knows what to switch to when you dock here."
echo
info "Best run while you're physically AT the location with everything plugged"
info "in (dock, monitor, mic, headphones, anything else)."
echo

[[ -f "$PROFILES_FILE" ]] || fail "profiles.lua not found at $PROFILES_FILE — run 'wizard.sh install' first."

# Existing location slugs (excluding "laptop" since it has no fingerprint).
slugs=()
while IFS= read -r _slug_line; do
  [[ -n "$_slug_line" ]] && slugs+=("$_slug_line")
done < <(grep -oE '\["[^"]+"\] = \{' "$PROFILES_FILE" | sed -E 's/^\["//; s/"\] = \{$//' | grep -v '^laptop$' || true)

choices=()
for s in "${slugs[@]}"; do
  choices+=("$(to_pretty "$s")")
done
choices+=("+ Add a brand new location")

step "Step 1 — Which location are you at right now?"
info "Pick from your existing locations, or add a new one if this is somewhere"
info "you didn't list during initial install."
echo
picked=$(choose_one "Choose:" "${choices[@]}")
[[ -n "$picked" ]] || fail "No location selected"

if [[ "$picked" == "+ Add a brand new location" ]]; then
  echo
  info "What should we call this location? (e.g., 'Coffee Shop', 'Client Site')"
  new_name=$(input_text "Location name")
  [[ -n "$new_name" ]] || fail "Location name can't be empty"
  slug=$(to_slug "$new_name")
  pretty=$(to_pretty "$slug")
  if grep -q "WIZARD_PROFILE_${slug}_BEGIN" "$PROFILES_FILE"; then
    info "Location '$pretty' already exists in profiles.lua. Reusing it."
  else
    tmpfile=$(mktemp)
    awk -v slug="$slug" -v pretty="$pretty" '
      /^}$/ && !inserted {
        printf "\n  -- WIZARD_PROFILE_%s_BEGIN\n", slug
        printf "  [\"%s\"] = {\n", slug
        printf "    fingerprint = {\n"
        printf "      -- WIZARD_FINGERPRINT_BEGIN\n"
        printf "      -- WIZARD_FINGERPRINT_END\n"
        printf "    },\n"
        printf "    audioInput  = \"FILL ME IN\",\n"
        printf "    audioOutput = \"FILL ME IN\",\n"
        printf "    obsScene    = \"%s\",\n", pretty
        printf "  },\n"
        printf "  -- WIZARD_PROFILE_%s_END\n", slug
        inserted=1
      }
      { print }
    ' "$PROFILES_FILE" > "$tmpfile"
    mv "$tmpfile" "$PROFILES_FILE"
    success "Added '$pretty' to profiles.lua"
    if command -v obs-cmd >/dev/null 2>&1 && obs-cmd info >/dev/null 2>&1; then
      if ! obs-cmd scene list 2>/dev/null | grep -qF "$pretty"; then
        if obs-cmd scene create "$pretty" >/dev/null 2>&1; then
          success "Created matching OBS scene '$pretty'"
        fi
      fi
    fi
  fi
else
  pretty="$picked"
  slug=$(to_slug "$pretty")
fi

# Migrate hand-written profiles.lua if no anchor markers present.
if ! grep -q "WIZARD_PROFILE_${slug}_BEGIN" "$PROFILES_FILE"; then
  echo
  warn "profiles.lua doesn't have wizard anchor markers for '$slug'."
  warn "(It was probably hand-written before the wizard existed, or someone"
  warn "removed the comment markers manually.)"
  info "I can regenerate the file in wizard format. Your location names will"
  info "be preserved, but device data (fingerprints, audio names) will be"
  info "reset to placeholders. You'll re-capture them via the rest of this"
  info "wizard. The current file will be backed up first."
  if confirm "Migrate now?"; then
    all_pretty=()
    while IFS= read -r _s; do
      [[ -n "$_s" ]] && all_pretty+=("$(to_pretty "$_s")")
    done < <(grep -oE '\["[^"]+"\] = \{' "$PROFILES_FILE" | sed -E 's/^\["//; s/"\] = \{$//')
    backup="$PROFILES_FILE.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$PROFILES_FILE" "$backup"
    info "Backed up to $backup"
    "$LIB_DIR/_generate-profiles.sh" "${all_pretty[@]}"
    success "profiles.lua migrated to wizard format"
  else
    fail "Can't update profile without anchor markers. Aborting."
  fi
fi

# ============================================================================
# Step 2 — Confirm physical state
# ============================================================================
echo
step "Step 2 — Confirm everything's plugged in for $pretty"
info "Make sure right now you have:"
info "  • The dock (or laptop port) connected"
info "  • Your monitor(s) plugged in if any"
info "  • Your microphone plugged in if any (USB mic, headset, etc.)"
info "  • Your speakers / headphones connected"
info "  • Anything else that's part of this location's setup"
echo
info "Wait ~5 seconds after plugging in the last thing — USB devices take a"
info "moment to show up."
echo
confirm "Ready to capture?" || { info "Aborted."; exit 0; }

# ============================================================================
# Step 3 — Refresh device snapshot
# ============================================================================
step "Step 3 — Reload Hammerspoon to capture a fresh device snapshot"
info "I'm asking the engine to enumerate all currently-attached USB devices"
info "and audio devices, and write the list to its log file. We'll read the"
info "list from there in the next step."
echo
hammerspoon_reload_with_fallback
sleep 2

# ============================================================================
# Step 4 — Parse the snapshot
# ============================================================================
snapshot=$("$LIB_DIR/_parse-snapshot.sh" "$LOG_FILE") \
  || fail "Couldn't read a device snapshot from $LOG_FILE. Is Hammerspoon running?"

audio_block=$(echo "$snapshot" | awk '/^AUDIO$/{f=1; next} /^USB$/{f=0} f')
usb_block=$(echo "$snapshot" | awk '/^USB$/{f=1; next} f')

[[ -n "$audio_block" ]] || fail "No audio devices found in snapshot."
[[ -n "$usb_block"   ]] || fail "No USB devices found in snapshot."

# ============================================================================
# Step 5 — Pick fingerprint USB devices
# ============================================================================
step "Step 5 — Pick the USB devices that identify this location"
info "The 'fingerprint' is one or more USB devices that are uniquely-and-stably"
info "present here. When the engine sees all of them attached, it knows you're"
info "at this location."
echo
info "Best picks:"
info "  • The dock itself (CalDigit / OWC / Anker / etc.) — almost always the"
info "    right choice; the dock is the thing that triggers the dock cycle."
info "  • A monitor or display USB hub if you have multiple identical docks."
info "  • A peripheral that ONLY lives at this location (e.g., a Stream Deck"
info "    that never travels)."
echo
info "Avoid picking peripherals that move with you (like a USB mic that goes"
info "in your bag) — if you forget it one day, the profile won't match."
echo
info "Tip: pick at least one device. More = more specific (will out-vote a"
info "less-specific profile if both could match)."
echo

usb_options=()
usb_meta=()  # parallel: "vid|pid|name"
while IFS=$'\t' read -r vid pid name; do
  [[ -z "$vid" || -z "$pid" ]] && continue
  usb_options+=("0x$vid 0x$pid  $name")
  usb_meta+=("$vid|$pid|$name")
done <<< "$usb_block"

picked_indexes=()
picked_lines=$(choose_multi "Tab/Space to pick, Enter when done" "${usb_options[@]}")
while IFS= read -r picked_line; do
  for i in "${!usb_options[@]}"; do
    if [[ "${usb_options[$i]}" == "$picked_line" ]]; then
      picked_indexes+=("$i")
      break
    fi
  done
done <<< "$picked_lines"

[[ ${#picked_indexes[@]} -ge 1 ]] || fail "Pick at least one USB device for the fingerprint."

# ============================================================================
# Step 6 — Pick microphone
# ============================================================================
echo
step "Step 6 — Pick the system default microphone for $pretty"
info "Whatever you pick here is what System Settings → Sound → Input gets set"
info "to when you dock here. Zoom and Slack inherit from this when their mic"
info "setting is 'Same as System'."
echo
audio_in_options=()
while IFS=$'\t' read -r name in_flag _out_flag; do
  [[ "$in_flag" == "in" && -n "$name" ]] && audio_in_options+=("$name")
done <<< "$audio_block"
[[ ${#audio_in_options[@]} -ge 1 ]] || fail "No input devices in snapshot."
audio_in=$(choose_one "Microphone" "${audio_in_options[@]}")

# ============================================================================
# Step 7 — Pick speaker
# ============================================================================
echo
step "Step 7 — Pick the system default speaker for $pretty"
info "Whatever you pick here is what System Settings → Sound → Output gets set"
info "to when you dock here. Same as above — Zoom/Slack inherit it."
echo
audio_out_options=()
while IFS=$'\t' read -r name _in_flag out_flag; do
  [[ "$out_flag" == "out" && -n "$name" ]] && audio_out_options+=("$name")
done <<< "$audio_block"
[[ ${#audio_out_options[@]} -ge 1 ]] || fail "No output devices in snapshot."
audio_out=$(choose_one "Speaker" "${audio_out_options[@]}")

# ============================================================================
# Step 8 — Confirm summary
# ============================================================================
echo
step "Step 8 — Review and save"
info "Here's what I'll write to profiles.lua for this location:"
echo
info "  Location:       $pretty  (slug: $slug)"
info "  Microphone:     $audio_in"
info "  Speaker:        $audio_out"
info "  OBS scene:      $pretty"
info "  USB fingerprint:"
for idx in "${picked_indexes[@]}"; do
  IFS='|' read -r vid pid name <<< "${usb_meta[$idx]}"
  info "    - vid=0x$vid pid=0x$pid  $name"
done
echo

confirm "Save this profile to profiles.lua?" || { info "Aborted, profiles.lua unchanged."; exit 0; }

# ============================================================================
# Step 9 — Write to profiles.lua
# ============================================================================
fp_block=$(mktemp)
trap 'rm -f "$fp_block"' EXIT
{
  for idx in "${picked_indexes[@]}"; do
    IFS='|' read -r vid pid name <<< "${usb_meta[$idx]}"
    vid_lower=$(echo "$vid" | tr 'A-F' 'a-f')
    pid_lower=$(echo "$pid" | tr 'A-F' 'a-f')
    name_esc=$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '      { vendorID = 0x%s, productID = 0x%s, name = "%s" },\n' "$vid_lower" "$pid_lower" "$name_esc"
  done
} > "$fp_block"

"$LIB_DIR/_update-profile.sh" "$slug" "$audio_in" "$audio_out" "$fp_block" "$PROFILES_FILE"
rm -f "$fp_block"
trap - EXIT

success "profiles.lua updated"

# Quick syntax check.
if command -v luac >/dev/null 2>&1; then
  if ! luac -p "$PROFILES_FILE" 2>/dev/null; then
    fail "profiles.lua has a syntax error after the edit. Restore from backup."
  fi
  success "profiles.lua syntax verified"
fi

# ============================================================================
# Step 10 — Apply (reload Hammerspoon)
# ============================================================================
echo
step "Step 10 — Apply the new profile"
info "Reloading Hammerspoon so the engine picks up the new profile and"
info "re-evaluates which one matches your current state."
echo
hammerspoon_reload_with_fallback
sleep 2

# ============================================================================
# Step 11 — Show what happened
# ============================================================================
echo
step "Step 11 — Result"
info "Here are the engine's most recent log lines (the ones relevant to"
info "the profile switch):"
echo
result_lines=$(tail -n 25 "$LOG_FILE" \
  | sed -E 's/^[0-9]{4}-[0-9-]+ [0-9:]+ (INFO|WARN)[[:space:]]+/  /' \
  | grep -E "applying profile|set default|OBS scene|warning|not found|evaluation" \
  || true)

if [[ -n "$result_lines" ]]; then
  printf '%s\n' "$result_lines"
else
  warn "No profile-application log lines found. Check the full log:"
  warn "  tail -f ~/.hammerspoon/logs/av-pain-reliever.log"
fi

# ============================================================================
# Step 12 — Optional commit
# ============================================================================
if [[ -d "$REPO_ROOT/.git" ]]; then
  echo
  step "Step 12 — Commit your change to the repo (optional)"
  info "Your settings live in profiles.lua. They work locally either way, but"
  info "committing them means you can roll back if you mess something up later,"
  info "and you can sync them to a different Mac."
  echo
  if confirm "Commit and push profiles.lua now?"; then
    if git -C "$REPO_ROOT" diff --quiet --exit-code -- profiles.lua; then
      info "No actual changes to commit (file already matched git's copy)."
    else
      git -C "$REPO_ROOT" add profiles.lua
      git -C "$REPO_ROOT" commit -m "Add/update $pretty profile via wizard"
      if git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
        if git -C "$REPO_ROOT" push 2>&1 | tail -3; then
          success "Committed and pushed"
        else
          warn "Commit succeeded but push failed (check your network/auth)."
        fi
      else
        success "Committed (no remote configured, skipping push)"
      fi
    fi
  fi
fi

banner "$pretty captured"
info "Verify it's working:"
info "  1. Unplug from the dock — engine should switch to 'laptop' within ~1.5s"
info "     (you'll see a notification)."
info "  2. Plug back in — engine should switch back to '$pretty'."
echo
info "If it's not behaving how you expect, check the live log:"
info "  tail -f ~/.hammerspoon/logs/av-pain-reliever.log"
info ""
info "Or run a quick diagnostic:"
info "  $REPO_ROOT/wizard.sh status"
