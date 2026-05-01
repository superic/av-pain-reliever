#!/usr/bin/env bash
# tests/test_tui.sh — verify the TUI helpers don't crash and handle no-color
# / no-TTY environments correctly.

# Subshell-scoped env modifications (SC2030/SC2031) are intentional: each test
# isolates its NO_COLOR override so it doesn't bleed into other tests.
# shellcheck disable=SC1091,SC2034,SC2030,SC2031
source "$REPO_ROOT/wizard/lib.sh"

test_logo_runs_without_error() {
  local out
  out=$(logo 2>&1)
  assert_contains "$out" "AV Pain Reliever"
}

test_logo_renders_in_no_color_mode() {
  local out
  out=$(
    export NO_COLOR=1
    unset USE_COLOR
    # shellcheck disable=SC1091
    source "$REPO_ROOT/wizard/lib.sh"
    logo
  )
  assert_contains "$out" "AV Pain Reliever"
  # In no-color mode, no ANSI escapes should leak through.
  if [[ "$out" == *$'\033'* ]]; then
    echo "ANSI escape codes leaked in NO_COLOR mode" >&2
    return 1
  fi
}

test_wizard_step_includes_counter_and_title() {
  local out
  out=$(wizard_step 4 15 "Install Hammerspoon" 2>&1)
  assert_contains "$out" "STEP"
  assert_contains "$out" "4/15"
  assert_contains "$out" "Install Hammerspoon"
}

# UTF-8-safe character counter. macOS tr is byte-oriented, so tr -cd on a
# multi-byte rune over-counts (it matches any byte from the rune). grep -o
# matches whole characters when the locale supports it.
count_char() {
  local needle="$1" haystack="$2"
  printf '%s' "$haystack" | grep -o "$needle" | wc -l | tr -d ' '
}

test_wizard_step_progress_bar_proportional() {
  # Step 5 of 10 with bar_width 20 = 10 filled, 10 empty.
  local out
  out=$(wizard_step 5 10 "halfway" 2>&1)
  assert_eq "10" "$(count_char '▰' "$out")"
  assert_eq "10" "$(count_char '▱' "$out")"
}

test_wizard_step_full_progress_at_total() {
  local out
  out=$(wizard_step 15 15 "done" 2>&1)
  assert_eq "20" "$(count_char '▰' "$out")"
  assert_eq "0" "$(count_char '▱' "$out")"
}

test_spin_runs_underlying_command() {
  local out
  out=$(spin "doing a thing" echo hello 2>&1)
  assert_contains "$out" "hello"
}

test_spin_propagates_failure() {
  # If the underlying command fails, spin should fail too.
  assert_exit_code 1 spin "this should fail" false
}

test_hr_prints_a_rule() {
  local out
  out=$(hr 2>&1)
  assert_contains "$out" "─"
}

test_banner_renders_text() {
  local out
  out=$(banner "Hello World" 2>&1)
  assert_contains "$out" "Hello World"
}

test_done_banner_renders_text() {
  local out
  out=$(done_banner "All done" 2>&1)
  assert_contains "$out" "All done"
}

test_no_color_disables_ansi_escapes_in_status_messages() {
  local out
  # Re-source lib.sh in a subshell with NO_COLOR set so USE_COLOR is recomputed.
  out=$(
    export NO_COLOR=1
    unset USE_COLOR
    # shellcheck disable=SC1091
    source "$REPO_ROOT/wizard/lib.sh"
    success "ok msg"
    warn "warn msg"
    info "info msg"
  )
  if [[ "$out" == *$'\033'* ]]; then
    echo "ANSI escapes leaked in NO_COLOR mode. Output was:" >&2
    printf '%s\n' "$out" | od -c | head >&2
    return 1
  fi
}

test_color_palette_constants_are_defined() {
  # Ensure the named color constants are set.
  [[ -n "${PRIMARY:-}" ]]   || { echo "PRIMARY undefined" >&2; return 1; }
  [[ -n "${HIGHLIGHT:-}" ]] || { echo "HIGHLIGHT undefined" >&2; return 1; }
  [[ -n "${OK:-}" ]]        || { echo "OK undefined" >&2; return 1; }
  [[ -n "${WARN_C:-}" ]]    || { echo "WARN_C undefined" >&2; return 1; }
  [[ -n "${ERR:-}" ]]       || { echo "ERR undefined" >&2; return 1; }
  [[ -n "${CHROME:-}" ]]    || { echo "CHROME undefined" >&2; return 1; }
}
