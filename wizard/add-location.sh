#!/usr/bin/env bash
# wizard/add-location.sh — capture USB fingerprint + audio for one location.
# Run while docked at the location you want to capture.

# shellcheck disable=SC1091
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/lib.sh"

bootstrap_gum

# ---------- 1: pick which location ----------
banner "Capture a dock location"

if [[ ! -f "$PROFILES_FILE" ]]; then
  fail "profiles.lua not found at $PROFILES_FILE — run 'wizard.sh install' first."
fi

# Extract existing location slugs from profiles.lua (any line like ["foo-bar"] = {)
slugs=()
while IFS= read -r _slug_line; do
  [[ -n "$_slug_line" ]] && slugs+=("$_slug_line")
done < <(grep -oE '\["[^"]+"\] = \{' "$PROFILES_FILE" | sed -E 's/^\["//; s/"\] = \{$//' | grep -v '^laptop$' || true)

choices=()
for s in "${slugs[@]}"; do
  choices+=("$(to_pretty "$s")")
done
choices+=("+ Add a brand new location")

picked=$(choose_one "Which location are you capturing?" "${choices[@]}")
[[ -n "$picked" ]] || fail "No location selected"

if [[ "$picked" == "+ Add a brand new location" ]]; then
  new_name=$(input_text "New location name (e.g., 'Coffee Shop')")
  [[ -n "$new_name" ]] || fail "Location name can't be empty"
  slug=$(to_slug "$new_name")
  pretty=$(to_pretty "$slug")
  if grep -q "WIZARD_PROFILE_${slug}_BEGIN" "$PROFILES_FILE"; then
    info "Location '$pretty' already exists. Reusing it."
  else
    # Insert a placeholder block before the final "}".
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
    success "Added placeholder block for '$pretty' to profiles.lua"
    if command -v obs-cmd >/dev/null 2>&1 && obs-cmd info >/dev/null 2>&1; then
      if ! obs-cmd scene list 2>/dev/null | grep -qF "$pretty"; then
        obs-cmd scene create "$pretty" >/dev/null 2>&1 && success "Created OBS scene '$pretty'"
      fi
    fi
  fi
else
  pretty="$picked"
  slug=$(to_slug "$pretty")
fi

# If profiles.lua is hand-written (no wizard anchors), offer to migrate.
if ! grep -q "WIZARD_PROFILE_${slug}_BEGIN" "$PROFILES_FILE"; then
  warn "profiles.lua doesn't have wizard anchor markers for '$slug'."
  warn "(It was probably hand-written before the wizard existed.)"
  if confirm "Regenerate profiles.lua in wizard format (keeps location names, resets device data)?"; then
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
    fail "Can't update profile without anchor markers."
  fi
fi

# ---------- 2: confirm docked ----------
info ""
info "Make sure you're plugged into the dock for **$pretty** right now."
info "Wait until all peripherals enumerate (give it ~5 seconds after plugging in)."
confirm "Ready?" || { info "Aborted."; exit 0; }

# ---------- 3: trigger Hammerspoon reload to refresh the snapshot ----------
step "Refreshing device snapshot"
osascript -e 'tell application "Hammerspoon" to reload' >/dev/null 2>&1 \
  || fail "Couldn't reach Hammerspoon. Is it running?"
sleep 2

[[ -f "$LOG_FILE" ]] || fail "Log file not found at $LOG_FILE — has Hammerspoon loaded the engine?"

# ---------- 4: extract the most recent snapshot ----------
last_snapshot() {
  local start
  start=$(grep -n -- '--- audio devices ---' "$LOG_FILE" | tail -1 | cut -d: -f1)
  [[ -z "$start" ]] && return 1
  tail -n "+$start" "$LOG_FILE" | sed -E 's/^.*av: //; s/^[[:space:]]+//'
}

snapshot=$(last_snapshot) || fail "Couldn't find a device snapshot in the log."

# Audio lines look like:    "Name"  in=true out=false
# USB lines look like:      vid=0x1e4e pid=0x701f  "Name"
audio_lines=$(echo "$snapshot" | awk '/in=/ && /out=/')
usb_lines=$(echo "$snapshot" | awk '/^vid=/')

[[ -n "$audio_lines" ]] || fail "No audio devices found in snapshot."
[[ -n "$usb_lines"   ]] || fail "No USB devices found in snapshot."

# ---------- 5: pick fingerprint USB devices ----------
step "Pick USB devices for the fingerprint"
info "Pick the device(s) that are uniquely-and-stably present at $pretty."
info "Usually that's the dock itself. Add a monitor or unique peripheral if you"
info "have the same dock model at multiple locations."
info ""

declare -a usb_options=()
declare -a usb_meta=()  # parallel array: "vid|pid|name"
while IFS= read -r line; do
  vid=$(echo "$line" | sed -nE 's/.*vid=(0x[0-9a-fA-F]+).*/\1/p')
  pid=$(echo "$line" | sed -nE 's/.*pid=(0x[0-9a-fA-F]+).*/\1/p')
  name=$(echo "$line" | sed -nE 's/.*"([^"]*)".*/\1/p')
  [[ -z "$vid" || -z "$pid" ]] && continue
  usb_options+=("$vid $pid  ${name:-(unnamed)}")
  usb_meta+=("$vid|$pid|${name:-Unknown}")
done <<< "$usb_lines"

