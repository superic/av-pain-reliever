#!/usr/bin/env bash
# tests/test_dry_run.sh — verify the --dry-run flag plumbing.

# shellcheck disable=SC1091
source "$REPO_ROOT/wizard/lib.sh"

WIZARD="$REPO_ROOT/wizard.sh"

test_runcmd_executes_when_dry_run_off() {
  DRY_RUN=0
  local out
  out=$(runcmd echo hello 2>&1)
  assert_eq "hello" "$out"
}

test_runcmd_skips_when_dry_run_on() {
  DRY_RUN=1
  local out
  out=$(runcmd touch /tmp/should-not-exist-$$ 2>&1)
  if [[ -e "/tmp/should-not-exist-$$" ]]; then
    rm -f "/tmp/should-not-exist-$$"
    echo "touch happened despite DRY_RUN=1" >&2
    return 1
  fi
  assert_contains "$out" "[dry-run]"
  assert_contains "$out" "would run"
}

test_runstep_uses_description_when_dry_run_on() {
  DRY_RUN=1
  local out
  out=$(runstep "regenerate the kitchen sink" echo this-should-not-print 2>&1)
  assert_contains "$out" "[dry-run]"
  assert_contains "$out" "regenerate the kitchen sink"
  if [[ "$out" == *this-should-not-print* ]]; then
    echo "underlying command ran despite DRY_RUN=1" >&2
    return 1
  fi
}

test_runstep_runs_underlying_command_when_dry_run_off() {
  DRY_RUN=0
  local out
  out=$(runstep "fake description" echo real-output 2>&1)
  assert_eq "real-output" "$out"
}

test_dryrun_banner_silent_when_off() {
  DRY_RUN=0
  local out
  out=$(dryrun_banner 2>&1)
  assert_eq "" "$out"
}

test_dryrun_banner_shown_when_on() {
  DRY_RUN=1
  local out
  out=$(dryrun_banner 2>&1)
  assert_contains "$out" "DRY-RUN MODE"
}

test_wizard_dispatcher_parses_dry_run_long_flag() {
  # Use the help subcommand because it doesn't actually do anything; we just
  # need to know the dispatcher accepted the flag without erroring.
  assert_exit_code 0 "$WIZARD" --dry-run help
}

test_wizard_dispatcher_parses_dry_run_short_flag() {
  assert_exit_code 0 "$WIZARD" -n help
}

test_wizard_help_mentions_dry_run() {
  local out
  out=$("$WIZARD" help 2>&1)
  assert_contains "$out" "--dry-run"
}

test_wizard_status_runs_normally_with_dry_run_flag() {
  # Status is read-only so dry-run is a no-op for it, but the flag should
  # parse cleanly and not break anything.
  assert_exit_code 0 "$WIZARD" --dry-run status
}

test_dry_run_default_is_zero() {
  unset DRY_RUN
  # shellcheck disable=SC1091
  source "$REPO_ROOT/wizard/lib.sh"
  assert_eq "0" "$DRY_RUN"
}

test_dry_run_respects_existing_env() {
  export DRY_RUN=1
  # shellcheck disable=SC1091
  source "$REPO_ROOT/wizard/lib.sh"
  assert_eq "1" "$DRY_RUN"
  unset DRY_RUN
}
