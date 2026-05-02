#!/usr/bin/env bash
# tests/test_update_profile.sh — exercises wizard/_update-profile.sh by
# generating a fresh profiles.lua, applying an edit, and inspecting the result.

# shellcheck disable=SC1091
source "$REPO_ROOT/wizard/lib.sh"

GEN="$REPO_ROOT/wizard/_generate-profiles.sh"
UPDATE="$REPO_ROOT/wizard/_update-profile.sh"

# Helper: write a sample fingerprint block file
write_fp() {
  local target="$1"
  cat > "$target" <<'EOF'
      { vendorID = 0x2188, productID = 0x6533, name = "CalDigit Thunderbolt 3 Audio (dock)" },
      { vendorID = 0x043e, productID = 0x9a68, name = "LG UltraFine Display Camera" },
EOF
}

setup() {
  export PROFILES_FILE="$PWD/profiles.lua"
  "$GEN" "Laptop" "Home Office" "Work Office" >/dev/null
}

test_update_replaces_audio_devices() {
  setup
  write_fp fp.txt
  "$UPDATE" "home-office" "Yeti Mic" "LG Speakers" "$PWD/fp.txt" "$PROFILES_FILE"
  awk '/WIZARD_PROFILE_home-office_BEGIN/,/WIZARD_PROFILE_home-office_END/' "$PROFILES_FILE" > block.txt
  assert_file_contains block.txt 'audioInput  = "Yeti Mic"'
  assert_file_contains block.txt 'audioOutput = "LG Speakers"'
}

test_update_inserts_fingerprint_entries() {
  setup
  write_fp fp.txt
  "$UPDATE" "home-office" "Mic" "Speaker" "$PWD/fp.txt" "$PROFILES_FILE"
  awk '/WIZARD_PROFILE_home-office_BEGIN/,/WIZARD_PROFILE_home-office_END/' "$PROFILES_FILE" > block.txt
  assert_file_contains block.txt 'vendorID = 0x2188, productID = 0x6533'
  assert_file_contains block.txt 'vendorID = 0x043e, productID = 0x9a68'
}

test_update_preserves_anchor_markers() {
  setup
  write_fp fp.txt
  "$UPDATE" "home-office" "Mic" "Speaker" "$PWD/fp.txt" "$PROFILES_FILE"
  assert_file_contains "$PROFILES_FILE" 'WIZARD_PROFILE_home-office_BEGIN'
  assert_file_contains "$PROFILES_FILE" 'WIZARD_PROFILE_home-office_END'
  assert_file_contains "$PROFILES_FILE" 'WIZARD_FINGERPRINT_BEGIN'
  assert_file_contains "$PROFILES_FILE" 'WIZARD_FINGERPRINT_END'
}

test_update_does_not_touch_other_profiles() {
  setup
  write_fp fp.txt
  # Capture the work-office block before
  awk '/WIZARD_PROFILE_work-office_BEGIN/,/WIZARD_PROFILE_work-office_END/' "$PROFILES_FILE" > work_before.txt
  "$UPDATE" "home-office" "Mic" "Speaker" "$PWD/fp.txt" "$PROFILES_FILE"
  # Capture work-office after
  awk '/WIZARD_PROFILE_work-office_BEGIN/,/WIZARD_PROFILE_work-office_END/' "$PROFILES_FILE" > work_after.txt
  if ! diff -q work_before.txt work_after.txt >/dev/null; then
    echo "work-office block unexpectedly changed:" >&2
    diff work_before.txt work_after.txt >&2
    return 1
  fi
}

test_update_yields_valid_lua() {
  setup
  write_fp fp.txt
  "$UPDATE" "home-office" "Yeti Mic" "LG Speakers" "$PWD/fp.txt" "$PROFILES_FILE"
  assert_lua_valid "$PROFILES_FILE"
}

test_update_replaces_when_run_twice() {
  setup
  # First update
  write_fp fp.txt
  "$UPDATE" "home-office" "Mic A" "Speaker A" "$PWD/fp.txt" "$PROFILES_FILE"
  # Second update with different data
  cat > fp2.txt <<'EOF'
      { vendorID = 0x1234, productID = 0x5678, name = "New Dock" },
EOF
  "$UPDATE" "home-office" "Mic B" "Speaker B" "$PWD/fp2.txt" "$PROFILES_FILE"
  awk '/WIZARD_PROFILE_home-office_BEGIN/,/WIZARD_PROFILE_home-office_END/' "$PROFILES_FILE" > block.txt
  # First update's data should be gone
  assert_file_not_contains block.txt 'CalDigit'
  assert_file_not_contains block.txt 'audioInput  = "Mic A"'
  # Second update's data should be present
  assert_file_contains block.txt 'vendorID = 0x1234'
  assert_file_contains block.txt 'audioInput  = "Mic B"'
}

test_update_missing_anchor_fails() {
  setup
  write_fp fp.txt
  assert_exit_code 65 "$UPDATE" "nonexistent-slug" "Mic" "Speaker" "$PWD/fp.txt" "$PROFILES_FILE"
}

test_update_missing_profiles_file_fails() {
  setup
  write_fp fp.txt
  assert_exit_code 66 "$UPDATE" "home-office" "Mic" "Speaker" "$PWD/fp.txt" "/nonexistent/path"
}

test_update_missing_fp_file_fails() {
  setup
  assert_exit_code 66 "$UPDATE" "home-office" "Mic" "Speaker" "/nonexistent/fp.txt" "$PROFILES_FILE"
}

test_update_audio_with_special_chars_in_name() {
  # The caller is responsible for escaping, but the helper should pass the
  # string through verbatim. Test with parens and apostrophes.
  setup
  write_fp fp.txt
  "$UPDATE" "home-office" "Bose QC35 (USB)" "MacBook Pro Speakers" "$PWD/fp.txt" "$PROFILES_FILE"
  assert_file_contains "$PROFILES_FILE" 'audioInput  = "Bose QC35 \(USB\)"'
}
