#!/usr/bin/env bash
# tests/test_generate_profiles.sh — exercises wizard/_generate-profiles.sh
# with controlled inputs and verifies the generated Lua.

# shellcheck disable=SC1091
source "$REPO_ROOT/wizard/lib.sh"

GEN="$REPO_ROOT/wizard/_generate-profiles.sh"

# Each test runs in its own tempdir (provided by the framework).
# The generator writes to $PROFILES_FILE which is REPO_ROOT/profiles.lua, so
# we override PROFILES_FILE to point at the tempdir for isolation.

setup() {
  export PROFILES_FILE="$PWD/profiles.lua"
}

test_generate_with_one_docked_location() {
  setup
  "$GEN" "Laptop" "Home Office"
  assert_file_contains "$PROFILES_FILE" '^return \{$'
  assert_file_contains "$PROFILES_FILE" '^\}$'
  assert_file_contains "$PROFILES_FILE" 'WIZARD_PROFILE_laptop_BEGIN'
  assert_file_contains "$PROFILES_FILE" 'WIZARD_PROFILE_laptop_END'
  assert_file_contains "$PROFILES_FILE" 'WIZARD_PROFILE_home-office_BEGIN'
  assert_file_contains "$PROFILES_FILE" 'WIZARD_PROFILE_home-office_END'
  assert_file_contains "$PROFILES_FILE" '\["laptop"\]'
  assert_file_contains "$PROFILES_FILE" '\["home-office"\]'
  assert_file_contains "$PROFILES_FILE" 'obsScene    = "Home Office"'
}

test_generate_lua_is_valid() {
  setup
  "$GEN" "Laptop" "Home Office" "Work Office" "Conference Room"
  assert_lua_valid "$PROFILES_FILE"
}

test_generate_laptop_has_real_audio_devices_not_placeholders() {
  setup
  "$GEN" "Laptop"
  assert_file_contains "$PROFILES_FILE" 'audioInput  = "MacBook Pro Microphone"'
  assert_file_contains "$PROFILES_FILE" 'audioOutput = "MacBook Pro Speakers"'
}

test_generate_docked_location_has_placeholders() {
  setup
  "$GEN" "Laptop" "Home Office"
  # The Home Office block should have FILL ME IN audio.
  awk '/WIZARD_PROFILE_home-office_BEGIN/,/WIZARD_PROFILE_home-office_END/' "$PROFILES_FILE" > home_block.txt
  assert_file_contains home_block.txt 'audioInput  = "FILL ME IN"'
  assert_file_contains home_block.txt 'audioOutput = "FILL ME IN"'
}

test_generate_each_block_has_fingerprint_anchors() {
  setup
  "$GEN" "Laptop" "Work Office"
  # Both blocks must have BEGIN/END fingerprint anchors.
  local count_begin count_end
  count_begin=$(grep -c 'WIZARD_FINGERPRINT_BEGIN' "$PROFILES_FILE")
  count_end=$(grep -c 'WIZARD_FINGERPRINT_END' "$PROFILES_FILE")
  assert_eq "2" "$count_begin"
  assert_eq "2" "$count_end"
}

test_generate_no_args_fails() {
  setup
  assert_exit_code 64 "$GEN"
}

test_generate_pretty_obsscene_matches_input() {
  setup
  "$GEN" "Laptop" "My Coffee Shop"
  assert_file_contains "$PROFILES_FILE" 'obsScene    = "My Coffee Shop"'
  assert_file_contains "$PROFILES_FILE" '\["my-coffee-shop"\]'
}

test_generate_overwrites_existing_file() {
  setup
  echo "PRIOR JUNK" > "$PROFILES_FILE"
  "$GEN" "Laptop"
  if grep -q 'PRIOR JUNK' "$PROFILES_FILE"; then
    echo "expected the prior content to be replaced" >&2
    return 1
  fi
}
