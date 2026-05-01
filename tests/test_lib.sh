#!/usr/bin/env bash
# tests/test_lib.sh — pure-function tests for wizard/lib.sh helpers.

# shellcheck disable=SC1091
source "$REPO_ROOT/wizard/lib.sh"

test_to_slug_simple() {
  assert_eq "home-office" "$(to_slug 'Home Office')"
}

test_to_slug_lowercase_input() {
  assert_eq "home" "$(to_slug 'home')"
}

test_to_slug_punctuation() {
  assert_eq "work-office-3" "$(to_slug 'Work Office #3')"
}

test_to_slug_trims_whitespace() {
  assert_eq "spaces" "$(to_slug '   spaces   ')"
}

test_to_slug_collapses_multiple_separators() {
  assert_eq "a-b" "$(to_slug 'a   ---   b')"
}

test_to_slug_empty_input() {
  assert_eq "" "$(to_slug '')"
}

test_to_pretty_simple() {
  assert_eq "Home Office" "$(to_pretty 'home-office')"
}

test_to_pretty_single_word() {
  assert_eq "Laptop" "$(to_pretty 'laptop')"
}

test_to_pretty_multi_hyphen() {
  assert_eq "Conference Room A" "$(to_pretty 'conference-room-a')"
}

test_to_pretty_already_capitalized_passes_through() {
  # to_pretty lowercases everything then re-titles, so it normalizes weird
  # capitalization too.
  assert_eq "Home Office" "$(to_pretty 'HOME-OFFICE')"
}

test_slug_pretty_round_trip() {
  local original="Home Office"
  local round_trip
  round_trip=$(to_pretty "$(to_slug "$original")")
  assert_eq "$original" "$round_trip"
}

test_obs_cmd_install_dir_apple_silicon() {
  # On the test host, /opt/homebrew/bin should exist (we're on Apple Silicon).
  if [[ -d /opt/homebrew/bin ]]; then
    assert_eq "/opt/homebrew/bin" "$(obs_cmd_install_dir)"
  else
    assert_eq "/usr/local/bin" "$(obs_cmd_install_dir)"
  fi
}

test_obs_cmd_asset_returns_known_filename() {
  local asset
  asset=$(obs_cmd_asset)
  case "$asset" in
    obs-cmd-arm64-macos.tar.gz|obs-cmd-x64-macos.tar.gz) return 0 ;;
    *) printf 'unexpected asset: %s\n' "$asset" >&2; return 1 ;;
  esac
}