picked_indexes=()
picked_lines=$(choose_multi "Use Tab/Space to pick — Enter when done" "${usb_options[@]}")
while IFS= read -r picked_line; do
  for i in "${!usb_options[@]}"; do
    if [[ "${usb_options[$i]}" == "$picked_line" ]]; then
      picked_indexes+=("$i")
      break
    fi
  done
done <<< "$picked_lines"

[[ ${#picked_indexes[@]} -ge 1 ]] || fail "Pick at least one USB device for the fingerprint."

# ---------- 6: pick audio input ----------
step "Pick the system default microphone for $pretty"
declare -a audio_in_options=()
while IFS= read -r line; do
  if echo "$line" | grep -q 'in=true'; then
    name=$(echo "$line" | sed -nE 's/^"([^"]+)".*/\1/p')
    [[ -n "$name" ]] && audio_in_options+=("$name")
  fi
done <<< "$audio_lines"
audio_in=$(choose_one "Microphone" "${audio_in_options[@]}")

# ---------- 7: pick audio output ----------
step "Pick the system default speaker for $pretty"
declare -a audio_out_options=()
while IFS= read -r line; do
  if echo "$line" | grep -q 'out=true'; then
    name=$(echo "$line" | sed -nE 's/^"([^"]+)".*/\1/p')
    [[ -n "$name" ]] && audio_out_options+=("$name")
  fi
done <<< "$audio_lines"
audio_out=$(choose_one "Speaker" "${audio_out_options[@]}")

# ---------- 8: confirm summary ----------
step "Confirm"
info "Profile:  $pretty  ($slug)"
info "Mic:      $audio_in"
info "Speaker:  $audio_out"
info "OBS:      $pretty"
info "USB fingerprint:"
for idx in "${picked_indexes[@]}"; do
  IFS='|' read -r vid pid name <<< "${usb_meta[$idx]}"
  info "  - $vid $pid  $name"
done

confirm "Save this profile?" || { info "Aborted, profiles.lua unchanged."; exit 0; }

# ---------- 9: write to profiles.lua via awk ----------
fp_block=$(mktemp)
{
  for idx in "${picked_indexes[@]}"; do
    IFS='|' read -r vid pid name <<< "${usb_meta[$idx]}"
    # Lower-case the hex, ensure 0x prefix preserved
    vid_lower=$(echo "$vid" | tr 'A-F' 'a-f')
    pid_lower=$(echo "$pid" | tr 'A-F' 'a-f')
    # Escape double quotes in the name for safety
    name_esc=$(printf '%s' "$name" | sed 's/"/\\"/g')
    echo "      { vendorID = $vid_lower, productID = $pid_lower, name = \"$name_esc\" },"
  done
} > "$fp_block"

tmpfile=$(mktemp)
awk -v slug="$slug" -v audio_in="$audio_in" -v audio_out="$audio_out" -v fp_file="$fp_block" '
  BEGIN { in_target=0; in_fp=0 }
  $0 ~ "WIZARD_PROFILE_" slug "_BEGIN" { in_target=1; print; next }
  $0 ~ "WIZARD_PROFILE_" slug "_END"   { in_target=0; print; next }
  in_target && /WIZARD_FINGERPRINT_BEGIN/ {
    print
    while ((getline line < fp_file) > 0) print line
    close(fp_file)
    in_fp=1
    next
  }
  in_target && /WIZARD_FINGERPRINT_END/ {
    in_fp=0
    print
    next
  }
  in_target && in_fp { next }
  in_target && /audioInput[[:space:]]*=/ {
    printf "    audioInput  = \"%s\",\n", audio_in
    next
  }
  in_target && /audioOutput[[:space:]]*=/ {
    printf "    audioOutput = \"%s\",\n", audio_out
    next
  }
  { print }
' "$PROFILES_FILE" > "$tmpfile"
mv "$tmpfile" "$PROFILES_FILE"
rm -f "$fp_block"

success "profiles.lua updated"

# Quick syntax check.
if command -v luac >/dev/null 2>&1; then
  if ! luac -p "$PROFILES_FILE" 2>/dev/null; then
    fail "profiles.lua has a syntax error after the edit. Restore from a backup."
  fi
fi

# ---------- 10: reload Hammerspoon ----------
step "Reloading Hammerspoon to apply"
osascript -e 'tell application "Hammerspoon" to reload' >/dev/null 2>&1 || true
sleep 2

# ---------- 11: surface result ----------
step "Result"
tail -n 25 "$LOG_FILE" | sed -E 's/^.*av: /  /' | grep -E "applying profile|set default|OBS scene|warning|not found" || \
  info "(No relevant lines found — check the full log if something looks off.)"

# ---------- 12: optional commit ----------
if [[ -d "$REPO_ROOT/.git" ]]; then
  if confirm "Commit and push this profile to the repo? (Optional — your settings work locally either way.)"; then
    if git -C "$REPO_ROOT" diff --quiet --exit-code -- profiles.lua; then
      info "No actual changes to commit (file already matched)."
    else
      git -C "$REPO_ROOT" add profiles.lua
      git -C "$REPO_ROOT" commit -m "Add/update $pretty profile via wizard"
      if git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
        git -C "$REPO_ROOT" push 2>&1 | tail -3
      fi
      success "Committed and pushed"
    fi
  fi
fi

banner "$pretty captured"
info "Dock + undock now to verify the profile fires correctly. The Console + log"
info "will show the engine resolving to '$slug' when this dock is attached."
