#!/usr/bin/env bash
# tests/run.sh — entry point for the wizard test suite. Source-and-run model:
# each test_*.sh defines functions named test_*; the framework discovers and
# runs them in their own subshells.

# shellcheck disable=SC1091
set -uo pipefail   # NOT -e: a failing test must not exit the runner
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$TESTS_DIR")"
export REPO_ROOT TESTS_DIR

source "$TESTS_DIR/_framework.sh"

PASS_TOTAL=0
FAIL_TOTAL=0

shopt -s nullglob
for f in "$TESTS_DIR"/test_*.sh; do
  TESTS_PASSED=0
  TESTS_FAILED=0
  # shellcheck disable=SC1090
  source "$f"
  run_all_tests_in_file "$f"
  PASS_TOTAL=$((PASS_TOTAL + TESTS_PASSED))
  FAIL_TOTAL=$((FAIL_TOTAL + TESTS_FAILED))
  echo
done

printf '%sSummary:%s %d passed, %d failed\n' "$BOLD" "$RESET" "$PASS_TOTAL" "$FAIL_TOTAL"

[[ "$FAIL_TOTAL" -eq 0 ]]
