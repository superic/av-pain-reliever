#!/usr/bin/env bash
# tests/test_wizard.sh — high-level dispatch and surface tests for wizard.sh.
# We can't fully exercise the install flow here (it would actually install
# Hammerspoon, OBS, etc.) so we verify routing and read-only paths.

# shellcheck disable=SC1091
source "$REPO_ROOT/wizard/lib.sh"

WIZARD="$REPO_ROOT/wizard.sh"

test_wizard_help_prints_usage() {
  local out
  out=$("$WIZARD" help 2>&1)
  assert_contains "$out" "Usage:"
  assert_contains "$out" "install"
  assert_contains "$out" "add-location"
  assert_contains "$out" "status"
}

test_wizard_dash_h_prints_usage() {
  local out
  out=$("$WIZARD" -h 2>&1)
  assert_contains "$out" "Usage:"
}

test_wizard_unknown_command_fails() {
  assert_exit_code 1 "$WIZARD" some-bogus-subcommand
}

test_wizard_unknown_command_prints_helpful_message() {
  local out
  out=$("$WIZARD" some-bogus-subcommand 2>&1) || true
  assert_contains "$out" "Unknown command"
}

test_wizard_status_runs_without_errors() {
  # status is read-only, safe to invoke. Will report current system state.
  local out
  out=$("$WIZARD" status 2>&1)
  assert_contains "$out" "av-pain-reliever status"
  assert_contains "$out" "Prerequisites"
  assert_contains "$out" "Hammerspoon"
  assert_contains "$out" "OBS Studio"
}

test_wizard_all_subscripts_are_executable() {
  for f in "$REPO_ROOT/wizard.sh" "$REPO_ROOT/wizard/"*.sh; do
    if [[ ! -x "$f" ]]; then
      echo "$f is not executable" >&2
      return 1
    fi
  done
}

test_wizard_subscripts_pass_shellcheck() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck not installed, skipping" >&2
    return 0
  fi
  for f in "$REPO_ROOT/wizard.sh" "$REPO_ROOT/wizard/"*.sh; do
    if ! shellcheck "$f" >/dev/null 2>&1; then
      echo "shellcheck failures in $f" >&2
      shellcheck "$f" >&2
      return 1
    fi
  done
}

test_wizard_subscripts_parse_under_bash_3_2_compat() {
  # Use /bin/bash explicitly — that's macOS's system bash 3.2.
  for f in "$REPO_ROOT/wizard.sh" "$REPO_ROOT/wizard/"*.sh; do
    if ! /bin/bash -n "$f" 2>/tmp/parse_err; then
      echo "$f failed bash 3.2 parse:" >&2
      cat /tmp/parse_err >&2
      return 1
    fi
  done
}

test_wizard_no_bash_4_only_features() {
  # Greppable list of features that don't work in 3.2.
  local found=0
  if grep -nE '\bmapfile\b' "$REPO_ROOT/wizard.sh" "$REPO_ROOT/wizard/"*.sh 2>/dev/null; then
    echo "mapfile is bash 4+; use a portable read loop" >&2
    found=1
  fi
  if grep -nE 'declare -[Ag]' "$REPO_ROOT/wizard.sh" "$REPO_ROOT/wizard/"*.sh 2>/dev/null; then
    echo "declare -A (associative) and -g are bash 4+" >&2
    found=1
  fi
  if grep -nE '\$\{[A-Za-z_][A-Za-z_0-9]*[\^,]{1,2}[A-Za-z_]*\}' "$REPO_ROOT/wizard.sh" "$REPO_ROOT/wizard/"*.sh 2>/dev/null; then
    echo "\${var^^} / \${var,,} case modification is bash 4+" >&2
    found=1
  fi
  return "$found"
}
